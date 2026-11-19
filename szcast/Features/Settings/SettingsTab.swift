enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, quicklinks, appleShortcuts,
        fallbacks, clipboard, snippets, fileSearch, windowManagement, displayTweaks, cleanKeyboard, navigation, notes, calendar, emoji,
        dictation, ai, quickActions, extensions, permissions, backup, changelog, about, enteAuth, duckDuckGoEmail, keepassxc, extendedFeatures
    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    init?(slug: String) {
        guard let tab = Self.allCases.first(where: { $0.slug == slug }) else { return nil }
        self = tab
    }

    /// `szcast://settings/<slug>`; spelled out, so renaming a case never breaks a saved link.
    var slug: String {
        switch self {
        case .general: "general"
        case .applications: "applications"
        case .systemSettings: "system-settings"
        case .systemActions: "system-actions"
        case .commands: "commands"
        case .quicklinks: "quicklinks"
        case .appleShortcuts: "apple-shortcuts"
        case .fallbacks: "fallbacks"
        case .clipboard: "clipboard"
        case .snippets: "snippets"
        case .fileSearch: "file-search"
        case .windowManagement: "window-management"
        case .displayTweaks: "display-tweaks"
        case .navigation: "navigation"
        case .notes: "notes"
        case .calendar: "calendar"
        case .emoji: "emoji"
        case .dictation: "dictation"
        case .ai: "ai"
        case .quickActions: "quick-actions"
        case .extensions: "extensions"
        case .permissions: "permissions"
        case .backup: "backup"
        case .changelog: "changelog"
        case .about: "about"
        case .enteAuth: "ente-auth"
        case .duckDuckGoEmail: "duckduckgo-email"
        case .cleanKeyboard: "clean-keyboard"
        case .keepassxc: "keepassxc"
        case .extendedFeatures: "extended-features"
        }
    }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .applications: return String(localized: "Applications")
        case .systemSettings: return String(localized: "System Settings")
        case .systemActions: return String(localized: "System Actions")
        case .commands: return String(localized: "Commands")
        case .quicklinks: return String(localized: "Quicklinks")
        case .appleShortcuts: return String(localized: "Apple Shortcuts")
        case .fallbacks: return String(localized: "Fallbacks")
        case .ai: return String(localized: "AI")
        case .quickActions: return String(localized: "Quick Actions")
        case .dictation: return String(localized: "Dictation")
        case .fileSearch: return String(localized: "File Search")
        case .notes: return String(localized: "Notes")
        case .snippets: return String(localized: "Snippets")
        case .navigation: return String(localized: "Navigation")
        case .windowManagement: return String(localized: "Window Management")
        case .displayTweaks: return String(localized: "Display Tweaks")
        case .cleanKeyboard: return String(localized: "Clean Keyboard")
        case .clipboard: return String(localized: "Clipboard")
        case .emoji: return String(localized: "Emoji & Symbols")
        case .calendar: return String(localized: "Calendar")
        case .extensions: return String(localized: "Extensions")
        case .permissions: return String(localized: "Permissions")
        case .backup: return String(localized: "Backup")
        case .changelog: return String(localized: "Changelog")
        case .about: return String(localized: "About")
        case .enteAuth: return String(localized: "Ente Auth")
        case .duckDuckGoEmail: return String(localized: "DuckDuckGo Email")
        case .keepassxc: return String(localized: "KeePassXC")
        case .extendedFeatures: return String(localized: "Extended Features")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .applications: return "square.grid.2x2"
        case .systemSettings: return "gearshape"
        case .systemActions: return "bolt"
        case .commands: return "terminal"
        case .quicklinks: return "link"
        case .appleShortcuts: return "square.2.layers.3d"
        case .fallbacks: return "arrow.turn.down.right"
        case .ai: return "sparkles"
        case .quickActions: return "wand.and.sparkles"
        case .dictation: return "waveform"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .notes: return "text.page"
        case .snippets: return "curlybraces"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .displayTweaks: return "sun.max"
        case .cleanKeyboard: return "keyboard"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .calendar: return "calendar"
        case .extensions: return "puzzlepiece.extension"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.up.arrow.down.circle"
        case .changelog: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        case .enteAuth: return "key.fill"
        case .duckDuckGoEmail: return "envelope.badge.shield.half.filled"
        case .keepassxc: return "lock.fill"
        case .extendedFeatures: return "sparkles.rectangle.stack"
        }
    }
}

/// Declaration order is display order; not `.Section`, which would shadow SwiftUI's `Section`.
enum SettingsSection: CaseIterable, Identifiable {
    case general, coreFeatures, extendedFeatures, systemAndAbout
    /// See `SettingsTab.id`: distinct types keep the two namespaces from colliding.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .coreFeatures: return String(localized: "Core Features")
        case .extendedFeatures: return String(localized: "Extended Features")
        case .systemAndAbout: return String(localized: "System & About")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .general:
            return [.general, .permissions, .navigation]
        case .coreFeatures:
            return [
                .dictation, .notes, .ai, .quickActions,
                .clipboard, .snippets, .fileSearch, .windowManagement,
                .applications, .commands, .quicklinks, .appleShortcuts, .fallbacks,
                .emoji, .systemActions, .systemSettings
            ]
        case .extendedFeatures:
            return [
                .extendedFeatures, .enteAuth, .keepassxc, .duckDuckGoEmail,
                .displayTweaks, .calendar, .cleanKeyboard
            ]
        case .systemAndAbout:
            return [.extensions, .backup, .changelog, .about]
        }
    }
}
