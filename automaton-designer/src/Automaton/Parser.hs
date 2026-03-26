{-# LANGUAGE OverloadedStrings #-}

-- | Parser and pretty-printer for the automaton DSL.
--
-- DSL grammar (example):
--
-- @
-- automaton DFA
-- alphabet: a,b
-- states: q0,q1,q2
-- start: q0
-- accept: q2
-- transitions:
--   q0,a -> q1
--   q1,b -> q2
--   q2,a -> q2
-- @
--
-- For ε-NFA, use @eps@ or @ε@ for epsilon transitions.
module Automaton.Parser
  ( parseAutomaton
  , formatAutomaton
  , ParseError
  ) where

import Control.Monad        (void)
import Data.Set             (Set)
import qualified Data.Set   as Set
import Data.Text            (Text)
import qualified Data.Text  as T
import Data.Void            (Void)
import Text.Megaparsec hiding (State, ParseError)
import Text.Megaparsec.Char hiding (symbolChar)
import qualified Text.Megaparsec.Char.Lexer as L

import Automaton.Types

type Parser = Parsec Void Text

-- | Human-readable parse error.
type ParseError = String

-- ---------------------------------------------------------------------------
-- Lexer helpers
-- ---------------------------------------------------------------------------

-- | Line comment starting with @--@.
lineComment :: Parser ()
lineComment = L.skipLineComment "--"

-- | Consume whitespace *including* newlines and comments.
scn :: Parser ()
scn = L.space space1 lineComment empty

-- | Consume horizontal whitespace only (no newlines).
sc :: Parser ()
sc = L.space hspace1 lineComment empty

-- | Wrap a parser so trailing horizontal whitespace is consumed.
lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

-- | Match a fixed keyword followed by horizontal whitespace.
keyword :: Text -> Parser ()
keyword w = void $ lexeme (string w)

-- ---------------------------------------------------------------------------
-- Atomic parsers
-- ---------------------------------------------------------------------------

-- | Parse the automaton-type keyword.
pAutomatonType :: Parser AutomatonType
pAutomatonType = lexeme $ choice
  [ ENFA <$ try (string "ENFA")
  , ENFA <$ try (string "ε-NFA")
  , ENFA <$ try (string "e-NFA")
  , DFA  <$ try (string "DFA")
  , NFA  <$ string "NFA"
  ]

-- | Parse a state name: starts with a letter or underscore, followed by
-- alphanumerics or underscores.
pStateName :: Parser State
pStateName = lexeme $ do
  first <- letterChar <|> char '_'
  rest  <- many (alphaNumChar <|> char '_')
  return $ State (T.pack (first : rest))

-- | Parse a single alphabet symbol (one alphanumeric character).
pSymbolChar :: Parser Symbol
pSymbolChar = Symbol <$> (alphaNumChar <?> "alphabet symbol")

-- | Parse a transition label: a symbol character, or @eps@ / @ε@ for epsilon.
pTransLabel :: Parser TransitionLabel
pTransLabel = lexeme pLabel
  where
    pLabel = choice
      [ OnEpsilon <$ try (string "epsilon")
      , OnEpsilon <$ try (string "eps")
      , OnEpsilon <$ try (string "ε")
      , OnSymbol  <$> pSymbolChar
      ]

-- ---------------------------------------------------------------------------
-- List parsers
-- ---------------------------------------------------------------------------

-- | Comma-separated list of symbols.
pSymbolList :: Parser (Set Symbol)
pSymbolList = do
  syms <- lexeme pSymbolChar `sepBy1` lexeme (char ',')
  return (Set.fromList syms)

-- | Comma-separated list of state names.
pStateList :: Parser (Set State)
pStateList = do
  sts <- pStateName `sepBy1` lexeme (char ',')
  return (Set.fromList sts)

-- | Comma-separated list that may be empty (used for accept states).
pStateListMaybe :: Parser (Set State)
pStateListMaybe = do
  sts <- pStateName `sepBy` lexeme (char ',')
  return (Set.fromList sts)

-- ---------------------------------------------------------------------------
-- Transition parser
-- ---------------------------------------------------------------------------

-- | Parse a single transition line: @q0,a -> q1@.
pTransition :: Parser Transition
pTransition = do
  from <- pStateName
  _    <- lexeme (char ',')
  lbl  <- pTransLabel
  _    <- lexeme (string "->")
  to   <- pStateName
  return (Transition from lbl to)

-- ---------------------------------------------------------------------------
-- Top-level automaton parser
-- ---------------------------------------------------------------------------

-- | Parse a complete automaton definition from the DSL.
pAutomaton :: Parser Automaton
pAutomaton = do
  scn
  keyword "automaton"
  atype <- pAutomatonType
  scn
  keyword "alphabet:"
  alpha <- pSymbolList
  scn
  keyword "states:"
  states <- pStateList
  scn
  keyword "start:"
  start <- pStateName
  scn
  keyword "accept:"
  accept <- pStateListMaybe
  scn
  keyword "transitions:"
  scn
  trans <- many (pTransition <* scn)
  eof
  return Automaton
    { automType        = atype
    , automStates      = states
    , automAlphabet    = alpha
    , automStart       = start
    , automAccept      = accept
    , automTransitions = Set.fromList trans
    }

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | Parse an automaton definition from DSL text.
-- Returns either a human-readable error or the parsed 'Automaton'.
parseAutomaton :: Text -> Either ParseError Automaton
parseAutomaton input =
  case parse pAutomaton "automaton" input of
    Left err  -> Left (errorBundlePretty err)
    Right aut -> Right aut

-- ---------------------------------------------------------------------------
-- Pretty-printer (DSL formatter)
-- ---------------------------------------------------------------------------

-- | Format an 'Automaton' back into DSL text.
formatAutomaton :: Automaton -> Text
formatAutomaton aut = T.unlines $
  [ "automaton " <> fmtType (automType aut)
  , "alphabet: " <> fmtSymbols (automAlphabet aut)
  , "states: "   <> fmtStates (automStates aut)
  , "start: "    <> stateName (automStart aut)
  , "accept: "   <> fmtStates (automAccept aut)
  , "transitions:"
  ] ++ map fmtTrans (Set.toList (automTransitions aut))
  where
    fmtType DFA  = "DFA"
    fmtType NFA  = "NFA"
    fmtType ENFA = "ENFA"

    fmtSymbols = T.intercalate "," . map (T.singleton . symbolChar) . Set.toList
    fmtStates  = T.intercalate "," . map stateName . Set.toList

    fmtTrans (Transition from lbl to') =
      "  " <> stateName from <> "," <> fmtLabel lbl <> " -> " <> stateName to'

    fmtLabel (OnSymbol s) = T.singleton (symbolChar s)
    fmtLabel OnEpsilon    = "eps"
