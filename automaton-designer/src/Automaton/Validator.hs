{-# LANGUAGE OverloadedStrings #-}

-- | Structural validation for automata.
--
-- Checks for unreachable states, undefined symbols in transitions,
-- states referenced in transitions but not declared, determinism
-- violations (for DFA), and other structural issues.
module Automaton.Validator
  ( validate
  , isValid
  , formatIssue
  ) where

import Data.Set  (Set)
import qualified Data.Set  as Set
import Data.Text (Text)
import qualified Data.Text as T

import Automaton.Types

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | Validate an automaton and return all structural issues found.
validate :: Automaton -> [ValidationIssue]
validate aut = concat
  [ checkStartState aut
  , checkAcceptStates aut
  , checkTransitionStates aut
  , checkTransitionSymbols aut
  , checkUnreachableStates aut
  , checkDeterminism aut
  ]

-- | Check whether an automaton is free of structural issues.
isValid :: Automaton -> Bool
isValid = null . validate

-- | Format a 'ValidationIssue' as a human-readable message.
formatIssue :: ValidationIssue -> Text
formatIssue (UnreachableState s) =
  "Unreachable state: " <> stateName s
formatIssue (UndefinedSymbolInTransition sym tr) =
  "Symbol '" <> T.singleton (symbolChar sym) <> "' in transition "
  <> fmtTrans tr <> " is not in the alphabet"
formatIssue (DuplicateTransition tr) =
  "Duplicate transition: " <> fmtTrans tr
formatIssue MissingStartState =
  "No start state defined"
formatIssue (StartStateNotInStates s) =
  "Start state " <> stateName s <> " is not in the set of states"
formatIssue (AcceptStateNotInStates s) =
  "Accept state " <> stateName s <> " is not in the set of states"
formatIssue (TransitionFromUndefinedState tr) =
  "Transition from undefined state: " <> fmtTrans tr
formatIssue (TransitionToUndefinedState tr) =
  "Transition to undefined state: " <> fmtTrans tr
formatIssue (NonDeterministicTransition s sym) =
  "Non-deterministic: state " <> stateName s
  <> " has multiple transitions on '" <> T.singleton (symbolChar sym) <> "'"

fmtTrans :: Transition -> Text
fmtTrans (Transition from lbl to') =
  stateName from <> "," <> fmtLabel lbl <> " -> " <> stateName to'
  where
    fmtLabel (OnSymbol s) = T.singleton (symbolChar s)
    fmtLabel OnEpsilon    = "ε"

-- ---------------------------------------------------------------------------
-- Individual checks
-- ---------------------------------------------------------------------------

-- | Start state must be declared in the set of states.
checkStartState :: Automaton -> [ValidationIssue]
checkStartState aut
  | automStart aut `Set.member` automStates aut = []
  | otherwise = [StartStateNotInStates (automStart aut)]

-- | All accept states must be declared.
checkAcceptStates :: Automaton -> [ValidationIssue]
checkAcceptStates aut =
  [ AcceptStateNotInStates s
  | s <- Set.toList (automAccept aut)
  , not (s `Set.member` automStates aut)
  ]

-- | Source and target states of every transition must be declared.
checkTransitionStates :: Automaton -> [ValidationIssue]
checkTransitionStates aut = concatMap check (Set.toList (automTransitions aut))
  where
    states = automStates aut
    check t = concat
      [ [ TransitionFromUndefinedState t | not (transFrom t `Set.member` states) ]
      , [ TransitionToUndefinedState t   | not (transTo   t `Set.member` states) ]
      ]

-- | Every symbol used in a transition must be in the alphabet.
checkTransitionSymbols :: Automaton -> [ValidationIssue]
checkTransitionSymbols aut =
  [ UndefinedSymbolInTransition s t
  | t <- Set.toList (automTransitions aut)
  , OnSymbol s <- [transLabel t]
  , not (s `Set.member` automAlphabet aut)
  ]

-- | Find states that are not reachable from the start state.
checkUnreachableStates :: Automaton -> [ValidationIssue]
checkUnreachableStates aut =
  [ UnreachableState s
  | s <- Set.toList (automStates aut)
  , s /= automStart aut
  , not (s `Set.member` reachable)
  ]
  where
    reachable = computeReachable aut

-- | For DFAs, each (state, symbol) pair must have at most one transition.
checkDeterminism :: Automaton -> [ValidationIssue]
checkDeterminism aut
  | automType aut /= DFA = []
  | otherwise =
    [ NonDeterministicTransition s sym
    | s   <- Set.toList (automStates aut)
    , sym <- Set.toList (automAlphabet aut)
    , let targets =
            [ transTo t
            | t <- Set.toList (automTransitions aut)
            , transFrom t == s
            , transLabel t == OnSymbol sym
            ]
    , length targets > 1
    ]

-- ---------------------------------------------------------------------------
-- Reachability helper
-- ---------------------------------------------------------------------------

-- | Compute the set of states reachable from the start state
-- via any transition (BFS).
computeReachable :: Automaton -> Set State
computeReachable aut = go initVisited initVisited
  where
    initVisited = Set.singleton (automStart aut)
    go visited frontier
      | Set.null newStates = visited
      | otherwise          = go visited' newStates
      where
        reachable = Set.fromList
          [ transTo t
          | t <- Set.toList (automTransitions aut)
          , transFrom t `Set.member` frontier
          ]
        newStates = Set.difference reachable visited
        visited'  = Set.union visited newStates
