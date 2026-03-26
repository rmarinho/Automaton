{-# LANGUAGE OverloadedStrings #-}

module SimulatorSpec (spec) where

import Test.Hspec
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)

import Automaton.Types
import Automaton.Simulator
import Automaton.Parser (parseAutomaton)

-- Helper: build automaton from DSL or fail
mkAut :: Text -> Automaton
mkAut txt = case parseAutomaton txt of
  Right a -> a
  Left e  -> error $ "Test setup parse error: " ++ e

-- The DFA that accepts strings ending in "ab"
endingAbDfa :: Automaton
endingAbDfa = mkAut $ unlines'
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

-- Simple NFA: accepts strings containing "ab"
containsAbNfa :: Automaton
containsAbNfa = mkAut $ unlines'
  [ "automaton NFA"
  , "alphabet: a,b"
  , "states: q0,q1,q2"
  , "start: q0"
  , "accept: q2"
  , "transitions:"
  , "  q0,a -> q0"
  , "  q0,b -> q0"
  , "  q0,a -> q1"
  , "  q1,b -> q2"
  , "  q2,a -> q2"
  , "  q2,b -> q2"
  ]

-- ε-NFA
simpleEnfa :: Automaton
simpleEnfa = mkAut $ unlines'
  [ "automaton ENFA"
  , "alphabet: a,b"
  , "states: q0,q1,q2"
  , "start: q0"
  , "accept: q2"
  , "transitions:"
  , "  q0,eps -> q1"
  , "  q1,a -> q2"
  , "  q2,b -> q2"
  ]

unlines' :: [Text] -> Text
unlines' = mconcat . map (<> "\n")

spec :: Spec
spec = do
  describe "DFA simulation" $ do

    it "accepts 'ab'" $
      accepts endingAbDfa "ab" `shouldBe` True

    it "accepts 'aab'" $
      accepts endingAbDfa "aab" `shouldBe` True

    it "accepts 'bab'" $
      accepts endingAbDfa "bab" `shouldBe` True

    it "rejects empty string" $
      accepts endingAbDfa "" `shouldBe` False

    it "rejects 'ba'" $
      accepts endingAbDfa "ba" `shouldBe` False

    it "rejects 'abb'" $
      accepts endingAbDfa "abb" `shouldBe` False

    it "generates correct number of steps" $ do
      let result = simulate endingAbDfa "ab"
      length (simSteps result) `shouldBe` 3  -- step 0, 1, 2

    it "step 0 has start state" $ do
      let result = simulate endingAbDfa "ab"
          s0 = case simSteps result of
                 (x:_) -> x
                 []    -> error "no steps"
      stepNumber s0 `shouldBe` 0
      stepSymbol s0 `shouldBe` Nothing
      stepActiveStates s0 `shouldBe` Set.singleton (State "q0")

  describe "NFA simulation" $ do

    it "accepts 'ab'" $
      accepts containsAbNfa "ab" `shouldBe` True

    it "accepts 'aab'" $
      accepts containsAbNfa "aab" `shouldBe` True

    it "accepts 'abb'" $
      accepts containsAbNfa "abb" `shouldBe` True

    it "rejects 'ba'" $
      accepts containsAbNfa "ba" `shouldBe` False

    it "rejects 'aaa'" $
      accepts containsAbNfa "aaa" `shouldBe` False

    it "shows multiple active states" $ do
      let result = simulate containsAbNfa "a"
          lastStep = last (simSteps result)
      -- After reading 'a' from q0, NFA is in {q0, q1}
      Set.size (stepActiveStates lastStep) `shouldBe` 2

  describe "ε-NFA simulation" $ do

    it "starts with epsilon closure" $ do
      let result = simulate simpleEnfa ""
          s0 = head (simSteps result)
      -- ε-closure of {q0} = {q0, q1}
      stepActiveStates s0 `shouldBe` Set.fromList [State "q0", State "q1"]

    it "accepts 'a'" $
      accepts simpleEnfa "a" `shouldBe` True

    it "accepts 'ab'" $
      accepts simpleEnfa "ab" `shouldBe` True

    it "accepts 'abbb'" $
      accepts simpleEnfa "abbb" `shouldBe` True

    it "rejects empty string" $
      accepts simpleEnfa "" `shouldBe` False

    it "rejects 'b'" $
      accepts simpleEnfa "b" `shouldBe` False

  describe "epsilonClosure" $ do

    it "includes the starting states" $ do
      let cl = epsilonClosure simpleEnfa (Set.singleton (State "q0"))
      State "q0" `shouldSatisfy` (`Set.member` cl)

    it "follows ε-transitions transitively" $ do
      let cl = epsilonClosure simpleEnfa (Set.singleton (State "q0"))
      State "q1" `shouldSatisfy` (`Set.member` cl)

  describe "runTests" $ do

    it "all tests pass for correct expectations" $ do
      let tests =
            [ TestCase "ab"  True
            , TestCase "ba"  False
            , TestCase "aab" True
            ]
          results = runTests endingAbDfa tests
      all trPassed results `shouldBe` True

    it "detects a failing test" $ do
      let tests = [TestCase "ab" False]  -- wrong expectation
          results = runTests endingAbDfa tests
      all trPassed results `shouldBe` False
