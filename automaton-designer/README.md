# Automaton Designer

A desktop-grade Haskell application for **designing, parsing, simulating, and
testing finite automata** (DFA, NFA, ε-NFA) through a graphical web UI.

![Architecture: Haskell backend + HTML5/Canvas frontend](https://img.shields.io/badge/Haskell-backend%20%2B%20HTML5%20frontend-blueviolet)

---

## Features

| Feature | Description |
|---------|-------------|
| **Automaton types** | DFA, NFA, ε-NFA (extensible for PDA) |
| **DSL editor** | Write automata in a concise textual DSL with live parsing |
| **Canvas** | Visual rendering with draggable states, arrows, self-loops |
| **Simulator** | Run/step-through input strings; highlights active states |
| **Test runner** | Batch test cases with expected results; pass/fail summary |
| **Validator** | Detects unreachable states, undefined symbols, non-determinism in DFA |
| **NFA → DFA** | Subset-construction conversion preserving the language |
| **JSON import/export** | Save/load full projects as JSON |
| **Dark theme** | Catppuccin Mocha colour scheme |

---

## Quick Start

### Prerequisites

- **GHC** ≥ 9.4 (tested with 9.14.1)
- **Cabal** ≥ 3.8
- A modern web browser

### Build & Run

```bash
cd automaton-designer

# Build everything (library + executable + tests)
cabal build all

# Run the test suite (45 tests)
cabal test

# Launch the application
cabal run automaton-designer
```

Then open **http://localhost:8023** in your browser.

### Using Stack (alternative)

```bash
stack build
stack test
stack run automaton-designer
```

---

## Project Structure

```
automaton-designer/
├── automaton-designer.cabal     # Build configuration
├── cabal.project                # Cabal project settings
├── stack.yaml                   # Stack resolver
│
├── src/Automaton/               # ── Library (pure domain logic) ──
│   ├── Types.hs                 #   Algebraic data types
│   ├── Parser.hs                #   Megaparsec DSL parser + formatter
│   ├── Simulator.hs             #   Pure simulation engine
│   ├── Validator.hs             #   Structural validation
│   ├── Serializer.hs            #   JSON & DSL file I/O
│   └── Converter.hs             #   NFA/ε-NFA → DFA conversion
│
├── app/                         # ── Executable (web UI) ──
│   ├── Main.hs                  #   Entry point (starts Warp server)
│   └── UI/
│       ├── Server.hs            #   WAI routing (API + static files)
│       └── Handlers.hs          #   JSON API request handlers
│
├── static/                      # ── Frontend assets ──
│   ├── index.html               #   Single-page application
│   ├── style.css                #   Dark-theme CSS (Catppuccin Mocha)
│   └── canvas.js                #   HTML5 Canvas automaton renderer
│
├── test/                        # ── Test suite (HSpec) ──
│   ├── Spec.hs                  #   Test runner entry
│   ├── ParserSpec.hs            #   DSL parser tests
│   ├── SimulatorSpec.hs         #   Simulation engine tests
│   ├── ValidatorSpec.hs         #   Validation tests
│   └── ConverterSpec.hs         #   NFA→DFA conversion tests
│
└── examples/                    # ── Sample automata ──
    ├── simple-dfa.atm           #   DFA: accepts strings ending in "ab"
    ├── nfa-example.atm          #   NFA: accepts strings containing "ab"
    └── enfa-example.atm         #   ε-NFA: accepts a(b*)
```

---

## Architecture

The codebase follows a strict **layered architecture**:

```
┌─────────────────────────────────────────┐
│  Frontend (HTML/CSS/JS)                 │  ← browser
├─────────────────────────────────────────┤
│  UI.Server / UI.Handlers  (Warp + WAI) │  ← HTTP JSON API
├─────────────────────────────────────────┤
│  Automaton.Parser                       │  ← Megaparsec DSL
│  Automaton.Simulator                    │  ← pure simulation
│  Automaton.Validator                    │  ← structural checks
│  Automaton.Converter                    │  ← NFA → DFA
│  Automaton.Serializer                   │  ← JSON / file I/O
├─────────────────────────────────────────┤
│  Automaton.Types                        │  ← algebraic data types
└─────────────────────────────────────────┘
```

- **Domain logic is pure** — the simulator, validator, and converter have no
  side effects and are fully tested.
- **UI is isolated** — the frontend communicates exclusively via JSON API calls.
- **Strong types** — `State`, `Symbol`, `TransitionLabel`, `Transition`,
  `Automaton`, `SimResult`, etc. are all algebraic data types.

---

## DSL Reference

```
-- Comments start with --
automaton DFA           -- or NFA, ENFA, ε-NFA, e-NFA
alphabet: a,b           -- comma-separated symbols (single chars)
states: q0,q1,q2        -- comma-separated state names
start: q0               -- initial state
accept: q2              -- accepting states (may be empty)
transitions:
  q0,a -> q1            -- state,symbol -> target
  q1,b -> q2
  q2,a -> q2
```

For ε-NFA, use `eps`, `ε`, or `epsilon` for epsilon transitions:

```
automaton ENFA
alphabet: a,b
states: q0,q1,q2
start: q0
accept: q2
transitions:
  q0,eps -> q1
  q1,a -> q2
  q2,b -> q2
```

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/state` | Current automaton, layout, tests, DSL text |
| POST | `/api/parse` | Parse DSL text → update automaton |
| POST | `/api/simulate` | Simulate input string → step trace |
| POST | `/api/test` | Run batch test cases → results |
| POST | `/api/validate` | Validate automaton → issue list |
| POST | `/api/convert` | Convert NFA/ε-NFA → DFA |
| POST | `/api/save` | Save project to `automaton-project.json` |

---

## Test Suite

```
Automaton.Parser
  parseAutomaton
    parses a simple DFA                      ✔
    parses an NFA                            ✔
    parses an ε-NFA with eps keyword         ✔
    parses ε-NFA with ε symbol               ✔
    handles comments                         ✔
    handles empty accept set                 ✔
    rejects malformed input                  ✔
  formatAutomaton
    round-trips a DFA (parse ∘ format = id)  ✔

Automaton.Simulator
  DFA simulation           (6 tests)         ✔
  NFA simulation           (6 tests)         ✔
  ε-NFA simulation         (5 tests)         ✔
  epsilonClosure           (2 tests)         ✔
  runTests                 (2 tests)         ✔

Automaton.Validator
  validate                 (7 tests)         ✔
  formatIssue              (1 test)          ✔

Automaton.Converter
  nfaToDfa                 (4 tests)         ✔

45 examples, 0 failures
```

---

## Extending

The codebase is designed to be extended:

- **New automaton types** — add a constructor to `AutomatonType` in `Types.hs`
  and extend the parser, simulator, and validator.
- **PDA support** — add a `Stack` type and extend `Transition` with stack
  operations.
- **DFA minimisation** — implement Hopcroft's algorithm in `Converter.hs`
  (stub is already in place).
- **Regex → NFA** — add a regex parser and Thompson construction.
- **Export as image** — render the canvas to PNG via the browser's `toDataURL`.

---

## License

MIT
