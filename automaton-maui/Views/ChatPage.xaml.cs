using AutomatonDesigner.Services;
using AutomatonDesigner.ViewModels;

namespace AutomatonDesigner.Views;

public partial class ChatPage : ContentPage
{
    private readonly ChatViewModel _vm;

    public ChatPage(LLMService llm, SettingsService settings)
    {
        InitializeComponent();

        _vm = new ChatViewModel(llm, settings);
        BindingContext = _vm;

        _vm.Messages.CollectionChanged += (_, _) => ScrollToBottom();
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await _vm.RefreshApiKeyStatusAsync();

        // Pull current automaton context from the app-level view model
        if (Application.Current?.Windows.FirstOrDefault()?.Page is Shell shell
            && shell.BindingContext is AppViewModel appVm)
        {
            _vm.AutomatonContext = appVm.DslText;
        }
    }

    private async void OnSendClicked(object? sender, EventArgs e) => await _vm.SendMessageAsync();

    private async void OnEntryCompleted(object? sender, EventArgs e) => await _vm.SendMessageAsync();

    private void ScrollToBottom()
    {
        if (_vm.Messages.Count > 0)
        {
            MainThread.BeginInvokeOnMainThread(() =>
            {
                MessagesCollection.ScrollTo(_vm.Messages.Count - 1, position: ScrollToPosition.End, animate: true);
            });
        }
    }
}
