using AutomatonDesigner.Services;
using AutomatonDesigner.Views;
using Microsoft.Extensions.Logging;
using Microsoft.Maui.DevFlow.Agent;

namespace AutomatonDesigner;

public static class MauiProgram
{
	public static MauiApp CreateMauiApp()
	{
		var builder = MauiApp.CreateBuilder();
		builder
			.UseMauiApp<App>()
			.ConfigureFonts(fonts =>
			{
				fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
				fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
			});

		// Services
		builder.Services.AddSingleton<SettingsService>();
		builder.Services.AddSingleton<LLMService>();

		// Pages (transient so they get fresh instances with DI)
		builder.Services.AddTransient<ChatPage>();
		builder.Services.AddTransient<SettingsPage>();

#if DEBUG
		builder.Logging.AddDebug();
		builder.AddMauiDevFlowAgent();
#endif

		return builder.Build();
	}
}
