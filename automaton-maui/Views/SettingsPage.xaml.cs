using AutomatonDesigner.Services;

namespace AutomatonDesigner.Views;

public partial class SettingsPage : ContentPage
{
    private readonly SettingsService _settings;
    private bool _isLoading;

    // Provider defaults matching the Haskell frontend
    private static readonly Dictionary<string, (string Endpoint, string Model)> ProviderDefaults = new()
    {
        ["Anthropic"] = ("https://api.anthropic.com/v1/messages", "claude-sonnet-4-20250514"),
        ["Llama"]     = ("http://localhost:11434/v1/chat/completions", "llama3"),
        ["Copilot"]   = ("https://api.githubcopilot.com/chat/completions", "gpt-4o"),
        ["PrivateAPI"] = ("http://localhost:8023/api/chat", ""),
    };

    public SettingsPage(SettingsService settings)
    {
        InitializeComponent();
        _settings = settings;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await LoadSettingsAsync();
    }

    private async Task LoadSettingsAsync()
    {
        _isLoading = true;
        try
        {
            var providers = (IList<string>)ProviderPicker.ItemsSource;
            var index = providers.IndexOf(_settings.Provider);
            ProviderPicker.SelectedIndex = index >= 0 ? index : 0;

            ModelEntry.Text = _settings.Model;
            EndpointEntry.Text = _settings.Endpoint;
            PrivateApiUrlEntry.Text = _settings.PrivateApiUrl;

            ApiKeyEntry.Text = await _settings.GetApiKeyAsync();
            PrivateTokenEntry.Text = await _settings.GetPrivateTokenAsync();

            UpdatePrivateApiVisibility();
        }
        finally
        {
            _isLoading = false;
        }
    }

    private void OnProviderChanged(object? sender, EventArgs e)
    {
        UpdatePrivateApiVisibility();

        // Auto-fill endpoint and model defaults when switching providers
        if (!_isLoading && ProviderPicker.SelectedItem?.ToString() is { } provider
            && ProviderDefaults.TryGetValue(provider, out var defaults))
        {
            EndpointEntry.Text = defaults.Endpoint;
            ModelEntry.Text = defaults.Model;
        }
    }

    private void UpdatePrivateApiVisibility()
    {
        PrivateApiSection.IsVisible =
            ProviderPicker.SelectedItem?.ToString() == "PrivateAPI";
    }

    private async void OnSaveClicked(object? sender, EventArgs e)
    {
        SaveButton.IsEnabled = false;
        StatusBanner.IsVisible = false;

        try
        {
            _settings.Provider = ProviderPicker.SelectedItem?.ToString() ?? "Anthropic";
            _settings.Model = ModelEntry.Text ?? "";
            _settings.Endpoint = EndpointEntry.Text ?? "";
            _settings.PrivateApiUrl = PrivateApiUrlEntry.Text ?? "";

            var apiKey = ApiKeyEntry.Text ?? "";
            var privateToken = PrivateTokenEntry.Text ?? "";

            if (!string.IsNullOrEmpty(apiKey))
                await _settings.SetApiKeyAsync(apiKey);

            if (!string.IsNullOrEmpty(privateToken))
                await _settings.SetPrivateTokenAsync(privateToken);

            ShowStatus("Settings saved ✓", success: true);
        }
        catch (Exception ex)
        {
            ShowStatus($"Save failed: {ex.Message}", success: false);
        }
        finally
        {
            SaveButton.IsEnabled = true;
        }
    }

    private async void ShowStatus(string message, bool success)
    {
        StatusBanner.Text = message;
        StatusBanner.TextColor = success
            ? (Color)Application.Current!.Resources["Green"]
            : (Color)Application.Current!.Resources["Red"];
        StatusBanner.IsVisible = true;

        await Task.Delay(3000);
        StatusBanner.IsVisible = false;
    }
}
