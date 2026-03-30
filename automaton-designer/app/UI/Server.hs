{-# LANGUAGE OverloadedStrings #-}

-- | WAI application: serves the JSON API and static files (index.html, JS, CSS).
module UI.Server (runServer) where

import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson             (encode)
import qualified Data.Map.Strict as Map
import Network.HTTP.Types     (status200, status302, status401, status404,
                               hContentType, hLocation)
import Network.Wai            (Application, Request, Response, responseLBS,
                               requestMethod, pathInfo, strictRequestBody,
                               requestHeaders, queryString)
import Network.Wai.Handler.Warp (run)
import System.Directory        (getCurrentDirectory, doesFileExist)
import System.FilePath         ((</>))

import UI.Auth
import UI.Handlers

-- | Start the web server on the given port.
runServer :: Int -> IO ()
runServer port = do
  st  <- newAppState
  ast <- newAuthState
  cwd <- getCurrentDirectory
  let staticDir = cwd </> "static"
  putStrLn $ "Starting server on http://localhost:" ++ show port
  run port (app st ast staticDir)

-- | WAI application: routes API calls and serves static files.
app :: AppState -> AuthState -> FilePath -> Application
app st ast staticDir req respond = do
  let method = requestMethod req
      path   = pathInfo req

  case (method, path) of
    -- ── JSON API ──────────────────────────────────────────────────────
    ("GET",  ["api", "state"])    -> handleIO (handleGetState st) respond
    ("POST", ["api", "parse"])    -> handleBodyIO (handleParse st) req respond
    ("POST", ["api", "simulate"]) -> handleBodyIO (handleSimulate st) req respond
    ("POST", ["api", "test"])     -> handleBodyIO (handleRunTests st) req respond
    ("POST", ["api", "validate"]) -> handleIO (handleValidate st) respond
    ("POST", ["api", "convert"])  -> handleIO (handleConvert st) respond
    ("POST", ["api", "save"])     -> handleIO (handleSave st) respond

    -- ── Chat (token-protected) ────────────────────────────────────────
    ("POST", ["api", "chat"])     -> withAuth st req respond $
                                       handleBodyIO (handleChat st) req respond

    -- ── Settings ──────────────────────────────────────────────────────
    ("GET",  ["api", "settings"]) -> handleIO (handleGetSettings st) respond
    ("POST", ["api", "settings"]) -> handleBodyIO (handleSaveSettings st) req respond

    -- ── OAuth login redirects ─────────────────────────────────────────
    ("GET", ["auth", "github"])    -> redirectToProvider ast GitHub respond
    ("GET", ["auth", "google"])    -> redirectToProvider ast Google respond
    ("GET", ["auth", "microsoft"]) -> redirectToProvider ast Microsoft respond
    ("GET", ["auth", "apple"])     -> redirectToProvider ast Apple respond

    -- ── OAuth callbacks ───────────────────────────────────────────────
    ("GET", ["auth", "callback", "github"])    -> handleAuthCallback ast GitHub req respond
    ("GET", ["auth", "callback", "google"])    -> handleAuthCallback ast Google req respond
    ("GET", ["auth", "callback", "microsoft"]) -> handleAuthCallback ast Microsoft req respond
    ("GET", ["auth", "callback", "apple"])     -> handleAuthCallback ast Apple req respond

    -- ── Auth API ──────────────────────────────────────────────────────
    ("GET",  ["api", "auth", "providers"]) -> handleAuthProviders ast respond
    ("GET",  ["api", "auth", "me"])     -> handleAuthMe ast req respond
    ("POST", ["api", "auth", "logout"]) -> handleAuthLogout ast req respond

    -- ── Static files ──────────────────────────────────────────────────
    ("GET", [])  -> serveFile staticDir "index.html" respond
    ("GET", ps)  -> do
      let fileName = T.unpack (T.intercalate "/" ps)
      serveFile staticDir fileName respond

    _ -> respond $ responseLBS status404 [(hContentType, "text/plain")] "Not Found"

-- ---------------------------------------------------------------------------
-- Original helpers
-- ---------------------------------------------------------------------------

-- | Handle an IO action that returns JSON bytes.
handleIO :: IO BL.ByteString -> (Network.Wai.Response -> IO b) -> IO b
handleIO action respond = do
  result <- action
  respond $ responseLBS status200 [(hContentType, "application/json")] result

-- | Handle a request with a body.
handleBodyIO :: (BL.ByteString -> IO BL.ByteString) -> Request -> (Response -> IO b) -> IO b
handleBodyIO handler req respond = do
  body   <- strictRequestBody req
  result <- handler body
  respond $ responseLBS status200 [(hContentType, "application/json")] result

-- | Serve a static file from the static directory.
serveFile :: FilePath -> String -> (Response -> IO b) -> IO b
serveFile dir name respond = do
  let cleanName = filter (\c -> c /= '\'' && c /= '"') name
      filePath  = dir </> cleanName
  exists <- doesFileExist filePath
  if exists
    then do
      content <- BL.readFile filePath
      let ct = contentType cleanName
      respond $ responseLBS status200 [(hContentType, ct)] content
    else respond $ responseLBS status404 [(hContentType, "text/plain")] "Not Found"

-- | Guess content type from file extension.
contentType :: String -> BS.ByteString
contentType name
  | endsWith ".html" = "text/html; charset=utf-8"
  | endsWith ".js"   = "application/javascript"
  | endsWith ".css"  = "text/css"
  | endsWith ".json" = "application/json"
  | endsWith ".svg"  = "image/svg+xml"
  | otherwise        = "application/octet-stream"
  where
    endsWith suffix = drop (length name - length suffix) name == suffix

-- | Check bearer token before executing an action.
withAuth :: AppState -> Request -> (Response -> IO b) -> IO b -> IO b
withAuth st req respond action = do
  let authHeader = lookup "Authorization" (requestHeaders req)
      bearer     = fmap (T.strip . TE.decodeUtf8 . BS.drop 7) authHeader
  ok <- checkApiToken st bearer
  if ok
    then action
    else respond $ responseLBS status401
           [(hContentType, "application/json")]
           "{\"error\":\"Unauthorized\"}"

-- ---------------------------------------------------------------------------
-- Auth route handlers
-- ---------------------------------------------------------------------------

-- | Redirect the user to the OAuth provider's authorize URL.
redirectToProvider :: AuthState -> OAuthProvider -> (Response -> IO b) -> IO b
redirectToProvider ast provider respond = do
  let url = getLoginUrl (authConfig ast) provider
  if T.null url
    then respond $ responseLBS status404
           [(hContentType, "text/plain")]
           "OAuth provider not configured"
    else respond $ responseLBS status302
           [ (hLocation, TE.encodeUtf8 url)
           , (hContentType, "text/plain")
           ] "Redirecting..."

-- | Handle the OAuth callback: exchange code, create session, set cookie, redirect.
handleAuthCallback :: AuthState -> OAuthProvider -> Request -> (Response -> IO b) -> IO b
handleAuthCallback ast provider req respond = do
  let qs   = queryString req
      code = lookup "code" qs
  case code of
    Just (Just c) -> do
      result <- handleOAuthCallback ast provider (TE.decodeUtf8 c)
      case result of
        Right (sid, _sess) ->
          respond $ responseLBS status302
            [ (hLocation, "/")
            , ("Set-Cookie", mkSessionCookie sid)
            , (hContentType, "text/plain")
            ] "Redirecting..."
        Left err ->
          respond $ responseLBS status401
            [(hContentType, "application/json")]
            (BL.fromStrict (TE.encodeUtf8 ("{\"error\":" <> T.pack (show err) <> "}")))
    _ ->
      respond $ responseLBS status401
        [(hContentType, "application/json")]
        "{\"error\":\"Missing code parameter\"}"

-- | Return which OAuth providers are configured.
handleAuthProviders :: AuthState -> (Response -> IO b) -> IO b
handleAuthProviders ast respond = do
  let providers = availableProviders (authConfig ast)
      json = encode $ Map.fromList providers
  respond $ responseLBS status200 [(hContentType, "application/json")] json

-- | Return the current user's session as JSON, or 401.
handleAuthMe :: AuthState -> Request -> (Response -> IO b) -> IO b
handleAuthMe ast req respond = do
  let msid = extractSessionCookie req
  case msid of
    Nothing -> respond $ responseLBS status401
                 [(hContentType, "application/json")]
                 "{\"error\":\"Not authenticated\"}"
    Just sid -> do
      mSess <- getSession ast sid
      case mSess of
        Nothing -> respond $ responseLBS status401
                     [(hContentType, "application/json")]
                     "{\"error\":\"Session expired\"}"
        Just sess -> respond $ responseLBS status200
                       [(hContentType, "application/json")]
                       (encode sess)

-- | Delete the session and clear the cookie.
handleAuthLogout :: AuthState -> Request -> (Response -> IO b) -> IO b
handleAuthLogout ast req respond = do
  let msid = extractSessionCookie req
  case msid of
    Just sid -> deleteSession ast sid
    Nothing  -> return ()
  respond $ responseLBS status200
    [ (hContentType, "application/json")
    , ("Set-Cookie", sessionCookieName <> "=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0")
    ] "{\"ok\":true}"

-- ---------------------------------------------------------------------------
-- Cookie helpers
-- ---------------------------------------------------------------------------

-- | Build a Set-Cookie value for the session.
mkSessionCookie :: T.Text -> BS.ByteString
mkSessionCookie sid =
  sessionCookieName <> "=" <> TE.encodeUtf8 sid
    <> "; Path=/; HttpOnly; SameSite=Lax; Max-Age=86400"

-- | Extract the session ID from the Cookie header.
extractSessionCookie :: Request -> Maybe T.Text
extractSessionCookie req = do
  cookieHeader <- lookup "Cookie" (requestHeaders req)
  let cookies = parseCookies cookieHeader
  lookup (TE.decodeUtf8 sessionCookieName) cookies

-- | Simple cookie parser: "k1=v1; k2=v2" -> [(k, v)]
parseCookies :: BS.ByteString -> [(T.Text, T.Text)]
parseCookies bs =
  let txt    = TE.decodeUtf8 bs
      pairs  = T.splitOn ";" txt
  in concatMap parsePair pairs
  where
    parsePair p =
      let stripped = T.strip p
      in case T.breakOn "=" stripped of
           (k, rest)
             | T.null rest -> []
             | otherwise   -> [(T.strip k, T.strip (T.drop 1 rest))]
