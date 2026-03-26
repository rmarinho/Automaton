using AutomatonDesigner.Services;
using AutomatonDesigner.UI.Controls;

namespace AutomatonDesigner;

public partial class MainPage : ContentPage
{
    readonly AppViewModel _vm = new();
    readonly AutomatonCanvasDrawable _drawable;

    CancellationTokenSource? _parseDebounce;

    public MainPage()
    {
        InitializeComponent();

        _drawable = new AutomatonCanvasDrawable { ViewModel = _vm };
        CanvasView.Drawable = _drawable;

        DslEditor.Text = _vm.DslText;
        UpdateParseStatus();
        RenderTestList();

        _vm.CanvasInvalidated += () =>
            MainThread.BeginInvokeOnMainThread(() => CanvasView.Invalidate());

        NewTestExpected.SelectedIndex = 0;
    }

    // ── DSL Editor ────────────────────────────────────────

    void OnDslTextChanged(object? sender, TextChangedEventArgs e)
    {
        _parseDebounce?.Cancel();
        _parseDebounce = new CancellationTokenSource();
        var token = _parseDebounce.Token;

        Task.Delay(400, token).ContinueWith(_ =>
        {
            if (token.IsCancellationRequested) return;
            MainThread.BeginInvokeOnMainThread(() =>
            {
                _vm.DslText = DslEditor.Text ?? "";
                UpdateParseStatus();
            });
        }, TaskScheduler.Default);
    }

    void OnFormat(object? sender, EventArgs e)
    {
        _vm.FormatDsl();
        DslEditor.Text = _vm.DslText;
    }

    void UpdateParseStatus()
    {
        ParseStatusLabel.Text = _vm.ParseStatus;
        ParseStatusLabel.TextColor = _vm.ParseOk
            ? Color.FromArgb("#a6e3a1")
            : Color.FromArgb("#f38ba8");
    }

    // ── Simulation ────────────────────────────────────────

    void OnSimRun(object? sender, EventArgs e)
    {
        _vm.SimInput = SimInputEntry.Text ?? "";
        _vm.RunSimulation();
        UpdateSimUI();
    }

    void OnSimStep(object? sender, EventArgs e)
    {
        _vm.SimInput = SimInputEntry.Text ?? "";
        _vm.StepSimulation();
        UpdateSimUI();
    }

    void OnSimReset(object? sender, EventArgs e)
    {
        _vm.ResetSimulation();
        SimResultLabel.Text = "";
        SimTraceStack.Children.Clear();
    }

    void UpdateSimUI()
    {
        if (_vm.SimResult != null)
        {
            SimResultLabel.Text = _vm.SimResultText;
            SimResultLabel.TextColor = _vm.SimResult.Accepted
                ? Color.FromArgb("#a6e3a1")
                : Color.FromArgb("#f38ba8");
        }

        SimTraceStack.Children.Clear();
        if (_vm.SimResult != null)
        {
            for (int i = 0; i <= _vm.SimStepIdx && i < _vm.SimResult.Steps.Count; i++)
            {
                var step = _vm.SimResult.Steps[i];
                var sym = step.ReadSymbol?.Char.ToString() ?? "—";
                var states = string.Join(", ", step.ActiveStates.Select(s => s.Name));
                bool isCurrent = i == _vm.SimStepIdx;

                var label = new Label
                {
                    FormattedText = new FormattedString
                    {
                        Spans =
                        {
                            new Span { Text = $"Step {step.StepNumber} ", TextColor = Color.FromArgb("#585b70"), FontSize = 12 },
                            new Span { Text = $"{sym} ", TextColor = Color.FromArgb("#f9e2af"), FontSize = 12 },
                            new Span { Text = $"{{{states}}}", TextColor = Color.FromArgb("#a6e3a1"), FontSize = 12 },
                            new Span { Text = $"  rem: \"{step.Remaining}\"", TextColor = Color.FromArgb("#585b70"), FontSize = 12 }
                        }
                    },
                    FontFamily = "Courier New",
                    BackgroundColor = isCurrent ? Color.FromArgb("#313244") : Colors.Transparent,
                    Padding = new Thickness(4, 2)
                };
                SimTraceStack.Children.Add(label);
            }
        }
    }

    // ── Toolbar ───────────────────────────────────────────

    void OnValidate(object? sender, EventArgs e)
    {
        _vm.ValidateAutomaton();
        ValidationStack.Children.Clear();
        foreach (var issue in _vm.ValidationIssues)
        {
            bool isOk = issue.StartsWith("✓");
            ValidationStack.Children.Add(new Label
            {
                Text = issue,
                TextColor = isOk ? Color.FromArgb("#a6e3a1") : Color.FromArgb("#f9e2af"),
                FontSize = 12
            });
        }
    }

    void OnConvert(object? sender, EventArgs e)
    {
        _vm.ConvertToDfa();
        DslEditor.Text = _vm.DslText;
        UpdateParseStatus();
    }

    async void OnSave(object? sender, EventArgs e)
    {
        string path = Path.Combine(FileSystem.AppDataDirectory, "automaton-project.atm");
        await File.WriteAllTextAsync(path, _vm.DslText);
        await DisplayAlertAsync("Saved", $"Project saved to:\n{path}", "OK");
    }

    // ── Test Runner ───────────────────────────────────────

    void OnAddTest(object? sender, EventArgs e)
    {
        bool expected = NewTestExpected.SelectedIndex == 0;
        _vm.NewTestInput = NewTestEntry.Text ?? "";
        _vm.NewTestExpected = expected;
        _vm.AddTestCase();
        NewTestEntry.Text = "";
        RenderTestList();
    }

    void OnRemoveTest(object? sender, EventArgs e)
    {
        _vm.RemoveLastTest();
        RenderTestList();
    }

    void OnRunTests(object? sender, EventArgs e)
    {
        _vm.RunAllTests();
        RenderTestList();
        TestSummaryLabel.Text = _vm.TestSummary;
        TestSummaryLabel.TextColor = _vm.TestSummary.Contains("✓")
            ? Color.FromArgb("#a6e3a1")
            : Color.FromArgb("#f38ba8");
    }

    void RenderTestList()
    {
        TestListStack.Children.Clear();
        foreach (var tc in _vm.TestCases)
        {
            var row = new HorizontalStackLayout { Spacing = 8, Padding = new Thickness(0, 2) };
            row.Children.Add(new Label
            {
                Text = tc.StatusIcon,
                TextColor = tc.StatusColor,
                FontSize = 12, FontFamily = "Courier New", WidthRequest = 16
            });
            row.Children.Add(new Label
            {
                Text = $"\"{tc.Input}\"",
                TextColor = Color.FromArgb("#cdd6f4"),
                FontSize = 12, FontFamily = "Courier New"
            });
            row.Children.Add(new Label
            {
                Text = $"expect: {(tc.Expected ? "accept" : "reject")}",
                TextColor = Color.FromArgb("#585b70"),
                FontSize = 12
            });
            row.Children.Add(new Label
            {
                Text = $"actual: {tc.ActualText}",
                TextColor = Color.FromArgb("#585b70"),
                FontSize = 12
            });
            TestListStack.Children.Add(row);
        }
    }
}
