namespace AutomatonDesigner.Models;

/// <summary>Flavour of automaton.</summary>
public enum AutomatonType { DFA, NFA, ENFA }

/// <summary>A state in an automaton, identified by name.</summary>
public sealed record State(string Name)
{
    public override string ToString() => Name;
}

/// <summary>A symbol in the input alphabet.</summary>
public sealed record Symbol(char Char)
{
    public override string ToString() => Char.ToString();
}

/// <summary>A transition label: a concrete symbol or epsilon.</summary>
public abstract record TransitionLabel;
public sealed record OnSymbol(Symbol Symbol) : TransitionLabel;
public sealed record OnEpsilon() : TransitionLabel;

/// <summary>A transition between two states.</summary>
public sealed record Transition(State From, TransitionLabel Label, State To);

/// <summary>A complete automaton definition.</summary>
public sealed class Automaton
{
    public AutomatonType Type { get; init; } = AutomatonType.DFA;
    public HashSet<State> States { get; init; } = [];
    public HashSet<Symbol> Alphabet { get; init; } = [];
    public required State Start { get; init; }
    public HashSet<State> Accept { get; init; } = [];
    public HashSet<Transition> Transitions { get; init; } = [];

    public static Automaton Empty => new()
    {
        Type = AutomatonType.DFA,
        States = [new("q0")],
        Alphabet = [],
        Start = new("q0"),
        Accept = [],
        Transitions = []
    };
}

/// <summary>A single step in a simulation trace.</summary>
public sealed record SimStep(
    int StepNumber,
    Symbol? ReadSymbol,
    HashSet<State> ActiveStates,
    string Remaining);

/// <summary>Result of simulating an automaton on an input string.</summary>
public sealed record SimResult(bool Accepted, List<SimStep> Steps, string Input);

/// <summary>A test case: input string + expected result.</summary>
public sealed record TestCase(string Input, bool Expected);

/// <summary>Result of running a single test case.</summary>
public sealed record TestResult(TestCase TestCase, bool Passed, bool Actual);

/// <summary>Issues found during validation.</summary>
public abstract record ValidationIssue(string Message);
public sealed record UnreachableState(State S) : ValidationIssue($"Unreachable state: {S.Name}");
public sealed record UndefinedSymbolInTransition(Symbol Sym, Transition T)
    : ValidationIssue($"Symbol '{Sym.Char}' in transition {T.From.Name},{Sym.Char} -> {T.To.Name} is not in the alphabet");
public sealed record StartStateNotInStates(State S) : ValidationIssue($"Start state {S.Name} is not in the set of states");
public sealed record AcceptStateNotInStates(State S) : ValidationIssue($"Accept state {S.Name} is not in the set of states");
public sealed record TransitionFromUndefinedState(Transition T)
    : ValidationIssue($"Transition from undefined state: {T.From.Name}");
public sealed record TransitionToUndefinedState(Transition T)
    : ValidationIssue($"Transition to undefined state: {T.To.Name}");
public sealed record NonDeterministicTransition(State S, Symbol Sym)
    : ValidationIssue($"Non-deterministic: state {S.Name} has multiple transitions on '{Sym.Char}'");

/// <summary>Position on the visual canvas.</summary>
public sealed record Position(double X, double Y);
