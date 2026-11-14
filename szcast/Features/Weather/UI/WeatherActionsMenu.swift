import AppKit

@MainActor
enum WeatherActionsMenu {
    static func content(weather: WeatherResult, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: weather.locationName,
            items: [
                PopoverMenuItem(
                    title: String(localized: "Copy Temperature"),
                    systemImage: "thermometer.medium",
                    shortcut: "↵"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(weather.formatTemp(weather.currentTemp), forType: .string)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy Forecast Summary"),
                    systemImage: "doc.on.doc",
                    shortcut: "⌘C"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(weather.summaryText, forType: .string)
                },
                PopoverMenuItem(
                    title: String(localized: weather.isFahrenheit ? "Switch to Celsius" : "Switch to Fahrenheit"),
                    systemImage: "arrow.triangle.2.circlepath",
                    shortcut: "⌘U"
                ) {
                    WeatherService.shared.useFahrenheit.toggle()
                }
            ]
        )
    }
}
