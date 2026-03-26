namespace AutomatonDesigner.Services;

public sealed class SettingsService
{
    // Provider: "Anthropic", "Llama", "Copilot", "PrivateAPI"
    public string Provider
    {
        get => Preferences.Get("llm_provider", "Anthropic");
        set => Preferences.Set("llm_provider", value);
    }

    public string Model
    {
        get => Preferences.Get("llm_model", "claude-sonnet-4-20250514");
        set => Preferences.Set("llm_model", value);
    }

    public string Endpoint
    {
        get => Preferences.Get("llm_endpoint", "https://api.anthropic.com/v1/messages");
        set => Preferences.Set("llm_endpoint", value);
    }

    public string PrivateApiUrl
    {
        get => Preferences.Get("private_api_url", "http://localhost:8023");
        set => Preferences.Set("private_api_url", value);
    }

    // Secure storage for API keys
    public async Task<string> GetApiKeyAsync() => await SecureStorage.GetAsync("llm_api_key") ?? "";
    public Task SetApiKeyAsync(string key) => SecureStorage.SetAsync("llm_api_key", key);

    public async Task<string> GetPrivateTokenAsync() => await SecureStorage.GetAsync("private_api_token") ?? "";
    public Task SetPrivateTokenAsync(string token) => SecureStorage.SetAsync("private_api_token", token);
}
