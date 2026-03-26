{-# LANGUAGE OverloadedStrings #-}

-- | WAI application: serves the JSON API and static files (index.html, JS, CSS).
module UI.Server (runServer) where

import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types         (status200, status401, status404, hContentType)
import Network.Wai                (Application, Request, Response, responseLBS,
                                   requestMethod, pathInfo, strictRequestBody,
                                   requestHeaders)
import Network.Wai.Handler.Warp   (run)
import System.Directory            (getCurrentDirectory, doesFileExist)
import System.FilePath             ((</>))

import UI.Handlers

-- | Start the web server on the given port.
runServer :: Int -> IO ()
runServer port = do
  st <- newAppState
  cwd <- getCurrentDirectory
  let staticDir = cwd </> "static"
  putStrLn $ "Starting server on http://localhost:" ++ show port
  run port (app st staticDir)

-- | WAI application: routes API calls and serves static files.
app :: AppState -> FilePath -> Application
app st staticDir req respond = do
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

    -- ── Static files ──────────────────────────────────────────────────
    ("GET", [])  -> serveFile staticDir "index.html" respond
    ("GET", ps)  -> do
      let fileName = T.unpack (T.intercalate "/" ps)
      serveFile staticDir fileName respond

    _ -> respond $ responseLBS status404 [(hContentType, "text/plain")] "Not Found"

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
