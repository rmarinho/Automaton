{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

-- | OAuth2 authentication with GitHub, Google, Microsoft, and Apple.
module UI.Auth
  ( AuthConfig(..)
  , AuthState(..)
  , UserSession(..)
  , OAuthProvider(..)
  , newAuthState
  , getLoginUrl
  , handleOAuthCallback
  , getSession
  , deleteSession
  , sessionCookieName
  , availableProviders
  ) where

import Data.Aeson            (ToJSON(..), FromJSON(..), Value(..), (.:),
                              eitherDecode)
import qualified Data.Aeson.Key as Key
import Data.Aeson.Types      (parseMaybe, withObject)
import qualified Data.ByteString.Char8 as BS
import Data.IORef
import Data.Map.Strict       (Map)
import qualified Data.Map.Strict as Map
import Data.Text             (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock       (UTCTime, getCurrentTime)
import GHC.Generics          (Generic)
import Network.HTTP.Simple   (httpLBS, parseRequest, setRequestHeader,
                              setRequestBodyURLEncoded, getResponseBody,
                              getResponseStatusCode, setRequestMethod)
import Numeric               (showHex)
import System.Environment    (lookupEnv)
import System.Random         (randomRIO)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

data OAuthProvider = GitHub | Google | Microsoft | Apple
  deriving (Show, Eq, Ord, Generic)

instance ToJSON OAuthProvider
instance FromJSON OAuthProvider

data UserSession = UserSession
  { sessionUser     :: Text
  , sessionEmail    :: Maybe Text
  , sessionAvatar   :: Maybe Text
  , sessionProvider :: OAuthProvider
  , sessionCreated  :: UTCTime
  } deriving (Show, Generic)

instance ToJSON UserSession
instance FromJSON UserSession

data ProviderCfg = ProviderCfg
  { pcClientId     :: Text
  , pcClientSecret :: Text
  } deriving (Show)

data AuthConfig = AuthConfig
  { authGitHub       :: Maybe ProviderCfg
  , authGoogle       :: Maybe ProviderCfg
  , authMicrosoft    :: Maybe ProviderCfg
  , authApple        :: Maybe ProviderCfg
  , authRedirectBase :: Text
  } deriving (Show)

data AuthState = AuthState
  { authSessions :: IORef (Map Text UserSession)
  , authConfig   :: AuthConfig
  }

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------

loadAuthConfig :: IO AuthConfig
loadAuthConfig = do
  gh <- loadProvider "GITHUB_CLIENT_ID" "GITHUB_CLIENT_SECRET"
  go <- loadProvider "GOOGLE_CLIENT_ID" "GOOGLE_CLIENT_SECRET"
  ms <- loadProvider "MICROSOFT_CLIENT_ID" "MICROSOFT_CLIENT_SECRET"
  ap <- loadProvider "APPLE_CLIENT_ID" "APPLE_CLIENT_SECRET"
  rb <- maybe "http://localhost:8023" T.pack <$> lookupEnv "OAUTH_REDIRECT_BASE"
  return AuthConfig
    { authGitHub       = gh
    , authGoogle       = go
    , authMicrosoft    = ms
    , authApple        = ap
    , authRedirectBase = rb
    }

loadProvider :: String -> String -> IO (Maybe ProviderCfg)
loadProvider idVar secretVar = do
  mId     <- lookupEnv idVar
  mSecret <- lookupEnv secretVar
  case (mId, mSecret) of
    (Just cid, Just sec) ->
      return (Just ProviderCfg { pcClientId = T.pack cid, pcClientSecret = T.pack sec })
    _ -> return Nothing

-- | Create a fresh AuthState by reading config from the environment.
newAuthState :: IO AuthState
newAuthState = do
  cfg <- loadAuthConfig
  ref <- newIORef Map.empty
  return AuthState { authSessions = ref, authConfig = cfg }

-- ---------------------------------------------------------------------------
-- Session cookie
-- ---------------------------------------------------------------------------

sessionCookieName :: BS.ByteString
sessionCookieName = "automaton_session"

-- ---------------------------------------------------------------------------
-- Login URLs
-- ---------------------------------------------------------------------------

-- | Build the OAuth authorize URL for a given provider.
-- Returns empty text when the provider has no client ID configured.
getLoginUrl :: AuthConfig -> OAuthProvider -> Text
getLoginUrl cfg provider =
  case providerCfg cfg provider of
    Nothing -> ""
    Just pc ->
      let cid   = pcClientId pc
          redir = authRedirectBase cfg <> callbackPath provider
      in case provider of
           GitHub ->
             "https://github.com/login/oauth/authorize"
               <> "?client_id=" <> cid
               <> "&redirect_uri=" <> redir
               <> "&scope=read:user%20user:email"
           Google ->
             "https://accounts.google.com/o/oauth2/v2/auth"
               <> "?client_id=" <> cid
               <> "&redirect_uri=" <> redir
               <> "&response_type=code"
               <> "&scope=openid%20email%20profile"
           Microsoft ->
             "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
               <> "?client_id=" <> cid
               <> "&redirect_uri=" <> redir
               <> "&response_type=code"
               <> "&scope=openid%20email%20profile%20User.Read"
           Apple ->
             "https://appleid.apple.com/auth/authorize"
               <> "?client_id=" <> cid
               <> "&redirect_uri=" <> redir
               <> "&response_type=code"
               <> "&scope=name%20email"
               <> "&response_mode=query"

callbackPath :: OAuthProvider -> Text
callbackPath GitHub    = "/auth/callback/github"
callbackPath Google    = "/auth/callback/google"
callbackPath Microsoft = "/auth/callback/microsoft"
callbackPath Apple     = "/auth/callback/apple"

providerCfg :: AuthConfig -> OAuthProvider -> Maybe ProviderCfg
providerCfg cfg GitHub    = authGitHub cfg
providerCfg cfg Google    = authGoogle cfg
providerCfg cfg Microsoft = authMicrosoft cfg
providerCfg cfg Apple     = authApple cfg

-- ---------------------------------------------------------------------------
-- OAuth callback handling
-- ---------------------------------------------------------------------------

-- | Exchange an authorization code for a token, fetch user info, and
-- create a session.  Returns @(sessionId, user)@ on success.
handleOAuthCallback
  :: AuthState -> OAuthProvider -> Text
  -> IO (Either Text (Text, UserSession))
handleOAuthCallback as provider code = do
  let cfg = authConfig as
  case providerCfg cfg provider of
    Nothing -> return (Left "Provider not configured")
    Just pc -> do
      let redir = authRedirectBase cfg <> callbackPath provider
      tokenResult <- exchangeCode provider pc redir code
      case tokenResult of
        Left err -> return (Left err)
        Right tok -> do
          userResult <- fetchUserInfo provider tok
          case userResult of
            Left err -> return (Left err)
            Right sess -> do
              sid <- generateSessionId
              atomicModifyIORef' (authSessions as) (\m -> (Map.insert sid sess m, ()))
              return (Right (sid, sess))

-- ---------------------------------------------------------------------------
-- Token exchange
-- ---------------------------------------------------------------------------

exchangeCode :: OAuthProvider -> ProviderCfg -> Text -> Text -> IO (Either Text Text)
exchangeCode provider pc redirectUri code = do
  let tokenUrl = case provider of
        GitHub    -> "https://github.com/login/oauth/access_token"
        Google    -> "https://oauth2.googleapis.com/token"
        Microsoft -> "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        Apple     -> "https://appleid.apple.com/auth/token"

      formBody :: [(BS.ByteString, BS.ByteString)]
      formBody =
        [ ("client_id",     TE.encodeUtf8 (pcClientId pc))
        , ("client_secret", TE.encodeUtf8 (pcClientSecret pc))
        , ("code",          TE.encodeUtf8 code)
        , ("redirect_uri",  TE.encodeUtf8 redirectUri)
        ] ++ case provider of
               GitHub -> []
               _      -> [("grant_type", "authorization_code")]

  initReq <- parseRequest tokenUrl
  let req = setRequestMethod "POST"
          $ setRequestHeader "Accept" ["application/json"]
          $ setRequestBodyURLEncoded formBody initReq

  resp <- httpLBS req
  let status = getResponseStatusCode resp
      body   = getResponseBody resp

  if status >= 200 && status < 300
    then case eitherDecode body :: Either String Value of
           Left err -> return (Left (T.pack ("Token JSON parse error: " ++ err)))
           Right val -> return (extractToken val)
    else return (Left ("Token exchange failed (HTTP " <> T.pack (show status) <> ")"))

extractToken :: Value -> Either Text Text
extractToken val =
  case getTextField "access_token" val of
    Just t  -> Right t
    Nothing ->
      case getTextField "id_token" val of
        Just t  -> Right t
        Nothing -> Left "No access_token or id_token in response"

-- ---------------------------------------------------------------------------
-- User info
-- ---------------------------------------------------------------------------

fetchUserInfo :: OAuthProvider -> Text -> IO (Either Text UserSession)
fetchUserInfo provider token = do
  now <- getCurrentTime
  case provider of
    GitHub    -> fetchGitHubUser token now
    Google    -> fetchGoogleUser token now
    Microsoft -> fetchMicrosoftUser token now
    Apple     -> return (Right (appleUserFromToken now))

fetchGitHubUser :: Text -> UTCTime -> IO (Either Text UserSession)
fetchGitHubUser token now = do
  initReq <- parseRequest "https://api.github.com/user"
  let req = setRequestHeader "Authorization" ["Bearer " <> TE.encodeUtf8 token]
          $ setRequestHeader "User-Agent" ["automaton-designer"]
          $ setRequestHeader "Accept" ["application/json"] initReq
  resp <- httpLBS req
  let body = getResponseBody resp
  case eitherDecode body of
    Left err  -> return (Left (T.pack ("GitHub user parse error: " ++ err)))
    Right val -> return (Right (mkSession val "login" "name" "email" "avatar_url" GitHub now))

fetchGoogleUser :: Text -> UTCTime -> IO (Either Text UserSession)
fetchGoogleUser token now = do
  initReq <- parseRequest "https://www.googleapis.com/oauth2/v2/userinfo"
  let req = setRequestHeader "Authorization" ["Bearer " <> TE.encodeUtf8 token]
          $ setRequestHeader "Accept" ["application/json"] initReq
  resp <- httpLBS req
  let body = getResponseBody resp
  case eitherDecode body of
    Left err  -> return (Left (T.pack ("Google user parse error: " ++ err)))
    Right val -> return (Right (mkSession val "name" "name" "email" "picture" Google now))

fetchMicrosoftUser :: Text -> UTCTime -> IO (Either Text UserSession)
fetchMicrosoftUser token now = do
  initReq <- parseRequest "https://graph.microsoft.com/v1.0/me"
  let req = setRequestHeader "Authorization" ["Bearer " <> TE.encodeUtf8 token]
          $ setRequestHeader "Accept" ["application/json"] initReq
  resp <- httpLBS req
  let body = getResponseBody resp
  case eitherDecode body of
    Left err  -> return (Left (T.pack ("Microsoft user parse error: " ++ err)))
    Right val -> return (Right (mkSession val "displayName" "displayName" "mail" "" Microsoft now))

appleUserFromToken :: UTCTime -> UserSession
appleUserFromToken now =
  UserSession
    { sessionUser     = "Apple User"
    , sessionEmail    = Nothing
    , sessionAvatar   = Nothing
    , sessionProvider = Apple
    , sessionCreated  = now
    }

-- | Build a UserSession from a JSON object using the given field names.
mkSession :: Value -> Text -> Text -> Text -> Text -> OAuthProvider -> UTCTime -> UserSession
mkSession val idField nameField emailField avatarField provider now =
  let displayName = case getTextField nameField val of
                      Just n | not (T.null n) -> n
                      _ -> case getTextField idField val of
                             Just i  -> i
                             Nothing -> "Unknown"
  in UserSession
       { sessionUser     = displayName
       , sessionEmail    = getTextField emailField val
       , sessionAvatar   = if T.null avatarField then Nothing else getTextField avatarField val
       , sessionProvider = provider
       , sessionCreated  = now
       }

-- | Extract a text field from a JSON Value using aeson's parser.
getTextField :: Text -> Value -> Maybe Text
getTextField key = parseMaybe parser
  where
    parser = withObject "obj" (\obj -> obj .: Key.fromText key)

-- ---------------------------------------------------------------------------
-- Session management
-- ---------------------------------------------------------------------------

-- | Look up a session by its ID.
getSession :: AuthState -> Text -> IO (Maybe UserSession)
getSession as sid =
  Map.lookup sid <$> readIORef (authSessions as)

-- | Remove a session.
deleteSession :: AuthState -> Text -> IO ()
deleteSession as sid =
  atomicModifyIORef' (authSessions as) (\m -> (Map.delete sid m, ()))

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

generateSessionId :: IO Text
generateSessionId = do
  bytes <- mapM (\_ -> randomRIO (0 :: Int, 255)) [1..16 :: Int]
  return (T.pack (concatMap (\b -> let h = showHex b "" in if length h == 1 then '0':h else h) bytes))

-- | Return a list of (providerName, isConfigured) pairs.
availableProviders :: AuthConfig -> [(Text, Bool)]
availableProviders cfg =
  [ ("github",    isJust (authGitHub cfg))
  , ("google",    isJust (authGoogle cfg))
  , ("microsoft", isJust (authMicrosoft cfg))
  , ("apple",     isJust (authApple cfg))
  ]
  where isJust Nothing  = False
        isJust (Just _) = True
