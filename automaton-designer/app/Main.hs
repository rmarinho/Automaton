{-# LANGUAGE OverloadedStrings #-}

-- | Application entry point.
--
-- Starts a local Warp web server serving the automaton designer UI.
-- Port is configurable via the PORT environment variable (default: 8023).
module Main (main) where

import System.Environment (lookupEnv)
import Text.Read          (readMaybe)
import UI.Server          (runServer)

main :: IO ()
main = do
  mPort <- lookupEnv "PORT"
  let port = maybe 8023 (\p -> maybe 8023 id (readMaybe p)) mPort
  putStrLn "╔══════════════════════════════════════════════════╗"
  putStrLn $ "║  Automaton Designer — port " ++ show port ++ replicate (24 - length (show port)) ' ' ++ "║"
  putStrLn "╚══════════════════════════════════════════════════╝"
  runServer port
