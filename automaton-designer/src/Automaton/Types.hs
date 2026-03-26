{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Core algebraic data types for the automaton designer.
--
-- Defines strong types for states, symbols, transitions, automata,
-- simulation results, test cases, validation issues, and projects.
module Automaton.Types
  ( -- * Core Automaton Types
    State(..)
  , Symbol(..)
  , TransitionLabel(..)
  , Transition(..)
  , Automaton(..)
  , AutomatonType(..)
    -- * Simulation
  , SimStep(..)
  , SimResult(..)
    -- * Testing
  , TestCase(..)
  , TestResult(..)
    -- * Validation
  , ValidationIssue(..)
    -- * Visual Layout
  , Position(..)
  , Project(..)
    -- * Smart Constructors & Defaults
  , mkState
  , mkSymbol
  , emptyAutomaton
  , emptyProject
  ) where

import Data.Aeson       (ToJSON(..), FromJSON(..), ToJSONKey(..), FromJSONKey(..))
import Data.Aeson.Types (toJSONKeyText, FromJSONKeyFunction(..))
import Data.Map.Strict  (Map)
import qualified Data.Map.Strict as Map
import Data.Set         (Set)
import qualified Data.Set as Set
import Data.Text        (Text)
import GHC.Generics     (Generic)

-- ---------------------------------------------------------------------------
-- Core types
-- ---------------------------------------------------------------------------

-- | A state in an automaton, identified by a textual name.
newtype State = State { stateName :: Text }
  deriving (Eq, Ord, Show, Generic)

instance ToJSON State
instance FromJSON State
instance ToJSONKey State where
  toJSONKey = toJSONKeyText stateName
instance FromJSONKey State where
  fromJSONKey = FromJSONKeyText State

-- | A symbol in the automaton's input alphabet.
newtype Symbol = Symbol { symbolChar :: Char }
  deriving (Eq, Ord, Show, Generic)

instance ToJSON Symbol
instance FromJSON Symbol

-- | A transition label: either a concrete symbol or epsilon (ε).
data TransitionLabel
  = OnSymbol Symbol  -- ^ Transition on reading a specific symbol
  | OnEpsilon        -- ^ Epsilon transition (no input consumed)
  deriving (Eq, Ord, Show, Generic)

instance ToJSON TransitionLabel
instance FromJSON TransitionLabel

-- | A transition between two states, labelled with a symbol or epsilon.
data Transition = Transition
  { transFrom  :: !State            -- ^ Source state
  , transLabel :: !TransitionLabel   -- ^ Label (symbol or ε)
  , transTo    :: !State            -- ^ Target state
  } deriving (Eq, Ord, Show, Generic)

instance ToJSON Transition
instance FromJSON Transition

-- | The flavour of automaton.
data AutomatonType
  = DFA   -- ^ Deterministic Finite Automaton
  | NFA   -- ^ Non-deterministic Finite Automaton
  | ENFA  -- ^ NFA with ε-transitions
  deriving (Eq, Show, Read, Bounded, Enum, Generic)

instance ToJSON AutomatonType
instance FromJSON AutomatonType

-- | A complete automaton definition.
data Automaton = Automaton
  { automType        :: !AutomatonType     -- ^ DFA, NFA, or ε-NFA
  , automStates      :: !(Set State)       -- ^ Set of all states
  , automAlphabet    :: !(Set Symbol)      -- ^ Input alphabet
  , automStart       :: !State             -- ^ Initial state
  , automAccept      :: !(Set State)       -- ^ Accepting (final) states
  , automTransitions :: !(Set Transition)  -- ^ Transition relation
  } deriving (Eq, Show, Generic)

instance ToJSON Automaton
instance FromJSON Automaton

-- ---------------------------------------------------------------------------
-- Simulation types
-- ---------------------------------------------------------------------------

-- | A single step in a simulation trace.
data SimStep = SimStep
  { stepNumber       :: !Int             -- ^ Step index (0 = initial)
  , stepSymbol       :: !(Maybe Symbol)  -- ^ Symbol read (Nothing for initial)
  , stepActiveStates :: !(Set State)     -- ^ Active states after this step
  , stepRemaining    :: !Text            -- ^ Remaining input string
  } deriving (Eq, Show, Generic)

instance ToJSON SimStep
instance FromJSON SimStep

-- | The complete result of simulating an automaton on an input string.
data SimResult = SimResult
  { simAccepted :: !Bool       -- ^ Whether the input was accepted
  , simSteps    :: ![SimStep]  -- ^ Step-by-step trace
  , simInput    :: !Text       -- ^ Original input string
  } deriving (Eq, Show, Generic)

instance ToJSON SimResult
instance FromJSON SimResult

-- ---------------------------------------------------------------------------
-- Test-case types
-- ---------------------------------------------------------------------------

-- | A test case: an input string and its expected acceptance result.
data TestCase = TestCase
  { testInput    :: !Text  -- ^ Input string to test
  , testExpected :: !Bool  -- ^ Expected acceptance result
  } deriving (Eq, Show, Generic)

instance ToJSON TestCase
instance FromJSON TestCase

-- | Result of running a single test case.
data TestResult = TestResult
  { trTestCase :: !TestCase  -- ^ The original test case
  , trPassed   :: !Bool      -- ^ Whether actual == expected
  , trActual   :: !Bool      -- ^ Actual acceptance result
  } deriving (Eq, Show, Generic)

instance ToJSON TestResult
instance FromJSON TestResult

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

-- | Issues found during structural validation of an automaton.
data ValidationIssue
  = UnreachableState State
  | UndefinedSymbolInTransition Symbol Transition
  | DuplicateTransition Transition
  | MissingStartState
  | StartStateNotInStates State
  | AcceptStateNotInStates State
  | TransitionFromUndefinedState Transition
  | TransitionToUndefinedState Transition
  | NonDeterministicTransition State Symbol
  deriving (Eq, Show)

-- ---------------------------------------------------------------------------
-- Visual layout / project
-- ---------------------------------------------------------------------------

-- | A position on the visual canvas (pixels).
data Position = Position
  { posX :: !Double
  , posY :: !Double
  } deriving (Eq, Show, Generic)

instance ToJSON Position
instance FromJSON Position

-- | A complete project: automaton + layout + test cases + DSL source.
data Project = Project
  { projAutomaton :: !Automaton
  , projLayout    :: !(Map State Position)
  , projTestCases :: ![TestCase]
  , projDslText   :: !Text
  } deriving (Eq, Show, Generic)

instance ToJSON Project
instance FromJSON Project

-- ---------------------------------------------------------------------------
-- Smart constructors & defaults
-- ---------------------------------------------------------------------------

mkState :: Text -> State
mkState = State

mkSymbol :: Char -> Symbol
mkSymbol = Symbol

-- | An empty DFA with a single start state.
emptyAutomaton :: Automaton
emptyAutomaton = Automaton
  { automType        = DFA
  , automStates      = Set.singleton (State "q0")
  , automAlphabet    = Set.empty
  , automStart       = State "q0"
  , automAccept      = Set.empty
  , automTransitions = Set.empty
  }

-- | An empty project with default layout.
emptyProject :: Project
emptyProject = Project
  { projAutomaton = emptyAutomaton
  , projLayout    = Map.singleton (State "q0") (Position 400 300)
  , projTestCases = []
  , projDslText   = ""
  }
