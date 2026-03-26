# Automaton Designer — .NET MAUI

A cross-platform desktop & mobile app for designing, parsing, simulating, and testing finite automata (DFA, NFA, ε-NFA).

## Features

- **Visual Canvas** — states rendered as circles with transitions as arrows, active-state highlighting during simulation
- **DSL Editor** — define automata in a textual DSL with live parsing and error feedback
- **Simulator** — run acceptance tests, step through execution, inspect active states per step
- **Validator** — check for unreachable states, missing transitions, undefined symbols
- **Test Runner** — batch test cases with pass/fail summary
- **NFA→DFA Converter** — subset construction to convert NFA to equivalent DFA
- **Catppuccin Mocha** dark theme throughout

## Requirements

- .NET 10+ SDK (tested with .NET 11 preview)
- MAUI workload: `dotnet workload install maui`

## Build & Run

```bash
cd automaton-maui

# Build all target frameworks
dotnet build

# Run on Mac Catalyst (macOS)
dotnet build -t:Run -f net10.0-maccatalyst

# Run on iOS Simulator
dotnet build -t:Run -f net10.0-ios

# Run on Android Emulator
dotnet build -t:Run -f net10.0-android
```

## Project Structure

```
automaton-maui/
├── Models/
│   └── AutomatonTypes.cs    # Core domain types (State, Symbol, Transition, Automaton, etc.)
├── Core/
│   ├── AutomatonParser.cs   # Recursive-descent DSL parser & formatter
│   ├── Simulator.cs         # Pure simulation engine
│   ├── Validator.cs         # Structural validation
│   └── Converter.cs         # NFA→DFA subset construction
├── Services/
│   └── AppViewModel.cs      # MVVM ViewModel + sample data
├── UI/
│   ├── Controls/
│   │   └── AutomatonCanvasDrawable.cs  # MAUI Graphics renderer
│   └── Converters/
│       └── Converters.cs    # Value converters
├── MainPage.xaml(.cs)       # Main UI layout
├── App.xaml(.cs)            # App entry + theme resources
└── AppShell.xaml(.cs)       # Shell navigation
```

## DSL Format

```
automaton DFA
alphabet: a,b
states: q0,q1,q2
start: q0
accept: q2
transitions:
  q0,a -> q1
  q1,b -> q2
  q2,a -> q2
```

Supports `DFA`, `NFA`, and `ENFA` (ε-NFA with `eps` transitions).
