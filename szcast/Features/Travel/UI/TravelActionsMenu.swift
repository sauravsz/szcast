import AppKit

@MainActor
enum TravelActionsMenu {
    static func content(travel: TravelResult, core: AppCore) -> PopoverMenuContent {
        let bestDuration = travel.fastestOption?.durationFormatted ?? ""
        return PopoverMenuContent(
            header: "\(travel.originName) → \(travel.destinationName)",
            items: [
                PopoverMenuItem(
                    title: String(localized: "Copy Travel Time (\(bestDuration))"),
                    systemImage: "clock",
                    shortcut: "↵"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bestDuration, forType: .string)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy Route Summary"),
                    systemImage: "doc.on.doc",
                    shortcut: "⌘C"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(travel.summaryText, forType: .string)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy Directions Link"),
                    systemImage: "map",
                    shortcut: "⌘D"
                ) {
                    if let url = travel.directionsURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                }
            ]
        )
    }
}
