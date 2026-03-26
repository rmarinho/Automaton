{-# LANGUAGE OverloadedStrings #-}

module ValidatorSpec (spec) where

import Test.Hspec
import qualified Data.Set as Set
import Data.Text (Text)

import Automaton.Types
import Automaton.Validator
import Automaton.Parser (parseAutomaton)

spec :: Spec
spec = do
  describe "validate" $ do

    it "returns no issues for a well-formed DFA" $ do
      let Right aut = parseAutomaton $ unlines'
            [ "automaton DFA"
            , "alphabet: a,b"
            , "states: q0,q1"
            , "start: q0"
            , "accept: q1"
            , "transitions:"
            , "  q0,a -> q1"
            , "  q0,b -> q0"
            , "  q1,a -> q1"
            , "  q1,b -> q0"
            ]
      validate aut `shouldBe` []

    it "detects start state not in states" $ do
      let aut = Automaton
            { automType        = DFA
            , automStates      = Set.fromList [State "q1"]
            , automAlphabet    = Set.fromList [Symbol 'a']
            , automStart       = State "q0"
            , automAccept      = Set.empty
            , automTransitions = Set.empty
            }
      validate aut `shouldSatisfy` any isStartNotInStates

    it "detects accept state not in states" $ do
      let aut = Automaton
            { automType        = DFA
            , automStates      = Set.fromList [State "q0"]
            , automAlphabet    = Set.fromList [Symbol 'a']
            , automStart       = State "q0"
            , automAccept      = Set.fromList [State "q99"]
            , automTransitions = Set.empty
            }
      validate aut `shouldSatisfy` any isAcceptNotInStates

    it "detects undefined symbol in transition" $ do
      let aut = Automaton
            { automType        = DFA
            , automStates      = Set.fromList [State "q0", State "q1"]
            , automAlphabet    = Set.fromList [Symbol 'a']
            , automStart       = State "q0"
            , automAccept      = Set.empty
            , automTransitions = Set.fromList
                [ Transition (State "q0") (OnSymbol (Symbol 'z')) (State "q1") ]
            }
      validate aut `shouldSatisfy` any isUndefinedSymbol

    it "detects transition from undefined state" $ do
      let aut = Automaton
            { automType        = DFA
            , automStates      = Set.fromList [State "q0"]
            , automAlphabet    = Set.fromList [Symbol 'a']
            , automStart       = State "q0"
            , automAccept      = Set.empty
            , automTransitions = Set.fromList
                [ Transition (State "ghost") (OnSymbol (Symbol 'a')) (State "q0") ]
            }
      validate aut `shouldSatisfy` any isTransFromUndefined

    it "detects unreachable states" $ do
      let aut = Automaton
            { automType        = DFA
            , automStates      = Set.fromList [State "q0", State "q1", State "island"]
            , automAlphabet    = Set.fromList [Symbol 'a']
            , automStart       = State "q0"
            , automAccept      = Set.empty
            , automTransitions = Set.fromList
                [ Transition (State "q0") (OnSymbol (Symbol 'a')) (State "q1") ]
            }
      validate aut `shouldSatisfy` any isUnreachable

    it "detects non-determinism in DFA" $ do
      let aut = Automaton
            { automType        = DFA
            , automStates      = Set.fromList [State "q0", State "q1", State "q2"]
            , automAlphabet    = Set.fromList [Symbol 'a']
            , automStart       = State "q0"
            , automAccept      = Set.empty
            , automTransitions = Set.fromList
                [ Transition (State "q0") (OnSymbol (Symbol 'a')) (State "q1")
                , Transition (State "q0") (OnSymbol (Symbol 'a')) (State "q2")
                ]
            }
      validate aut `shouldSatisfy` any isNonDeterministic

    it "allows non-determinism in NFA" $ do
      let aut = Automaton
            { automType        = NFA
            , automStates      = Set.fromList [State "q0", State "q1", State "q2"]
            , automAlphabet    = Set.fromList [Symbol 'a']
            , automStart       = State "q0"
            , automAccept      = Set.empty
            , automTransitions = Set.fromList
                [ Transition (State "q0") (OnSymbol (Symbol 'a')) (State "q1")
                , Transition (State "q0") (OnSymbol (Symbol 'a')) (State "q2")
                ]
            }
      validate aut `shouldSatisfy` (not . any isNonDeterministic)

  describe "formatIssue" $ do
    it "produces readable messages" $ do
      let msg = formatIssue (UnreachableState (State "q5"))
      msg `shouldBe` "Unreachable state: q5"

-- ---------------------------------------------------------------------------
-- Issue predicates
-- ---------------------------------------------------------------------------

isStartNotInStates :: ValidationIssue -> Bool
isStartNotInStates (StartStateNotInStates _) = True
isStartNotInStates _ = False

isAcceptNotInStates :: ValidationIssue -> Bool
isAcceptNotInStates (AcceptStateNotInStates _) = True
isAcceptNotInStates _ = False

isUndefinedSymbol :: ValidationIssue -> Bool
isUndefinedSymbol (UndefinedSymbolInTransition _ _) = True
isUndefinedSymbol _ = False

isTransFromUndefined :: ValidationIssue -> Bool
isTransFromUndefined (TransitionFromUndefinedState _) = True
isTransFromUndefined _ = False

isUnreachable :: ValidationIssue -> Bool
isUnreachable (UnreachableState _) = True
isUnreachable _ = False

isNonDeterministic :: ValidationIssue -> Bool
isNonDeterministic (NonDeterministicTransition _ _) = True
isNonDeterministic _ = False

-- ---------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------

unlines' :: [Text] -> Text
unlines' = mconcat . map (<> "\n")
