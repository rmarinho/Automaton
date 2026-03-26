using AutomatonDesigner.Models;

namespace AutomatonDesigner.Core;

/// <summary>Structural validation for automata.</summary>
public static class Validator
{
    public static List<ValidationIssue> Validate(Automaton aut)
    {
        var issues = new List<ValidationIssue>();
        issues.AddRange(CheckStartState(aut));
        issues.AddRange(CheckAcceptStates(aut));
        issues.AddRange(CheckTransitionStates(aut));
        issues.AddRange(CheckTransitionSymbols(aut));
        issues.AddRange(CheckUnreachableStates(aut));
        issues.AddRange(CheckDeterminism(aut));
        return issues;
    }

    public static bool IsValid(Automaton aut) => Validate(aut).Count == 0;

    static IEnumerable<ValidationIssue> CheckStartState(Automaton aut)
    {
        if (!aut.States.Contains(aut.Start))
            yield return new StartStateNotInStates(aut.Start);
    }

    static IEnumerable<ValidationIssue> CheckAcceptStates(Automaton aut) =>
        aut.Accept.Where(s => !aut.States.Contains(s)).Select(s => new AcceptStateNotInStates(s));

    static IEnumerable<ValidationIssue> CheckTransitionStates(Automaton aut) =>
        aut.Transitions.SelectMany(t =>
        {
            var issues = new List<ValidationIssue>();
            if (!aut.States.Contains(t.From)) issues.Add(new TransitionFromUndefinedState(t));
            if (!aut.States.Contains(t.To)) issues.Add(new TransitionToUndefinedState(t));
            return issues;
        });

    static IEnumerable<ValidationIssue> CheckTransitionSymbols(Automaton aut) =>
        aut.Transitions
            .Where(t => t.Label is OnSymbol s && !aut.Alphabet.Contains(s.Symbol))
            .Select(t => new UndefinedSymbolInTransition(((OnSymbol)t.Label).Symbol, t));

    static IEnumerable<ValidationIssue> CheckUnreachableStates(Automaton aut)
    {
        var reachable = ComputeReachable(aut);
        return aut.States
            .Where(s => s != aut.Start && !reachable.Contains(s))
            .Select(s => new UnreachableState(s));
    }

    static IEnumerable<ValidationIssue> CheckDeterminism(Automaton aut)
    {
        if (aut.Type != AutomatonType.DFA) yield break;
        foreach (var state in aut.States)
        {
            foreach (var sym in aut.Alphabet)
            {
                int count = aut.Transitions.Count(t =>
                    t.From == state && t.Label is OnSymbol s && s.Symbol == sym);
                if (count > 1)
                    yield return new NonDeterministicTransition(state, sym);
            }
        }
    }

    static HashSet<State> ComputeReachable(Automaton aut)
    {
        var visited = new HashSet<State> { aut.Start };
        var frontier = new HashSet<State> { aut.Start };
        while (frontier.Count > 0)
        {
            var next = new HashSet<State>();
            foreach (var t in aut.Transitions)
            {
                if (frontier.Contains(t.From) && !visited.Contains(t.To))
                    next.Add(t.To);
            }
            if (next.Count == 0) break;
            visited.UnionWith(next);
            frontier = next;
        }
        return visited;
    }
}
