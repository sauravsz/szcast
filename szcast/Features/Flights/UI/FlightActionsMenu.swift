import AppKit

@MainActor
enum FlightActionsMenu {
    static func content(flight: FlightResult, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: "\(flight.airlineName) \(flight.flightNumber)",
            items: [
                PopoverMenuItem(
                    title: String(localized: "Copy Flight Status"),
                    systemImage: "airplane",
                    shortcut: "↵"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(flight.summaryText, forType: .string)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy Flight Number (\(flight.flightNumber))"),
                    systemImage: "doc.on.doc",
                    shortcut: "⌘C"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(flight.flightNumber, forType: .string)
                }
            ]
        )
    }
}
