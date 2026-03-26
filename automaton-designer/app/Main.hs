{-# LANGUAGE OverloadedStrings #-}

-- | Application entry point.
--
-- Starts a local Warp web server serving the automaton designer UI.
module Main (main) where

import UI.Server (runServer)

main :: IO ()
main = do
  putStrLn "╔══════════════════════════════════════════════════╗"
  putStrLn "║       Automaton Designer — starting…             ║"
  putStrLn "║  Open  http://localhost:8023  in your browser    ║"
  putStrLn "╚══════════════════════════════════════════════════╝"
  runServer 8023
