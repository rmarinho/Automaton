# Automaton Designer

A complete automaton parser, designer, simulator, and test runner — implemented in both **Haskell** and **.NET MAUI**.

Design, visualize, and test DFA, NFA, and ε-NFA automata with a graphical canvas, a custom DSL editor, step-by-step simulation, and batch test runner.

![License](https://img.shields.io/badge/license-MIT-blue)
![Haskell CI](https://github.com/rmarinho/Automaton/actions/workflows/haskell.yml/badge.svg)
![MAUI CI](https://github.com/rmarinho/Automaton/actions/workflows/maui.yml/badge.svg)

## Features

- **Visual canvas** — drag states, draw transitions, mark start/accept states
- **DSL editor** — define automata in text with live parse feedback
- **Simulator** — run strings, step through execution, inspect active states per step
- **Test runner** — batch test cases with pass/fail summary
- **Validator** — detect unreachable states, missing transitions, undefined symbols
- **NFA→DFA converter** — subset construction algorithm
- **Catppuccin Mocha** dark theme

## Projects

### `automaton-designer/` — Haskell + Web UI

A Haskell library with a Warp web server serving an HTML5 Canvas SPA.

```bash
cd automaton-designer
cabal build all
cabal test                # 45 tests
cabal run automaton-designer  # http://localhost:8023
```

**Stack:** Haskell · Megaparsec · Aeson · Warp/WAI · HSpec

### `automaton-maui/` — .NET MAUI

A native cross-platform app targeting iOS, Android, Mac Catalyst, and Windows.

```bash
cd automaton-maui
dotnet build
dotnet build -t:Run -f net10.0-maccatalyst  # macOS
dotnet build -t:Run -f net10.0-ios          # iOS Simulator
dotnet build -t:Run -f net10.0-android      # Android Emulator
```

**Stack:** C# · .NET 10 · MAUI · MVVM · MauiDevFlow

## DSL Format

```
automaton DFA
alphabet: a,b
states: q0,q1,q2
start: q0
accept: q2
transitions:
  q0,a -> q1
  q0,b -> q0
  q1,b -> q2
  q2,a -> q1
```

Supports `DFA`, `NFA`, and `ENFA` (ε-NFA with `eps` transitions). See `automaton-designer/examples/` for more samples.

## Architecture

Both projects share the same layered design — all domain logic is pure with no side effects:

```
Types       → State, Symbol, Transition, Automaton
Parser      → DSL text ↔ Automaton
Simulator   → Input string → Step trace + accept/reject
Validator   → Automaton → [Issues]
Converter   → NFA → DFA (subset construction)
UI          → Web SPA (Haskell) / Native MAUI (C#)
```

## Requirements

| Project | Requirements |
|---------|-------------|
| Haskell | GHC 9.4+, Cabal 2.4+ |
| MAUI | .NET 10+ SDK, MAUI workload |

## License

[MIT](LICENSE)
