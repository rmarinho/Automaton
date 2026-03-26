using AutomatonDesigner.Services;

namespace AutomatonDesigner.Views;

public partial class SettingsPage : ContentPage
{
    private readonly SettingsService _settings;

    public SettingsPage(SettingsService settings)
    {
        InitializeComponent();
        _settings = settings;
        LoadSettings();
    }

    private async void LoadSettings()
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

    private void OnProviderChanged(object? sender, EventArgs e)
    {
        UpdatePrivateApiVisibility();
    }

    private void UpdatePrivateApiVisibility()
    {
        PrivateApiSection.IsVisible =
            ProviderPicker.SelectedItem?.ToString() == "PrivateAPI";
    }

    private async void OnSaveClicked(object? sender, EventArgs e)
    {
        _settings.Provider = ProviderPicker.SelectedItem?.ToString() ?? "Anthropic";
        _settings.Model = ModelEntry.Text ?? "";
        _settings.Endpoint = EndpointEntry.Text ?? "";
        _settings.PrivateApiUrl = PrivateApiUrlEntry.Text ?? "";

        await _settings.SetApiKeyAsync(ApiKeyEntry.Text ?? "");
        await _settings.SetPrivateTokenAsync(PrivateTokenEntry.Text ?? "");

        SavedLabel.IsVisible = true;
        await Task.Delay(2000);
        SavedLabel.IsVisible = false;
    }
}
