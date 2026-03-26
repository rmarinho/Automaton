{-# LANGUAGE OverloadedStrings #-}

module ConverterSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Set as Set

import Automaton.Types
import Automaton.Converter
import Automaton.Simulator (accepts)
import Automaton.Parser (parseAutomaton)

spec :: Spec
spec = do
  describe "nfaToDfa" $ do

    it "returns a DFA unchanged" $ do
      let Right dfa = parseAutomaton $ unlines'
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
      nfaToDfa dfa `shouldBe` dfa

    it "converts a simple NFA to DFA preserving language" $ do
      let Right nfa = parseAutomaton $ unlines'
            [ "automaton NFA"
            , "alphabet: a,b"
            , "states: q0,q1,q2"
            , "start: q0"
            , "accept: q2"
            , "transitions:"
            , "  q0,a -> q0"
            , "  q0,a -> q1"
            , "  q0,b -> q0"
            , "  q1,b -> q2"
            , "  q2,a -> q2"
            , "  q2,b -> q2"
            ]
      let dfa = nfaToDfa nfa
      automType dfa `shouldBe` DFA

      -- The DFA should accept/reject the same strings
      accepts dfa "ab"   `shouldBe` accepts nfa "ab"
      accepts dfa "aab"  `shouldBe` accepts nfa "aab"
      accepts dfa "ba"   `shouldBe` accepts nfa "ba"
      accepts dfa "bbb"  `shouldBe` accepts nfa "bbb"
      accepts dfa ""     `shouldBe` accepts nfa ""
      accepts dfa "abab" `shouldBe` accepts nfa "abab"

    it "converts an ε-NFA to DFA preserving language" $ do
      let Right enfa = parseAutomaton $ unlines'
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
      let dfa = nfaToDfa enfa
      automType dfa `shouldBe` DFA

      accepts dfa "a"    `shouldBe` True
      accepts dfa "ab"   `shouldBe` True
      accepts dfa "abbb" `shouldBe` True
      accepts dfa ""     `shouldBe` False
      accepts dfa "b"    `shouldBe` False
      accepts dfa "ba"   `shouldBe` False

    it "produces no epsilon transitions in the result" $ do
      let Right enfa = parseAutomaton $ unlines'
            [ "automaton ENFA"
            , "alphabet: a"
            , "states: q0,q1"
            , "start: q0"
            , "accept: q1"
            , "transitions:"
            , "  q0,eps -> q1"
            , "  q1,a -> q1"
            ]
      let dfa = nfaToDfa enfa
          hasEps = any (\t -> transLabel t == OnEpsilon)
                       (Set.toList (automTransitions dfa))
      hasEps `shouldBe` False

-- ---------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------

unlines' :: [Text] -> Text
unlines' = mconcat . map (<> "\n")
