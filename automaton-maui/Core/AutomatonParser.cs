using AutomatonDesigner.Models;

namespace AutomatonDesigner.Core;

/// <summary>
/// Parser and formatter for the automaton DSL.
/// Hand-written recursive-descent parser for simplicity and clear error messages.
/// </summary>
public static class AutomatonParser
{
    public static (Automaton? Result, string? Error) Parse(string input)
    {
        try
        {
            var lines = PreprocessLines(input);
            int idx = 0;

            var type = ParseHeader(lines, ref idx);
            var alphabet = ParseAlphabet(lines, ref idx);
            var states = ParseStates(lines, ref idx);
            var start = ParseStart(lines, ref idx);
            var accept = ParseAccept(lines, ref idx);
            var transitions = ParseTransitions(lines, ref idx);

            var aut = new Automaton
            {
                Type = type,
                States = states,
                Alphabet = alphabet,
                Start = start,
                Accept = accept,
                Transitions = transitions
            };
            return (aut, null);
        }
        catch (ParseException ex)
        {
            return (null, ex.Message);
        }
    }

    public static string Format(Automaton aut)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"automaton {FormatType(aut.Type)}");
        sb.AppendLine($"alphabet: {string.Join(",", aut.Alphabet.OrderBy(s => s.Char).Select(s => s.Char))}");
        sb.AppendLine($"states: {string.Join(",", aut.States.OrderBy(s => s.Name).Select(s => s.Name))}");
        sb.AppendLine($"start: {aut.Start.Name}");
        sb.AppendLine($"accept: {string.Join(",", aut.Accept.OrderBy(s => s.Name).Select(s => s.Name))}");
        sb.AppendLine("transitions:");
        foreach (var t in aut.Transitions.OrderBy(t => t.From.Name).ThenBy(t => FormatLabel(t.Label)))
            sb.AppendLine($"  {t.From.Name},{FormatLabel(t.Label)} -> {t.To.Name}");
        return sb.ToString();
    }

    // ── Preprocessing ─────────────────────────────────────────────────

    static List<string> PreprocessLines(string input)
    {
        return input
            .Split('\n')
            .Select(l =>
            {
                int commentIdx = l.IndexOf("--");
                return (commentIdx >= 0 ? l[..commentIdx] : l).Trim();
            })
            .Where(l => l.Length > 0)
            .ToList();
    }

    // ── Section parsers ───────────────────────────────────────────────

    static AutomatonType ParseHeader(List<string> lines, ref int idx)
    {
        Expect(lines, ref idx, "automaton", out string rest);
        return rest.Trim() switch
        {
            "DFA" => AutomatonType.DFA,
            "NFA" => AutomatonType.NFA,
            "ENFA" or "ε-NFA" or "e-NFA" => AutomatonType.ENFA,
            _ => throw new ParseException($"Unknown automaton type: '{rest.Trim()}'. Expected DFA, NFA, or ENFA.")
        };
    }

    static HashSet<Symbol> ParseAlphabet(List<string> lines, ref int idx)
    {
        Expect(lines, ref idx, "alphabet:", out string rest);
        return rest.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(s =>
            {
                if (s.Length != 1) throw new ParseException($"Alphabet symbol must be a single character, got '{s}'");
                return new Symbol(s[0]);
            })
            .ToHashSet();
    }

    static HashSet<State> ParseStates(List<string> lines, ref int idx)
    {
        Expect(lines, ref idx, "states:", out string rest);
        return rest.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(s => new State(s))
            .ToHashSet();
    }

    static State ParseStart(List<string> lines, ref int idx)
    {
        Expect(lines, ref idx, "start:", out string rest);
        return new State(rest.Trim());
    }

    static HashSet<State> ParseAccept(List<string> lines, ref int idx)
    {
        Expect(lines, ref idx, "accept:", out string rest);
        var trimmed = rest.Trim();
        if (string.IsNullOrEmpty(trimmed)) return [];
        return trimmed.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(s => new State(s))
            .ToHashSet();
    }

    static HashSet<Transition> ParseTransitions(List<string> lines, ref int idx)
    {
        Expect(lines, ref idx, "transitions:", out _);
        var transitions = new HashSet<Transition>();
        while (idx < lines.Count)
        {
            var line = lines[idx];
            var arrowIdx = line.IndexOf("->");
            if (arrowIdx < 0)
                throw new ParseException($"Expected transition 'state,label -> state', got: '{line}'");

            var left = line[..arrowIdx].Trim();
            var right = line[(arrowIdx + 2)..].Trim();

            var commaIdx = left.IndexOf(',');
            if (commaIdx < 0)
                throw new ParseException($"Expected 'state,label' on left side of transition, got: '{left}'");

            var fromName = left[..commaIdx].Trim();
            var labelStr = left[(commaIdx + 1)..].Trim();

            TransitionLabel label = labelStr switch
            {
                "eps" or "ε" or "epsilon" => new OnEpsilon(),
                _ when labelStr.Length == 1 => new OnSymbol(new Symbol(labelStr[0])),
                _ => throw new ParseException($"Invalid transition label: '{labelStr}'")
            };

            transitions.Add(new Transition(new State(fromName), label, new State(right)));
            idx++;
        }
        return transitions;
    }

    // ── Helpers ───────────────────────────────────────────────────────

    static void Expect(List<string> lines, ref int idx, string keyword, out string rest)
    {
        if (idx >= lines.Count)
            throw new ParseException($"Expected '{keyword}' but reached end of input");
        var line = lines[idx];
        if (!line.StartsWith(keyword, StringComparison.OrdinalIgnoreCase))
            throw new ParseException($"Expected '{keyword}', got: '{line}'");
        rest = line[keyword.Length..];
        idx++;
    }

    static string FormatType(AutomatonType t) => t switch
    {
        AutomatonType.DFA => "DFA",
        AutomatonType.NFA => "NFA",
        AutomatonType.ENFA => "ENFA",
        _ => "DFA"
    };

    static string FormatLabel(TransitionLabel l) => l switch
    {
        OnSymbol s => s.Symbol.Char.ToString(),
        OnEpsilon => "eps",
        _ => "?"
    };
}

public class ParseException(string message) : Exception(message);
