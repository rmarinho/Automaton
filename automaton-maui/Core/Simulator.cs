using AutomatonDesigner.Models;

namespace AutomatonDesigner.Core;

/// <summary>
/// Pure simulation engine for DFA, NFA, and ε-NFA automata.
/// </summary>
public static class Simulator
{
    /// <summary>Compute the epsilon closure of a set of states.</summary>
    public static HashSet<State> EpsilonClosure(Automaton aut, HashSet<State> initial)
    {
        var visited = new HashSet<State>(initial);
        var frontier = new HashSet<State>(initial);

        while (frontier.Count > 0)
        {
            var next = new HashSet<State>();
            foreach (var t in aut.Transitions)
            {
                if (t.Label is OnEpsilon && frontier.Contains(t.From) && !visited.Contains(t.To))
                    next.Add(t.To);
            }
            if (next.Count == 0) break;
            visited.UnionWith(next);
            frontier = next;
        }
        return visited;
    }

    /// <summary>Advance one step: compute next states after reading a symbol.</summary>
    public static HashSet<State> Step(Automaton aut, HashSet<State> current, Symbol sym)
    {
        var targets = new HashSet<State>();
        foreach (var t in aut.Transitions)
        {
            if (t.Label is OnSymbol s && s.Symbol == sym && current.Contains(t.From))
                targets.Add(t.To);
        }
        return aut.Type == AutomatonType.ENFA ? EpsilonClosure(aut, targets) : targets;
    }

    /// <summary>Compute initial active states (with ε-closure for ε-NFA).</summary>
    static HashSet<State> InitialStates(Automaton aut)
    {
        var init = new HashSet<State> { aut.Start };
        return aut.Type == AutomatonType.ENFA ? EpsilonClosure(aut, init) : init;
    }

    /// <summary>Run a full simulation and return step-by-step trace.</summary>
    public static SimResult Simulate(Automaton aut, string input)
    {
        var active = InitialStates(aut);
        var steps = new List<SimStep>
        {
            new(0, null, new HashSet<State>(active), input)
        };

        for (int i = 0; i < input.Length; i++)
        {
            var sym = new Symbol(input[i]);
            active = Step(aut, active, sym);
            steps.Add(new SimStep(i + 1, sym, new HashSet<State>(active), input[(i + 1)..]));
        }

        bool accepted = active.Overlaps(aut.Accept);
        return new SimResult(accepted, steps, input);
    }

    /// <summary>Quick check: does the automaton accept the string?</summary>
    public static bool Accepts(Automaton aut, string input) =>
        Simulate(aut, input).Accepted;

    /// <summary>Run a batch of test cases.</summary>
    public static List<TestResult> RunTests(Automaton aut, List<TestCase> tests) =>
        tests.Select(tc =>
        {
            bool actual = Accepts(aut, tc.Input);
            return new TestResult(tc, actual == tc.Expected, actual);
        }).ToList();
}
