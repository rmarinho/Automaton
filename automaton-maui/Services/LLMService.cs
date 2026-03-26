using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AutomatonDesigner.Services;

public record ChatMsg(string Role, string Content);

public sealed class LLMService
{
    private readonly SettingsService _settings;
    private readonly HttpClient _http = new();

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public LLMService(SettingsService settings) => _settings = settings;

    public static string SystemPrompt(string? automatonContext = null)
    {
        var prompt = """
            You are an automata theory expert and assistant for the Automaton Designer app. 
            Help users understand DFA, NFA, ε-NFA, pushdown automata, and Turing machines. 
            You can explain the Automaton Designer DSL syntax, analyze automata for correctness, 
            suggest improvements, and help debug transition functions. 
            Keep answers clear and concise. Use examples when helpful.
            """;

        if (!string.IsNullOrWhiteSpace(automatonContext))
            prompt += $"\n\nCurrent automaton:\n```\n{automatonContext}\n```";

        return prompt;
    }

    public async Task<string> SendMessageAsync(
        List<ChatMsg> history,
        string userMessage,
        string? automatonContext = null,
        CancellationToken ct = default)
    {
        var provider = _settings.Provider;

        return provider switch
        {
            "Anthropic" => await SendAnthropicAsync(history, userMessage, automatonContext, ct),
            "Llama" or "Copilot" => await SendOpenAICompatibleAsync(history, userMessage, automatonContext, ct),
            "PrivateAPI" => await SendPrivateApiAsync(userMessage, automatonContext, ct),
            _ => throw new InvalidOperationException($"Unknown provider: {provider}")
        };
    }

    private async Task<string> SendAnthropicAsync(
        List<ChatMsg> history, string userMessage, string? automatonContext, CancellationToken ct)
    {
        var apiKey = await _settings.GetApiKeyAsync();
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new InvalidOperationException("Anthropic API key not configured. Go to Settings to add one.");

        var messages = history
            .Select(m => new { role = m.Role, content = m.Content })
            .Append(new { role = "user", content = userMessage })
            .ToList();

        var body = new
        {
            model = _settings.Model,
            max_tokens = 1024,
            system = SystemPrompt(automatonContext),
            messages
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
        request.Headers.Add("x-api-key", apiKey);
        request.Headers.Add("anthropic-version", "2023-06-01");
        request.Content = new StringContent(JsonSerializer.Serialize(body, JsonOpts), Encoding.UTF8, "application/json");

        using var response = await _http.SendAsync(request, ct);
        var json = await response.Content.ReadAsStringAsync(ct);

        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"Anthropic API error ({response.StatusCode}): {TruncateError(json)}");

        using var doc = JsonDocument.Parse(json);
        return doc.RootElement
            .GetProperty("content")[0]
            .GetProperty("text")
            .GetString() ?? "";
    }

    private async Task<string> SendOpenAICompatibleAsync(
        List<ChatMsg> history, string userMessage, string? automatonContext, CancellationToken ct)
    {
        var apiKey = await _settings.GetApiKeyAsync();
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new InvalidOperationException("API key not configured. Go to Settings to add one.");

        var messages = new List<object>
        {
            new { role = "system", content = SystemPrompt(automatonContext) }
        };
        messages.AddRange(history.Select(m => (object)new { role = m.Role, content = m.Content }));
        messages.Add(new { role = "user", content = userMessage });

        var body = new
        {
            model = _settings.Model,
            messages
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, _settings.Endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = new StringContent(JsonSerializer.Serialize(body, JsonOpts), Encoding.UTF8, "application/json");

        using var response = await _http.SendAsync(request, ct);
        var json = await response.Content.ReadAsStringAsync(ct);

        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"API error ({response.StatusCode}): {TruncateError(json)}");

        using var doc = JsonDocument.Parse(json);
        return doc.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString() ?? "";
    }

    private async Task<string> SendPrivateApiAsync(
        string userMessage, string? automatonContext, CancellationToken ct)
    {
        var token = await _settings.GetPrivateTokenAsync();
        if (string.IsNullOrWhiteSpace(token))
            throw new InvalidOperationException("Private API token not configured. Go to Settings to add one.");

        // Build messages array matching the Haskell backend's ChatReq format
        var messages = new List<object>();
        if (!string.IsNullOrWhiteSpace(automatonContext))
            messages.Add(new { role = "system", content = automatonContext });
        messages.Add(new { role = "user", content = userMessage });

        var body = new { messages };

        var url = _settings.PrivateApiUrl.TrimEnd('/') + "/api/chat";
        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = new StringContent(JsonSerializer.Serialize(body, JsonOpts), Encoding.UTF8, "application/json");

        using var response = await _http.SendAsync(request, ct);
        var json = await response.Content.ReadAsStringAsync(ct);

        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"Private API error ({response.StatusCode}): {TruncateError(json)}");

        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("reply").GetString() ?? "";
    }

    private static string TruncateError(string json) =>
        json.Length > 300 ? json[..300] + "…" : json;
}
