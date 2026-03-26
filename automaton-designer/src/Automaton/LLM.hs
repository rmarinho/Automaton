{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

-- | LLM integration: call Anthropic or OpenAI-compatible APIs for
-- automaton-focused chat assistance.
module Automaton.LLM
  ( LLMProvider(..)
  , LLMConfig(..)
  , ChatMessage(..)
  , ChatRole(..)
  , chatCompletion
  , defaultConfig
  , systemPrompt
  ) where

import Data.Aeson           (ToJSON(..), FromJSON(..), Value(..), object, (.=), (.:),
                             eitherDecode, encode, withObject, withText)
import Data.Aeson.Types     (parseMaybe)
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Char8 as BS
import Data.Text            (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import GHC.Generics         (Generic)
import Network.HTTP.Simple  (httpLBS, getResponseBody, getResponseStatusCode,
                             setRequestBodyLBS, setRequestHeader,
                             setRequestMethod, parseRequest)

-- | Supported LLM providers.
data LLMProvider = Anthropic | OpenAICompat
  deriving (Show, Eq, Generic)

instance ToJSON LLMProvider
instance FromJSON LLMProvider

-- | LLM configuration.
data LLMConfig = LLMConfig
  { llmProvider :: LLMProvider
  , llmEndpoint :: Text
  , llmApiKey   :: Text
  , llmModel    :: Text
  } deriving (Show, Generic)

instance ToJSON LLMConfig
instance FromJSON LLMConfig

-- | Chat message role.
data ChatRole = RoleSystem | RoleUser | RoleAssistant
  deriving (Show, Eq, Generic)

instance ToJSON ChatRole where
  toJSON RoleSystem    = "system"
  toJSON RoleUser      = "user"
  toJSON RoleAssistant = "assistant"

instance FromJSON ChatRole where
  parseJSON = withText "ChatRole" $ \t -> case t of
    "system"    -> pure RoleSystem
    "user"      -> pure RoleUser
    "assistant" -> pure RoleAssistant
    _           -> fail $ "Unknown role: " ++ T.unpack t

-- | A single chat message.
data ChatMessage = ChatMessage
  { msgRole    :: ChatRole
  , msgContent :: Text
  } deriving (Show, Generic)

instance ToJSON ChatMessage where
  toJSON (ChatMessage r c) = object ["role" .= r, "content" .= c]

instance FromJSON ChatMessage where
  parseJSON = withObject "ChatMessage" $ \o ->
    ChatMessage <$> o .: "role" <*> o .: "content"

-- | Default (empty) config.
defaultConfig :: LLMConfig
defaultConfig = LLMConfig Anthropic
  "https://api.anthropic.com/v1/messages" "" "claude-sonnet-4-20250514"

-- | System prompt for automaton-focused assistance.
systemPrompt :: Text -> Text
systemPrompt dsl = T.unlines
  [ "You are an automata theory assistant in the Automaton Designer app."
  , "Help users understand and design finite automata (DFA, NFA, ε-NFA)."
  , "Explain concepts, help write DSL definitions, analyze automata,"
  , "suggest improvements, answer formal language theory questions."
  , ""
  , "DSL format:"
  , "  automaton DFA|NFA|ENFA"
  , "  alphabet: a,b,..."
  , "  states: q0,q1,..."
  , "  start: q0"
  , "  accept: q2,..."
  , "  transitions:"
  , "    state,symbol -> target"
  , "    state,eps -> target  (epsilon, ENFA only)"
  , ""
  , if T.null dsl then "No automaton loaded."
    else "Current automaton:\n" <> dsl
  ]

-- | Call the configured LLM and return the assistant's reply.
chatCompletion :: LLMConfig -> [ChatMessage] -> IO (Either Text Text)
chatCompletion cfg msgs
  | T.null (llmApiKey cfg) = return $ Left "No API key configured"
  | otherwise = case llmProvider cfg of
      Anthropic    -> callAnthropic cfg msgs
      OpenAICompat -> callOpenAI cfg msgs

-- | Call Anthropic Messages API.
callAnthropic :: LLMConfig -> [ChatMessage] -> IO (Either Text Text)
callAnthropic cfg msgs = do
  let sysText = T.concat [msgContent m | m <- msgs, msgRole m == RoleSystem]
      nonSys  = [m | m <- msgs, msgRole m /= RoleSystem]
      body    = encode $ object
        [ "model"      .= llmModel cfg
        , "max_tokens" .= (2048 :: Int)
        , "system"     .= sysText
        , "messages"   .= nonSys
        ]
  callAPI cfg body extractAnthropic

-- | Call OpenAI-compatible API (Llama, Copilot, etc.).
callOpenAI :: LLMConfig -> [ChatMessage] -> IO (Either Text Text)
callOpenAI cfg msgs = do
  let body = encode $ object
        [ "model"      .= llmModel cfg
        , "max_tokens" .= (2048 :: Int)
        , "messages"   .= msgs
        ]
  callAPI cfg body extractOpenAI

-- | Make HTTP request to LLM API.
callAPI :: LLMConfig -> BL.ByteString -> (BL.ByteString -> Either Text Text)
        -> IO (Either Text Text)
callAPI cfg reqBody extractor = do
  reqInit <- parseRequest (T.unpack (llmEndpoint cfg))
  let req = setRequestMethod "POST"
          $ setRequestBodyLBS reqBody
          $ setRequestHeader "Content-Type" ["application/json"]
          $ setRequestHeader "Authorization"
              [BS.pack $ "Bearer " ++ T.unpack (llmApiKey cfg)]
          $ setRequestHeader "x-api-key" [TE.encodeUtf8 (llmApiKey cfg)]
          $ setRequestHeader "anthropic-version" ["2023-06-01"]
          $ setRequestHeader "Copilot-Integration-Id" ["automaton-designer"]
          $ reqInit
  resp <- httpLBS req
  let status = getResponseStatusCode resp
      body   = getResponseBody resp
  if status >= 200 && status < 300
    then return (extractor body)
    else return $ Left $ "API error (HTTP " <> T.pack (show status) <> ")"

-- | Extract text from Anthropic response: { content: [{text: "..."}] }
extractAnthropic :: BL.ByteString -> Either Text Text
extractAnthropic body = case eitherDecode body of
  Left err -> Left (T.pack err)
  Right val ->
    case parseMaybe extractA val of
      Just t  -> Right t
      Nothing -> Left "Could not parse Anthropic response"
  where
    extractA = withObject "resp" $ \o -> do
      Array arr <- o .: "content"
      case V.toList arr of
        (first:_) -> withObject "block" (.: "text") first
        []        -> fail "empty content"

-- | Extract text from OpenAI response: { choices: [{message:{content:"..."}}] }
extractOpenAI :: BL.ByteString -> Either Text Text
extractOpenAI body = case eitherDecode body of
  Left err -> Left (T.pack err)
  Right val ->
    case parseMaybe extractO val of
      Just t  -> Right t
      Nothing -> Left "Could not parse OpenAI response"
  where
    extractO = withObject "resp" $ \o -> do
      Array arr <- o .: "choices"
      case V.toList arr of
        (first:_) -> withObject "choice" (\c -> do
          msg <- c .: "message"
          withObject "msg" (.: "content") msg) first
        [] -> fail "empty choices"
