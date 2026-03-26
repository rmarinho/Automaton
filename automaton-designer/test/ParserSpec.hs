{-# LANGUAGE OverloadedStrings #-}

module ParserSpec (spec) where

import Test.Hspec
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Automaton.Types
import Automaton.Parser

-- Helper: parse and assert success
shouldParseTo :: Text -> Automaton -> Expectation
shouldParseTo input expected =
  case parseAutomaton input of
    Left err  -> expectationFailure $ "Parse failed: " ++ err
    Right aut -> aut `shouldBe` expected

-- Helper: assert parse failure
shouldFailToParse :: Text -> Expectation
shouldFailToParse input =
  case parseAutomaton input of
    Left _    -> return ()
    Right aut -> expectationFailure $ "Expected parse failure, got: " ++ show aut

spec :: Spec
spec = do
  describe "parseAutomaton" $ do

    it "parses a simple DFA" $ do
      let input = T.unlines
            [ "automaton DFA"
            , "alphabet: a,b"
            , "states: q0,q1,q2"
            , "start: q0"
            , "accept: q2"
            , "transitions:"
            , "  q0,a -> q1"
            , "  q1,b -> q2"
            , "  q2,a -> q2"
            ]
          expected = Automaton
            { automType        = DFA
            , automStates      = Set.fromList [State "q0", State "q1", State "q2"]
            , automAlphabet    = Set.fromList [Symbol 'a', Symbol 'b']
            , automStart       = State "q0"
            , automAccept      = Set.singleton (State "q2")
            , automTransitions = Set.fromList
                [ Transition (State "q0") (OnSymbol (Symbol 'a')) (State "q1")
                , Transition (State "q1") (OnSymbol (Symbol 'b')) (State "q2")
                , Transition (State "q2") (OnSymbol (Symbol 'a')) (State "q2")
                ]
            }
      input `shouldParseTo` expected

    it "parses an NFA" $ do
      let input = T.unlines
            [ "automaton NFA"
            , "alphabet: a,b"
            , "states: q0,q1"
            , "start: q0"
            , "accept: q1"
            , "transitions:"
            , "  q0,a -> q0"
            , "  q0,a -> q1"
            , "  q0,b -> q0"
            ]
      case parseAutomaton input of
        Left err  -> expectationFailure err
        Right aut -> do
          automType aut `shouldBe` NFA
          Set.size (automTransitions aut) `shouldBe` 3

    it "parses an ε-NFA with eps keyword" $ do
      let input = T.unlines
            [ "automaton ENFA"
            , "alphabet: a,b"
            , "states: q0,q1,q2"
            , "start: q0"
            , "accept: q2"
            , "transitions:"
            , "  q0,eps -> q1"
            , "  q1,a -> q2"
            ]
      case parseAutomaton input of
        Left err  -> expectationFailure err
        Right aut -> do
          automType aut `shouldBe` ENFA
          let epsTrans = Set.filter (\t -> transLabel t == OnEpsilon)
                                    (automTransitions aut)
          Set.size epsTrans `shouldBe` 1

    it "parses ε-NFA with ε symbol" $ do
      let input = T.unlines
            [ "automaton ε-NFA"
            , "alphabet: a"
            , "states: q0,q1"
            , "start: q0"
            , "accept: q1"
            , "transitions:"
            , "  q0,ε -> q1"
            ]
      case parseAutomaton input of
        Left err  -> expectationFailure err
        Right aut -> automType aut `shouldBe` ENFA

    it "handles comments" $ do
      let input = T.unlines
            [ "-- A simple DFA"
            , "automaton DFA"
            , "alphabet: a"
            , "states: q0"
            , "start: q0"
            , "accept: q0"
            , "transitions:"
            , "  q0,a -> q0  -- self-loop"
            ]
      case parseAutomaton input of
        Left err  -> expectationFailure err
        Right aut -> automType aut `shouldBe` DFA

    it "handles empty accept set" $ do
      let input = T.unlines
            [ "automaton DFA"
            , "alphabet: a"
            , "states: q0"
            , "start: q0"
            , "accept:"
            , "transitions:"
            , "  q0,a -> q0"
            ]
      case parseAutomaton input of
        Left err  -> expectationFailure err
        Right aut -> automAccept aut `shouldBe` Set.empty

    it "rejects malformed input" $ do
      shouldFailToParse "this is not an automaton"
      shouldFailToParse "automaton INVALID\nalphabet: a"
      shouldFailToParse "automaton DFA\nstates: q0"

  describe "formatAutomaton" $ do

    it "round-trips a DFA (parse ∘ format = id)" $ do
      let input = T.unlines
            [ "automaton DFA"
            , "alphabet: a,b"
            , "states: q0,q1"
            , "start: q0"
            , "accept: q1"
            , "transitions:"
            , "  q0,a -> q1"
            , "  q1,b -> q0"
            ]
      case parseAutomaton input of
        Left err  -> expectationFailure err
        Right aut -> do
          let formatted = formatAutomaton aut
          case parseAutomaton formatted of
            Left err2  -> expectationFailure $ "Re-parse failed: " ++ err2
            Right aut2 -> aut2 `shouldBe` aut
