{-# LANGUAGE OverloadedStrings #-}

-- | JSON API handlers for the automaton designer web UI.
module UI.Handlers
  ( AppState(..)
  , newAppState
  , handleParse
  , handleSimulate
  , handleRunTests
  , handleValidate
  , handleConvert
  , handleGetState
  , handleSave
  ) where

import Data.Aeson            (ToJSON(..), FromJSON(..), object, (.=), (.:),
                              eitherDecode, encode)
import Data.Aeson.Encode.Pretty (encodePretty)
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import Data.Map.Strict       (Map)
import qualified Data.Map.Strict as Map
import Data.Set              (Set)
import qualified Data.Set as Set
import Data.Text             (Text)
import qualified Data.Text as T
import GHC.Generics          (Generic)

import Automaton.Types
import Automaton.Parser      (parseAutomaton, formatAutomaton)
import Automaton.Simulator   (simulate, runTests)
import Automaton.Validator   (validate, formatIssue)
import Automaton.Converter   (nfaToDfa)
import Automaton.Serializer  (saveProject)

-- | Server-side application state.
data AppState = AppState
  { asAutomaton :: IORef Automaton
  , asLayout    :: IORef (Map State Position)
  , asTests     :: IORef [TestCase]
  }

newAppState :: IO AppState
newAppState = do
  autRef    <- newIORef sampleDfa
  layoutRef <- newIORef (circularLayout sampleDfa)
  testsRef  <- newIORef sampleTests
  return (AppState autRef layoutRef testsRef)

-- ---------------------------------------------------------------------------
-- Handlers (return lazy ByteString JSON responses)
-- ---------------------------------------------------------------------------

-- | GET /api/state — return current automaton + layout + tests as JSON
handleGetState :: AppState -> IO BL.ByteString
handleGetState st = do
  aut    <- readIORef (asAutomaton st)
  layout <- readIORef (asLayout st)
  tests  <- readIORef (asTests st)
  let dsl = formatAutomaton aut
  return $ encode $ object
    [ "automaton" .= aut
    , "layout"    .= layoutToJson aut layout
    , "tests"     .= tests
    , "dsl"       .= dsl
    ]

-- | POST /api/parse — parse DSL text, update state, return automaton
handleParse :: AppState -> BL.ByteString -> IO BL.ByteString
handleParse st body = do
  let mReq = eitherDecode body :: Either String ParseReq
  case mReq of
    Left err -> return $ encode $ object ["error" .= ("Invalid request: " <> T.pack err)]
    Right (ParseReq dslText) ->
      case parseAutomaton dslText of
        Left err -> return $ encode $ object
          ["error" .= T.pack err, "ok" .= False]
        Right aut -> do
          let layout = circularLayout aut
          writeIORef (asAutomaton st) aut
          writeIORef (asLayout st) layout
          return $ encode $ object
            [ "ok"        .= True
            , "automaton" .= aut
            , "layout"    .= layoutToJson aut layout
            ]

-- | POST /api/simulate — run simulation on input string
handleSimulate :: AppState -> BL.ByteString -> IO BL.ByteString
handleSimulate st body = do
  let mReq = eitherDecode body :: Either String SimReq
  case mReq of
    Left err -> return $ encode $ object ["error" .= T.pack err]
    Right (SimReq input) -> do
      aut <- readIORef (asAutomaton st)
      let result = simulate aut input
      return $ encode result

-- | POST /api/test — run all test cases
handleRunTests :: AppState -> BL.ByteString -> IO BL.ByteString
handleRunTests st body = do
  let mReq = eitherDecode body :: Either String TestReq
  case mReq of
    Left _ -> do
      -- Use stored tests
      aut   <- readIORef (asAutomaton st)
      tests <- readIORef (asTests st)
      let results = runTests aut tests
      return $ encode results
    Right (TestReq tests) -> do
      -- Update stored tests and run
      writeIORef (asTests st) tests
      aut <- readIORef (asAutomaton st)
      let results = runTests aut tests
      return $ encode results

-- | POST /api/validate — validate the current automaton
handleValidate :: AppState -> IO BL.ByteString
handleValidate st = do
  aut <- readIORef (asAutomaton st)
  let issues = validate aut
      msgs   = map formatIssue issues
  return $ encode $ object
    [ "valid"  .= null issues
    , "issues" .= msgs
    ]

-- | POST /api/convert — convert NFA/ε-NFA to DFA
handleConvert :: AppState -> IO BL.ByteString
handleConvert st = do
  aut <- readIORef (asAutomaton st)
  let dfa    = nfaToDfa aut
      layout = circularLayout dfa
  writeIORef (asAutomaton st) dfa
  writeIORef (asLayout st) layout
  return $ encode $ object
    [ "automaton" .= dfa
    , "layout"    .= layoutToJson dfa layout
    , "dsl"       .= formatAutomaton dfa
    ]

-- | POST /api/save — save project to disk
handleSave :: AppState -> IO BL.ByteString
handleSave st = do
  aut    <- readIORef (asAutomaton st)
  layout <- readIORef (asLayout st)
  tests  <- readIORef (asTests st)
  let proj = Project aut layout tests (formatAutomaton aut)
  saveProject "automaton-project.json" proj
  return $ encode $ object ["ok" .= True, "file" .= ("automaton-project.json" :: Text)]

-- ---------------------------------------------------------------------------
-- Request types
-- ---------------------------------------------------------------------------

data ParseReq = ParseReq { prDsl :: Text }
instance FromJSON ParseReq where
  parseJSON v = do
    o <- parseJSON v
    ParseReq <$> o .: "dsl"

data SimReq = SimReq { srInput :: Text }
instance FromJSON SimReq where
  parseJSON v = do
    o <- parseJSON v
    SimReq <$> o .: "input"

data TestReq = TestReq { trTests :: [TestCase] }
instance FromJSON TestReq where
  parseJSON v = do
    o <- parseJSON v
    TestReq <$> o .: "tests"

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

circularLayout :: Automaton -> Map State Position
circularLayout aut =
  let states = Set.toList (automStates aut)
      n      = length states
      cx     = 400.0
      cy     = 300.0
      radius = min 220 (fromIntegral n * 50)
  in Map.fromList
    [ (s, Position (cx + radius * cos angle) (cy + radius * sin angle))
    | (i, s) <- zip [0..] states
    , let angle = 2 * pi * fromIntegral i / fromIntegral (max 1 n) - pi/2
    ]

layoutToJson :: Automaton -> Map State Position -> [LayoutEntry]
layoutToJson aut layout =
  [ LayoutEntry (stateName s) (posX p) (posY p)
      (s == automStart aut) (s `Set.member` automAccept aut)
  | s <- Set.toList (automStates aut)
  , let p = Map.findWithDefault (Position 100 100) s layout
  ]

data LayoutEntry = LayoutEntry
  { leName     :: Text
  , leX        :: Double
  , leY        :: Double
  , leIsStart  :: Bool
  , leIsAccept :: Bool
  } deriving (Generic)

instance ToJSON LayoutEntry where
  toJSON (LayoutEntry n x y s a) = object
    [ "name" .= n, "x" .= x, "y" .= y, "isStart" .= s, "isAccept" .= a ]

-- ---------------------------------------------------------------------------
-- Sample data
-- ---------------------------------------------------------------------------

sampleDfa :: Automaton
sampleDfa = case parseAutomaton sampleDsl of
  Right a -> a
  Left _  -> emptyAutomaton

sampleDsl :: Text
sampleDsl = T.unlines
  [ "automaton DFA"
  , "alphabet: a,b"
  , "states: q0,q1,q2"
  , "start: q0"
  , "accept: q2"
  , "transitions:"
  , "  q0,a -> q1"
  , "  q0,b -> q0"
  , "  q1,a -> q1"
  , "  q1,b -> q2"
  , "  q2,a -> q1"
  , "  q2,b -> q0"
  ]

sampleTests :: [TestCase]
sampleTests =
  [ TestCase "ab"   True
  , TestCase "aab"  True
  , TestCase "abb"  False
  , TestCase "bab"  True
  , TestCase ""     False
  , TestCase "abab" True
  ]
