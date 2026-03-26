namespace AutomatonDesigner.Views;

public partial class AboutPage : ContentPage
{
    public AboutPage()
    {
        InitializeComponent();
    }

    private async void OnGitHubTapped(object? sender, EventArgs e)
    {
        await Launcher.OpenAsync("https://github.com/rmarinho/Automaton");
    }
}
