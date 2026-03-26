using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using AutomatonDesigner.Core;
using AutomatonDesigner.Models;

namespace AutomatonDesigner.Services;

/// <summary>
/// Main application view model: holds automaton state, drives parsing,
/// simulation, validation, tests, and canvas rendering.
/// </summary>
public sealed class AppViewModel : INotifyPropertyChanged
{
    // ── Automaton state ──────────────────────────────────────────────

    Automaton _automaton = SampleData.SampleDfa;
    public Automaton Automaton
    {
        get => _automaton;
        set { _automaton = value; OnPropertyChanged(); OnPropertyChanged(nameof(DslText)); }
    }

    Dictionary<State, Position> _layout = [];
    public Dictionary<State, Position> Layout
    {
        get => _layout;
        set { _layout = value; OnPropertyChanged(); }
    }

    // ── DSL editor ───────────────────────────────────────────────────

    string _dslText = "";
    public string DslText
    {
        get => _dslText;
        set
        {
            _dslText = value;
            OnPropertyChanged();
            ParseDsl();
        }
    }

    string _parseStatus = "";
    public string ParseStatus
    {
        get => _parseStatus;
        set { _parseStatus = value; OnPropertyChanged(); }
    }

    bool _parseOk;
    public bool ParseOk
    {
        get => _parseOk;
        set { _parseOk = value; OnPropertyChanged(); }
    }

    // ── Simulation ───────────────────────────────────────────────────

    string _simInput = "";
    public string SimInput
    {
        get => _simInput;
        set { _simInput = value; OnPropertyChanged(); }
    }

    SimResult? _simResult;
    public SimResult? SimResult
    {
        get => _simResult;
        set { _simResult = value; OnPropertyChanged(); }
    }

    int _simStepIdx;
    public int SimStepIdx
    {
        get => _simStepIdx;
        set { _simStepIdx = value; OnPropertyChanged(); OnPropertyChanged(nameof(CurrentStep)); }
    }

    public SimStep? CurrentStep =>
        SimResult != null && SimStepIdx < SimResult.Steps.Count
            ? SimResult.Steps[SimStepIdx] : null;

    HashSet<State> _activeStates = [];
    public HashSet<State> ActiveStates
    {
        get => _activeStates;
        set { _activeStates = value; OnPropertyChanged(); }
    }

    string _simResultText = "";
    public string SimResultText
    {
        get => _simResultText;
        set { _simResultText = value; OnPropertyChanged(); }
    }

    // ── Validation ───────────────────────────────────────────────────

    ObservableCollection<string> _validationIssues = [];
    public ObservableCollection<string> ValidationIssues
    {
        get => _validationIssues;
        set { _validationIssues = value; OnPropertyChanged(); }
    }

    // ── Tests ────────────────────────────────────────────────────────

    public ObservableCollection<TestCaseVM> TestCases { get; } = [];

    string _testSummary = "No tests run yet";
    public string TestSummary
    {
        get => _testSummary;
        set { _testSummary = value; OnPropertyChanged(); }
    }

    string _newTestInput = "";
    public string NewTestInput
    {
        get => _newTestInput;
        set { _newTestInput = value; OnPropertyChanged(); }
    }

    bool _newTestExpected = true;
    public bool NewTestExpected
    {
        get => _newTestExpected;
        set { _newTestExpected = value; OnPropertyChanged(); }
    }

    // ── Canvas invalidation trigger ──────────────────────────────────

    /// <summary>Raised when the canvas should repaint.</summary>
    public event Action? CanvasInvalidated;

    /// <summary>Request a canvas repaint (called by drawable during drag).</summary>
    public void RequestCanvasInvalidate() => CanvasInvalidated?.Invoke();

    // ── Initialisation ───────────────────────────────────────────────

    public AppViewModel()
    {
        _automaton = SampleData.SampleDfa;
        _layout = CircularLayout(_automaton);
        _dslText = AutomatonParser.Format(_automaton);
        ParseOk = true;
        ParseStatus = "✓ Valid automaton";

        foreach (var tc in SampleData.SampleTests)
            TestCases.Add(new TestCaseVM(tc));
    }

    // ── Commands ─────────────────────────────────────────────────────

    public void ParseDsl()
    {
        var (result, error) = AutomatonParser.Parse(_dslText);
        if (result != null)
        {
            _automaton = result;
            _layout = CircularLayout(result);
            ParseOk = true;
            ParseStatus = "✓ Valid automaton";
            OnPropertyChanged(nameof(Automaton));
            OnPropertyChanged(nameof(Layout));
            CanvasInvalidated?.Invoke();
        }
        else
        {
            ParseOk = false;
            ParseStatus = $"✗ {error?.Split('\n').FirstOrDefault() ?? "Parse error"}";
        }
    }

    public void FormatDsl()
    {
        _dslText = AutomatonParser.Format(_automaton);
        OnPropertyChanged(nameof(DslText));
    }

    public void RunSimulation()
    {
        SimResult = Simulator.Simulate(Automaton, SimInput);
        SimStepIdx = SimResult.Steps.Count - 1;
        UpdateSimHighlight();
        SimResultText = SimResult.Accepted ? "✓ ACCEPTED" : "✗ REJECTED";
    }

    public void StepSimulation()
    {
        if (SimResult == null)
        {
            SimResult = Simulator.Simulate(Automaton, SimInput);
            SimStepIdx = 0;
        }
        else if (SimStepIdx < SimResult.Steps.Count - 1)
        {
            SimStepIdx++;
            if (SimStepIdx == SimResult.Steps.Count - 1)
                SimResultText = SimResult.Accepted ? "✓ ACCEPTED" : "✗ REJECTED";
        }
        UpdateSimHighlight();
    }

    public void ResetSimulation()
    {
        SimResult = null;
        SimStepIdx = 0;
        SimResultText = "";
        ActiveStates = [];
        CanvasInvalidated?.Invoke();
    }

    void UpdateSimHighlight()
    {
        if (CurrentStep != null)
        {
            ActiveStates = new HashSet<State>(CurrentStep.ActiveStates);
            CanvasInvalidated?.Invoke();
        }
    }

    public void ValidateAutomaton()
    {
        var issues = Validator.Validate(Automaton);
        ValidationIssues.Clear();
        if (issues.Count == 0)
            ValidationIssues.Add("✓ No issues found");
        else
            foreach (var i in issues) ValidationIssues.Add($"⚠ {i.Message}");
    }

    public void ConvertToDfa()
    {
        var dfa = Converter.NfaToDfa(Automaton);
        Automaton = dfa;
        Layout = CircularLayout(dfa);
        _dslText = AutomatonParser.Format(dfa);
        OnPropertyChanged(nameof(DslText));
        CanvasInvalidated?.Invoke();
    }

    public void AddTestCase()
    {
        if (string.IsNullOrEmpty(NewTestInput) && NewTestExpected) return;
        TestCases.Add(new TestCaseVM(new TestCase(NewTestInput, NewTestExpected)));
        NewTestInput = "";
    }

    public void RemoveLastTest()
    {
        if (TestCases.Count > 0) TestCases.RemoveAt(TestCases.Count - 1);
    }

    public void RunAllTests()
    {
        var tests = TestCases.Select(tc => tc.TestCase).ToList();
        var results = Simulator.RunTests(Automaton, tests);

        for (int i = 0; i < results.Count; i++)
        {
            TestCases[i].Passed = results[i].Passed;
            TestCases[i].Actual = results[i].Actual;
            TestCases[i].HasRun = true;
        }

        int passed = results.Count(r => r.Passed);
        TestSummary = passed == results.Count
            ? $"All {results.Count} tests passed ✓"
            : $"{passed}/{results.Count} passed";
    }

    // ── Layout helper ────────────────────────────────────────────────

    public static Dictionary<State, Position> CircularLayout(Automaton aut)
    {
        var states = aut.States.OrderBy(s => s.Name).ToList();
        int n = states.Count;
        double cx = 400, cy = 300, radius = Math.Min(220, n * 50);
        var layout = new Dictionary<State, Position>();
        for (int i = 0; i < n; i++)
        {
            double angle = 2 * Math.PI * i / Math.Max(1, n) - Math.PI / 2;
            layout[states[i]] = new Position(cx + radius * Math.Cos(angle), cy + radius * Math.Sin(angle));
        }
        return layout;
    }

    // ── INotifyPropertyChanged ───────────────────────────────────────

    public event PropertyChangedEventHandler? PropertyChanged;
    void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>Observable wrapper for a test case.</summary>
public sealed class TestCaseVM : INotifyPropertyChanged
{
    public TestCase TestCase { get; }
    public string Input => TestCase.Input;
    public bool Expected => TestCase.Expected;

    bool _hasRun;
    public bool HasRun { get => _hasRun; set { _hasRun = value; OnPropertyChanged(); OnPropertyChanged(nameof(StatusIcon)); OnPropertyChanged(nameof(StatusColor)); } }

    bool _passed;
    public bool Passed { get => _passed; set { _passed = value; OnPropertyChanged(); OnPropertyChanged(nameof(StatusIcon)); OnPropertyChanged(nameof(StatusColor)); } }

    bool _actual;
    public bool Actual { get => _actual; set { _actual = value; OnPropertyChanged(); OnPropertyChanged(nameof(ActualText)); } }

    public string StatusIcon => HasRun ? (Passed ? "✓" : "✗") : "○";
    public Color StatusColor => HasRun ? (Passed ? Colors.LightGreen : Colors.Salmon) : Colors.Gray;
    public string ActualText => HasRun ? (Actual ? "accept" : "reject") : "—";

    public TestCaseVM(TestCase tc) => TestCase = tc;

    public event PropertyChangedEventHandler? PropertyChanged;
    void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>Sample data for initial state.</summary>
static class SampleData
{
    public const string SampleDsl = """
        automaton DFA
        alphabet: a,b
        states: q0,q1,q2
        start: q0
        accept: q2
        transitions:
          q0,a -> q1
          q0,b -> q0
          q1,a -> q1
          q1,b -> q2
          q2,a -> q1
          q2,b -> q0
        """;

    public static readonly Automaton SampleDfa = AutomatonParser.Parse(SampleDsl).Result!;

    public static readonly List<TestCase> SampleTests =
    [
        new("ab", true), new("aab", true), new("abb", false),
        new("bab", true), new("", false), new("abab", true)
    ];
}
