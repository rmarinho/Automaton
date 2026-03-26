module Main (main) where

import Test.Hspec

import qualified ParserSpec
import qualified SimulatorSpec
import qualified ValidatorSpec
import qualified ConverterSpec

main :: IO ()
main = hspec $ do
  describe "Automaton.Parser"    ParserSpec.spec
  describe "Automaton.Simulator" SimulatorSpec.spec
  describe "Automaton.Validator" ValidatorSpec.spec
  describe "Automaton.Converter" ConverterSpec.spec
