using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using AutomatonDesigner.Services;

namespace AutomatonDesigner.ViewModels;

public sealed class ChatMessageVM : INotifyPropertyChanged
{
    public string Role { get; init; } = "user";
    public string Content { get; init; } = "";
    public bool IsUser => Role == "user";
    public bool IsAssistant => Role == "assistant";

#pragma warning disable CS0067
    public event PropertyChangedEventHandler? PropertyChanged;
#pragma warning restore CS0067
}

public sealed class ChatViewModel : INotifyPropertyChanged
{
    private readonly LLMService _llm;
    private readonly SettingsService _settings;
    private readonly List<ChatMsg> _history = [];

    public ObservableCollection<ChatMessageVM> Messages { get; } = [];

    private string _messageText = "";
    public string MessageText
    {
        get => _messageText;
        set { _messageText = value; OnPropertyChanged(); OnPropertyChanged(nameof(CanSend)); }
    }

    private bool _isLoading;
    public bool IsLoading
    {
        get => _isLoading;
        set { _isLoading = value; OnPropertyChanged(); OnPropertyChanged(nameof(CanSend)); }
    }

    private bool _hasApiKey;
    public bool HasApiKey
    {
        get => _hasApiKey;
        set { _hasApiKey = value; OnPropertyChanged(); OnPropertyChanged(nameof(ShowBanner)); OnPropertyChanged(nameof(CanSend)); }
    }

    private bool _includeContext;
    public bool IncludeContext
    {
        get => _includeContext;
        set { _includeContext = value; OnPropertyChanged(); }
    }

    public string? AutomatonContext { get; set; }

    public bool CanSend => HasApiKey && !IsLoading && !string.IsNullOrWhiteSpace(MessageText);
    public bool ShowBanner => !HasApiKey;

    public string ProviderName => _settings.Provider;

    public ChatViewModel(LLMService llm, SettingsService settings)
    {
        _llm = llm;
        _settings = settings;
    }

    public async Task RefreshApiKeyStatusAsync()
    {
        var provider = _settings.Provider;
        if (provider == "PrivateAPI")
        {
            var token = await _settings.GetPrivateTokenAsync();
            HasApiKey = !string.IsNullOrWhiteSpace(token);
        }
        else
        {
            var key = await _settings.GetApiKeyAsync();
            HasApiKey = !string.IsNullOrWhiteSpace(key);
        }
        OnPropertyChanged(nameof(ProviderName));
    }

    public async Task SendMessageAsync()
    {
        var text = MessageText.Trim();
        if (string.IsNullOrEmpty(text) || IsLoading) return;

        MessageText = "";
        Messages.Add(new ChatMessageVM { Role = "user", Content = text });

        IsLoading = true;
        try
        {
            var context = IncludeContext ? AutomatonContext : null;
            var reply = await _llm.SendMessageAsync(_history, text, context);

            _history.Add(new ChatMsg("user", text));
            _history.Add(new ChatMsg("assistant", reply));

            Messages.Add(new ChatMessageVM { Role = "assistant", Content = reply });
        }
        catch (Exception ex)
        {
            Messages.Add(new ChatMessageVM
            {
                Role = "assistant",
                Content = $"⚠ Error: {ex.Message}"
            });
        }
        finally
        {
            IsLoading = false;
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
