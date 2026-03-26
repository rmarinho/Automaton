{-# LANGUAGE OverloadedStrings #-}

-- | JSON and DSL serialization / deserialization for automata and projects.
module Automaton.Serializer
  ( saveProject
  , loadProject
  , exportJson
  , importJson
  , saveDsl
  , loadDsl
  ) where

import Data.Aeson              (eitherDecode)
import Data.Aeson.Encode.Pretty (encodePretty)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text.IO         as TIO
import System.Directory        (doesFileExist)

import Automaton.Types
import Automaton.Parser (formatAutomaton, parseAutomaton)

-- ---------------------------------------------------------------------------
-- Project (JSON)
-- ---------------------------------------------------------------------------

-- | Save a project to a JSON file.
saveProject :: FilePath -> Project -> IO ()
saveProject path proj = BL.writeFile path (encodePretty proj)

-- | Load a project from a JSON file.
loadProject :: FilePath -> IO (Either String Project)
loadProject path = do
  exists <- doesFileExist path
  if exists
    then eitherDecode <$> BL.readFile path
    else return $ Left $ "File not found: " ++ path

-- ---------------------------------------------------------------------------
-- Automaton (JSON)
-- ---------------------------------------------------------------------------

-- | Export an automaton as pretty-printed JSON bytes.
exportJson :: Automaton -> BL.ByteString
exportJson = encodePretty

-- | Import an automaton from JSON bytes.
importJson :: BL.ByteString -> Either String Automaton
importJson = eitherDecode

-- ---------------------------------------------------------------------------
-- Automaton (DSL text)
-- ---------------------------------------------------------------------------

-- | Save an automaton to a DSL text file.
saveDsl :: FilePath -> Automaton -> IO ()
saveDsl path = TIO.writeFile path . formatAutomaton

-- | Load an automaton from a DSL text file.
loadDsl :: FilePath -> IO (Either String Automaton)
loadDsl path = do
  exists <- doesFileExist path
  if exists
    then parseAutomaton <$> TIO.readFile path
    else return $ Left $ "File not found: " ++ path
