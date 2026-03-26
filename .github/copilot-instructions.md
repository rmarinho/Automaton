# Copilot Instructions — Automaton Designer

## Repository Overview

This repo contains **two independent implementations** of the same automaton designer (DFA, NFA, ε-NFA):

| Project | Stack | UI | Entry Point |
|---------|-------|----|-------------|
| `automaton-designer/` | Haskell (Cabal) | Warp web server + HTML5 Canvas SPA | `app/Main.hs` → http://localhost:8023 |
| `automaton-maui/` | C# .NET 10 MAUI | Native cross-platform (iOS, Android, Mac Catalyst) | `MauiProgram.cs` |

Both share the same domain model, DSL format, and layered architecture — only the language and UI framework differ.

## Build & Test Commands

### Haskell (`automaton-designer/`)

```bash
cabal build all                        # Build library + exe + tests
cabal test                             # Run all 45 tests
cabal test --test-options="--match Simulator"  # Run only Simulator tests
cabal test --test-options="--match \"accepts a simple DFA string\""  # Single test
cabal run automaton-designer           # Launch web UI on :8023
```

Requires GHC 9.4+ and Cabal 2.4+. The `cabal.project` file has `allow-newer` stanzas critical for GHC 9.14 compatibility — do not remove them.

### .NET MAUI (`automaton-maui/`)

```bash
dotnet build                                        # All platforms
dotnet build -f net10.0-maccatalyst                 # Mac only
dotnet build -t:Run -f net10.0-maccatalyst          # Build + launch Mac
dotnet build -t:Run -f net10.0-ios                  # iOS simulator
dotnet build -t:Run -f net10.0-android              # Android emulator
```

Requires .NET 10+ SDK with MAUI workload (`dotnet workload install maui`).

**MauiDevFlow** is integrated for AI debugging — after launching the app, use `maui-devflow wait` then `maui-devflow MAUI status`, `screenshot`, `tree`, `tap`, etc. The `.claude/skills/maui-ai-debugging/` skill has full reference docs.

## Architecture

Both projects use the same layered structure — **all domain logic is pure with no side effects**:

```
Types (ADTs/Records)
  ↓
Parser         → parse DSL text into Automaton
Simulator      → run input strings, produce step traces
Validator      → detect structural issues (unreachable states, etc.)
Converter      → NFA→DFA via subset construction
Serializer     → JSON import/export (Haskell only)
  ↓
UI Layer       → Warp handlers (Haskell) / MVVM ViewModel (MAUI)
```

### Haskell module map

| Module | Role |
|--------|------|
| `Automaton.Types` | All ADTs: `State`, `Symbol`, `TransitionLabel`, `Transition`, `Automaton`, `SimResult` |
| `Automaton.Parser` | Megaparsec DSL parser + `formatAutomaton` pretty-printer |
| `Automaton.Simulator` | `simulate`, `epsilonClosure`, `runTests` — pure Set-based |
| `Automaton.Validator` | Returns `[ValidationIssue]` — no exceptions |
| `Automaton.Converter` | `nfaToDfa` via BFS subset construction |
| `Automaton.Serializer` | Aeson JSON + DSL file I/O |
| `UI.Server` | WAI routing (`/api/*` + static files) |
| `UI.Handlers` | HTTP handlers holding `IORef AppState` |

### C# module map

| Namespace | Role |
|-----------|------|
| `Models/AutomatonTypes.cs` | C# records mirroring Haskell ADTs |
| `Core/AutomatonParser.cs` | Recursive-descent parser (no Megaparsec in C#) |
| `Core/Simulator.cs` | Static methods, same algorithm as Haskell |
| `Core/Validator.cs` | Static validation, returns `List<ValidationIssue>` |
| `Core/Converter.cs` | Subset construction, same algorithm |
| `Services/AppViewModel.cs` | MVVM ViewModel with `INotifyPropertyChanged` |
| `UI/Controls/AutomatonCanvasDrawable.cs` | MAUI `IDrawable` canvas renderer |

## Key Conventions

### Error handling

- **Haskell**: Parser returns `Either String Automaton`. Validator returns `[ValidationIssue]`. No exceptions in domain logic.
- **C#**: Parser returns `(Automaton? Result, string? Error)` tuple. Validator returns `List<ValidationIssue>`. Domain logic is exception-free.

### Extending automaton types

1. Add constructor to `AutomatonType` enum (`Types.hs` / `AutomatonTypes.cs`)
2. Update parser to recognize the new keyword
3. Extend `Simulator` with type-specific logic (e.g., stack for PDA)
4. Add validation rules in `Validator`
5. Add test cases in `test/` (Haskell) — match the existing HSpec style

### Megaparsec quirks (GHC 9.14)

The parser has specific import hiding to avoid name collisions:
```haskell
import Text.Megaparsec hiding (State, ParseError)
import Text.Megaparsec.Char hiding (symbolChar)
```
`$` and `<?>` cannot mix in the same infix expression on GHC 9.14 — use `where` clauses instead.

### MAUI canvas

`AutomatonCanvasDrawable` implements `IDrawable` and uses only basic SVG-compatible shapes (circles, lines, paths). State positions are stored in `AppViewModel.Layout` as `Dictionary<State, Position>` and support drag interaction via `StartInteraction`/`DragInteraction`/`EndInteraction`.

## DSL Format

```
automaton DFA            -- Type: DFA | NFA | ENFA (or ε-NFA, e-NFA)
alphabet: a,b            -- Single-char symbols, comma-separated
states: q0,q1,q2
start: q0
accept: q2               -- Can list multiple or leave empty
transitions:
  q0,a -> q1             -- state,symbol -> target
  q0,eps -> q1           -- Epsilon: eps | ε | epsilon (ENFA only)
```

Example `.atm` files are in `automaton-designer/examples/`.

## Haskell Web API

The Haskell app exposes JSON endpoints used by the SPA frontend (`static/index.html`):

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/state` | Current automaton + layout + tests |
| `POST` | `/api/parse` | Parse DSL text |
| `POST` | `/api/simulate` | Run input string |
| `POST` | `/api/validate` | Structural validation |
| `POST` | `/api/convert` | NFA→DFA conversion |
| `POST` | `/api/test` | Run all test cases |
| `POST` | `/api/save` | Save project to JSON file |

The frontend sends `Content-Type: application/json` and renders results on an HTML5 Canvas. Aeson serializes `Set` as sorted arrays and sum types as `{"tag":"OnSymbol","contents":{...}}`.
