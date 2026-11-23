import SwiftUI

struct SettingsDetailView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(AppSettings.self) private var settings

    var body: some View {
        // Not a `TabView`: `NSTabView` re-hosts on selection and breaks the recorder.
        Group {
            switch navigation.tab {
            case .general: GeneralSettingsView()
            case .applications: ApplicationsSettingsView()
            case .systemSettings: SystemSettingsSettingsView()
            case .systemActions: SystemActionsSettingsView()
            case .commands: CommandsSettingsView()
            case .quicklinks: QuicklinksSettingsView()
            case .appleShortcuts: AppleShortcutsSettingsView()
            case .fallbacks: FallbacksSettingsView()
            case .ai: AISettingsView()
            case .quickActions: QuickActionsSettingsView()
            case .dictation: DictationSettingsView()
            case .fileSearch: FileSearchSettingsView()
            case .notes: NotesSettingsView()
            case .snippets: SnippetsSettingsView()
            case .navigation: NavigationSettingsView()
            case .windowManagement: WindowManagementSettingsView()
            case .displayTweaks: DisplayTweaksSettingsView()
            case .cleanKeyboard: CleanKeyboardSettingsView()
            case .clipboard: ClipboardSettingsView()
            case .emoji: EmojiSettingsView()
            case .calendar: CalendarSettingsView()
            case .extensions: ExtensionsSettingsView()
            case .permissions: PermissionsSettingsView()
            case .backup: BackupSettingsView()
            case .changelog: ChangelogSettingsView()
            case .about: AboutView()
            case .enteAuth: EnteAuthSettingsView()
            case .duckDuckGoEmail: DuckDuckGoEmailSettingsView()
            case .keepassxc: KeePassXCSettingsView()
            case .textTransformer: TextTransformerSettingsView()
            case .stats: StatsSettingsView()
            case .extendedFeatures: ExtendedFeaturesSettingsView()
            }
        }
        .font(.system(size: settings.settingsRowSubtitleFontSize))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One host for every pane, above their scroll views so a callout is never clipped.
        .shortcutRecorderPopoverHost()
    }
}
