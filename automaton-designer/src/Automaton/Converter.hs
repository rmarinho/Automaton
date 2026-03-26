{-# LANGUAGE OverloadedStrings #-}

-- | Automaton conversion utilities.
--
-- * NFA / ε-NFA → DFA via subset construction
-- * DFA minimisation (stub for future implementation)
module Automaton.Converter
  ( nfaToDfa
  , minimizeDfa
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set        (Set)
import qualified Data.Set        as Set
import qualified Data.Text       as T

import Automaton.Types
import Automaton.Simulator (epsilonClosure, step)

-- ---------------------------------------------------------------------------
-- NFA / ε-NFA → DFA (subset construction)
-- ---------------------------------------------------------------------------

-- | Convert an NFA or ε-NFA to an equivalent DFA using subset construction.
--
-- If the automaton is already a DFA it is returned unchanged.
nfaToDfa :: Automaton -> Automaton
nfaToDfa aut
  | automType aut == DFA = aut
  | otherwise            = buildDfa aut

-- Internal BFS state threaded through the subset construction.
data BuildState = BuildState
  { bsVisited     :: !(Map (Set State) State)  -- state-set → DFA name
  , bsQueue       :: ![Set State]              -- work-list
  , bsTransitions :: ![Transition]             -- accumulated DFA transitions
  , bsNextId      :: !Int                      -- counter for naming new states
  }

buildDfa :: Automaton -> Automaton
buildDfa nfa =
  let alpha = Set.toList (automAlphabet nfa)

      -- Initial DFA state (with ε-closure for ε-NFA)
      initSet = case automType nfa of
        ENFA -> epsilonClosure nfa (Set.singleton (automStart nfa))
        _    -> Set.singleton (automStart nfa)

      initBuild = BuildState
        { bsVisited     = Map.singleton initSet (nameOf 0)
        , bsQueue       = [initSet]
        , bsTransitions = []
        , bsNextId      = 1
        }

      final = explore alpha nfa initBuild

      dfaStates = Set.fromList (Map.elems (bsVisited final))
      dfaStart  = bsVisited final Map.! initSet
      dfaAccept = Set.fromList
        [ bsVisited final Map.! ss
        | ss <- Map.keys (bsVisited final)
        , not (Set.null (Set.intersection ss (automAccept nfa)))
        ]
  in Automaton
    { automType        = DFA
    , automStates      = dfaStates
    , automAlphabet    = automAlphabet nfa
    , automStart       = dfaStart
    , automAccept      = dfaAccept
    , automTransitions = Set.fromList (bsTransitions final)
    }

-- | Assign a DFA state name from an integer counter: d0, d1, d2, …
nameOf :: Int -> State
nameOf n = State ("d" <> T.pack (show n))

-- | BFS loop: process each state-set on the queue.
explore :: [Symbol] -> Automaton -> BuildState -> BuildState
explore _     _   bs@(BuildState _ [] _ _) = bs
explore alpha nfa bs@(BuildState visited (current:rest) trans nid) =
  let fromName = visited Map.! current

      -- Process every alphabet symbol for the current state-set
      (visited', rest', nid', newTrans) =
        foldl (processSymbol nfa current fromName) (visited, rest, nid, []) alpha

  in explore alpha nfa bs
    { bsVisited     = visited'
    , bsQueue       = rest'
    , bsTransitions = trans ++ newTrans
    , bsNextId      = nid'
    }

-- | For one state-set and one symbol, compute the target state-set,
-- register it if new, and emit the DFA transition.
processSymbol
  :: Automaton
  -> Set State            -- current NFA state-set
  -> State                -- current DFA state name
  -> (Map (Set State) State, [Set State], Int, [Transition])
  -> Symbol
  -> (Map (Set State) State, [Set State], Int, [Transition])
processSymbol nfa current fromName (vis, queue, nid, ts) sym =
  let targetSet = step nfa current sym
  in if Set.null targetSet
     then (vis, queue, nid, ts)                  -- dead end, skip
     else case Map.lookup targetSet vis of
       Just toName ->
         -- Already known state-set
         ( vis
         , queue
         , nid
         , ts ++ [Transition fromName (OnSymbol sym) toName]
         )
       Nothing ->
         -- New state-set discovered
         let toName = nameOf nid
             vis'   = Map.insert targetSet toName vis
             queue' = queue ++ [targetSet]
         in ( vis'
            , queue'
            , nid + 1
            , ts ++ [Transition fromName (OnSymbol sym) toName]
            )

-- ---------------------------------------------------------------------------
-- DFA minimisation (placeholder)
-- ---------------------------------------------------------------------------

-- | Minimise a DFA using Hopcroft's algorithm.
--
-- /Currently a stub that returns the input unchanged./
-- TODO: implement partition-refinement.
minimizeDfa :: Automaton -> Automaton
minimizeDfa = id
