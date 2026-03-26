namespace AutomatonDesigner.Services;

/// <summary>
/// Stores LLM settings. Uses SecureStorage for API keys (backed by Keychain on
/// Apple platforms, Keystore on Android). Falls back to Preferences if SecureStorage
/// is unavailable (e.g. unsigned Mac Catalyst builds without keychain entitlement).
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

    // API key storage — SecureStorage with Preferences fallback
    public Task<string> GetApiKeyAsync() => GetSecureAsync("llm_api_key");
    public Task SetApiKeyAsync(string key) => SetSecureAsync("llm_api_key", key);

    public Task<string> GetPrivateTokenAsync() => GetSecureAsync("private_api_token");
    public Task SetPrivateTokenAsync(string token) => SetSecureAsync("private_api_token", token);

    private static async Task<string> GetSecureAsync(string key)
    {
        try
        {
            var value = await SecureStorage.Default.GetAsync(key);
            if (!string.IsNullOrEmpty(value))
                return value;
        }
        catch
        {
            // Corrupted value or Keychain unavailable — clear and fall through
            SecureStorage.Default.RemoveAll();
        }

        // Fallback for unsigned builds where SecureStorage silently returns null
        return Preferences.Get($"_secure_{key}", "");
    }

    private static async Task SetSecureAsync(string key, string value)
    {
        try
        {
            await SecureStorage.Default.SetAsync(key, value);
        }
        catch
        {
            // Keychain unavailable (unsigned build) — use Preferences fallback
            Preferences.Set($"_secure_{key}", value);
        }
    }
}
