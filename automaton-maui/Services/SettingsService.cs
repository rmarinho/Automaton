namespace AutomatonDesigner.Services;

/// <summary>
/// Stores LLM settings. Uses SecureStorage for API keys when available (requires
/// keychain entitlements + code signing), falling back to Preferences for unsigned
/// development builds.
/// </summary>
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

    // API key storage with SecureStorage → Preferences fallback
    public async Task<string> GetApiKeyAsync() => await GetSecureAsync("llm_api_key");
    public async Task SetApiKeyAsync(string key) => await SetSecureAsync("llm_api_key", key);

    public async Task<string> GetPrivateTokenAsync() => await GetSecureAsync("private_api_token");
    public async Task SetPrivateTokenAsync(string token) => await SetSecureAsync("private_api_token", token);

    private static async Task<string> GetSecureAsync(string key)
    {
        try
        {
            var value = await SecureStorage.GetAsync(key);
            if (!string.IsNullOrEmpty(value))
                return value;
        }
        catch
        {
            // Keychain unavailable
        }

        // Fall back to Preferences (used when SecureStorage is unavailable or empty)
        return Preferences.Get($"_secure_{key}", "");
    }

    private static async Task SetSecureAsync(string key, string value)
    {
        try
        {
            await SecureStorage.SetAsync(key, value);
            return; // Keychain worked — done
        }
        catch
        {
            // Keychain unavailable — fall back to Preferences
        }

        Preferences.Set($"_secure_{key}", value);
    }
}
