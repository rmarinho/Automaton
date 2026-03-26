using AutomatonDesigner.Models;

namespace AutomatonDesigner.Core;

/// <summary>NFA/ε-NFA → DFA conversion via subset construction.</summary>
public static class Converter
{
    public static Automaton NfaToDfa(Automaton nfa)
    {
        if (nfa.Type == AutomatonType.DFA) return nfa;

        var alphabet = nfa.Alphabet.ToList();
        var initSet = nfa.Type == AutomatonType.ENFA
            ? Simulator.EpsilonClosure(nfa, [nfa.Start])
            : new HashSet<State> { nfa.Start };

        // Map from NFA state-sets to DFA state names
        var visited = new Dictionary<string, State>();
        var queue = new Queue<HashSet<State>>();
        var transitions = new HashSet<Transition>();
        int nextId = 0;

        string Key(HashSet<State> ss) =>
            string.Join("|", ss.OrderBy(s => s.Name).Select(s => s.Name));

        State Register(HashSet<State> ss)
        {
            var key = Key(ss);
            if (visited.TryGetValue(key, out var existing)) return existing;
            var name = new State($"d{nextId++}");
            visited[key] = name;
            queue.Enqueue(ss);
            return name;
        }

        var dfaStart = Register(initSet);

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            var fromName = visited[Key(current)];

            foreach (var sym in alphabet)
            {
                var targetSet = Simulator.Step(nfa, current, sym);
                if (targetSet.Count == 0) continue;

                var toName = Register(targetSet);
                transitions.Add(new Transition(fromName, new OnSymbol(sym), toName));
            }
        }

        var dfaStates = visited.Values.ToHashSet();
        var dfaAccept = visited
            .Where(kv =>
            {
                var ss = kv.Key.Split('|').Select(n => new State(n)).ToHashSet();
                return ss.Overlaps(nfa.Accept);
            })
            .Select(kv => kv.Value)
            .ToHashSet();

        return new Automaton
        {
            Type = AutomatonType.DFA,
            States = dfaStates,
            Alphabet = new HashSet<Symbol>(nfa.Alphabet),
            Start = dfaStart,
            Accept = dfaAccept,
            Transitions = transitions
        };
    }
}
