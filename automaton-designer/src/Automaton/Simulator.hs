{-# LANGUAGE OverloadedStrings #-}

-- | Pure simulation engine for automata.
--
-- Supports DFA (single active state), NFA (set of active states),
-- and ε-NFA (epsilon closure computed at each step).
module Automaton.Simulator
  ( simulate
  , simulateStep
  , epsilonClosure
  , step
  , accepts
  , runTests
  ) where

import Data.Set  (Set)
import qualified Data.Set  as Set
import Data.Text (Text)
import qualified Data.Text as T

import Automaton.Types

-- ---------------------------------------------------------------------------
-- Epsilon closure
-- ---------------------------------------------------------------------------

-- | Compute the epsilon closure of a set of states.
--
-- Returns all states reachable from the given set via zero or more
-- ε-transitions (fixed-point iteration).
epsilonClosure :: Automaton -> Set State -> Set State
epsilonClosure aut initial = go initial initial
  where
    go visited frontier
      | Set.null newReachable = visited
      | otherwise = go visited' newReachable
      where
        -- States reachable via one ε-step from the frontier
        reachable = Set.fromList
          [ transTo t
          | t <- Set.toList (automTransitions aut)
          , transFrom t `Set.member` frontier
          , transLabel t == OnEpsilon
          ]
        newReachable = Set.difference reachable visited
        visited'     = Set.union visited newReachable

-- ---------------------------------------------------------------------------
-- Single-step transition
-- ---------------------------------------------------------------------------

-- | Advance one step: given the current set of active states and a symbol,
-- compute the next set of active states.
--
-- For ε-NFA, epsilon closure is applied after following symbol-transitions.
step :: Automaton -> Set State -> Symbol -> Set State
step aut current sym =
  let directTargets = Set.fromList
        [ transTo t
        | t <- Set.toList (automTransitions aut)
        , transFrom t `Set.member` current
        , transLabel t == OnSymbol sym
        ]
  in case automType aut of
       ENFA -> epsilonClosure aut directTargets
       _    -> directTargets

-- ---------------------------------------------------------------------------
-- Full simulation
-- ---------------------------------------------------------------------------

-- | Compute initial active states (applying ε-closure for ε-NFA).
initialStates :: Automaton -> Set State
initialStates aut = case automType aut of
  ENFA -> epsilonClosure aut (Set.singleton (automStart aut))
  _    -> Set.singleton (automStart aut)

-- | Run a complete simulation and return a step-by-step trace.
simulate :: Automaton -> Text -> SimResult
simulate aut input =
  let symbols = map Symbol (T.unpack input)
      initActive = initialStates aut

      -- Step 0: before reading any input
      step0 = SimStep
        { stepNumber       = 0
        , stepSymbol       = Nothing
        , stepActiveStates = initActive
        , stepRemaining    = input
        }

      -- Build all subsequent steps with scanl
      allSteps = scanl advance step0 (zip [1..] symbols)

      finalActive = stepActiveStates (safeLast step0 allSteps)
      accepted    = not $ Set.null $ Set.intersection finalActive (automAccept aut)
  in SimResult
    { simAccepted = accepted
    , simSteps    = allSteps
    , simInput    = input
    }
  where
    advance prev (i, sym) =
      let nextStates = step aut (stepActiveStates prev) sym
      in SimStep
        { stepNumber       = i
        , stepSymbol       = Just sym
        , stepActiveStates = nextStates
        , stepRemaining    = T.drop i input
        }

    safeLast def [] = def
    safeLast _   xs = last xs

-- | Perform a single simulation step from a given set of active states.
-- Useful for step-by-step interactive simulation.
simulateStep :: Automaton -> Set State -> Symbol -> (Set State, Bool)
simulateStep aut current sym =
  let next     = step aut current sym
      accepted = not $ Set.null $ Set.intersection next (automAccept aut)
  in (next, accepted)

-- | Quick check: does the automaton accept the given string?
accepts :: Automaton -> Text -> Bool
accepts aut = simAccepted . simulate aut

-- ---------------------------------------------------------------------------
-- Batch test runner
-- ---------------------------------------------------------------------------

-- | Run a list of test cases against an automaton.
runTests :: Automaton -> [TestCase] -> [TestResult]
runTests aut = map runOne
  where
    runOne tc =
      let actual = accepts aut (testInput tc)
      in TestResult
        { trTestCase = tc
        , trPassed   = actual == testExpected tc
        , trActual   = actual
        }
