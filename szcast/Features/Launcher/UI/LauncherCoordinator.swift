import AppKit

/// Owns launcher activation: the one funnel from a palette row to whatever the entry's kind runs.
@MainActor
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let customCommandCoordinator: CustomCommandCoordinator
    private let systemActionCoordinator: SystemActionCoordinator
    private let quicklinkCoordinator: QuicklinkCoordinator
    private let windowCommandCoordinator: WindowCommandCoordinator
    private let windowLayoutCoordinator: WindowLayoutCoordinator
    private let snippetCoordinator: SnippetCoordinator
    private let fileSearchCoordinator: FileSearchCoordinator
    private let menuSearchCoordinator: MenuSearchCoordinator
    private let windowSwitchCoordinator: WindowSwitchCoordinator
    private let notesCoordinator: NotesCoordinator
    private let extensionCoordinator: ExtensionCoordinator
    private let calendarCoordinator: CalendarCoordinator
    /// The backup commands only, which need the live stores to gather from and apply to.
    private unowned let core: AppCore

    init(
        ranking: LauncherRankingStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        customCommandCoordinator: CustomCommandCoordinator,
        systemActionCoordinator: SystemActionCoordinator,
        quicklinkCoordinator: QuicklinkCoordinator,
        windowCommandCoordinator: WindowCommandCoordinator,
        windowLayoutCoordinator: WindowLayoutCoordinator,
        snippetCoordinator: SnippetCoordinator,
        fileSearchCoordinator: FileSearchCoordinator,
        menuSearchCoordinator: MenuSearchCoordinator,
        windowSwitchCoordinator: WindowSwitchCoordinator,
        notesCoordinator: NotesCoordinator,
        extensionCoordinator: ExtensionCoordinator,
        calendarCoordinator: CalendarCoordinator,
        core: AppCore
    ) {
        self.ranking = ranking
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.customCommandCoordinator = customCommandCoordinator
        self.systemActionCoordinator = systemActionCoordinator
        self.quicklinkCoordinator = quicklinkCoordinator
        self.windowCommandCoordinator = windowCommandCoordinator
        self.windowLayoutCoordinator = windowLayoutCoordinator
        self.snippetCoordinator = snippetCoordinator
        self.fileSearchCoordinator = fileSearchCoordinator
        self.menuSearchCoordinator = menuSearchCoordinator
        self.windowSwitchCoordinator = windowSwitchCoordinator
        self.notesCoordinator = notesCoordinator
        self.extensionCoordinator = extensionCoordinator
        self.calendarCoordinator = calendarCoordinator
        self.core = core
    }

    // MARK: - Activation

    func launch(
        _ app: AppEntry, searchQuery: String? = nil, arguments: [String: String] = [:]
    ) {
        // A category word is no search for the row: learning it would rank the row under "s".
        if !CommandCatalog.isQueryDriven(app) {
            let term = searchQuery.flatMap {
                AppEntry.Kind.matching(by: LauncherOrder.CategoryQuery($0)).contains(app.kind) ? nil : $0
            }
            ranking.visit(itemKey: app.preferenceKey, query: term)
        }
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        // A command that opens a screen seeds it with what is left after its own name, so
        // `search files report` opens file search holding `report`, not the whole phrase.
        if app.kind == .command {
            guard let id = CommandCatalog.command(for: app) else { return }
            // Query-driven: only this row knows the URL the typed text resolved to.
            if id == .openInBrowser {
                paletteCoordinator.hidePalette(restoreFocus: false)
                AppLauncher.open(app.url)
                return
            }
            runCommand(id, searchQuery: remainder(of: searchQuery, for: app))
            return
        }
        if app.kind == .quickAction {
            if let command = CommandCatalog.command(for: app) {
                runCommand(command, searchQuery: remainder(of: searchQuery, for: app))
                return
            }
            guard let id = CustomQuickAction.id(fromEntryID: app.id) else { return }
            core.quickActionCoordinator.run(id: id)
            return
        }
        if app.kind == .customCommand {
            guard let id = CustomCommand.id(fromEntryID: app.id) else { return }
            customCommandCoordinator.runCustomCommand(id: id, values: arguments)
            return
        }
        if app.kind == .systemAction {
            guard let action = SystemActionCatalog.action(forEntryID: app.id) else { return }
            systemActionCoordinator.runSystemAction(id: action.id)
            return
        }
        if app.kind == .windowCommand {
            if let command = WindowCommandCatalog.command(forEntryID: app.id) {
                windowCommandCoordinator.runWindowCommand(id: command.id)
                return
            }
            guard let id = CustomWindowSize.id(fromEntryID: app.id) else { return }
            windowCommandCoordinator.runCustomWindowSize(id: id)
            return
        }
        if app.kind == .windowRoom {
            // The coordinator hides the palette itself: entering must not restore focus first.
            guard let id = Room.id(fromEntryID: app.id) else { return }
            core.roomCoordinator.enterRoom(id: id)
            return
        }
        if app.kind == .windowLayout {
            // The coordinator hides the palette itself: a layout must not restore focus first.
            guard let id = WindowLayout.id(fromEntryID: app.id) else { return }
            windowLayoutCoordinator.runWindowLayout(id: id)
            return
        }
        // Before the palette hides: a view command takes the palette over rather than closing it.
        if app.kind == .extensionCommand {
            extensionCoordinator.runExtensionCommand(app, arguments: arguments)
            return
        }
        if app.kind == .meeting {
            guard let id = MeetingEvent.id(fromEntryID: app.id) else { return }
            calendarCoordinator.activateMeeting(id: id)
            return
        }
        // Before the palette hides: an unfilled quicklink stays up to ask first.
        if app.kind == .quicklink {
            guard let id = Quicklink.id(fromEntryID: app.id) else { return }
            quicklinkCoordinator.openQuicklink(id: id, values: arguments)
            return
        }
        if app.kind == .appleShortcut {
            guard let id = AppleShortcut.id(fromEntryID: app.id) else { return }
            core.appleShortcutCoordinator.run(id: id)
            return
        }
        let previous = windowController.previousTarget
        paletteCoordinator.hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url, allowsRunningApplicationSubstitution: false)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .snippet:
            guard let snippetID = StoredSnippet.id(fromEntryID: app.id) else { return }
            snippetCoordinator.expandSnippet(id: snippetID, target: previous)
        case .command, .quickAction, .customCommand, .systemAction, .windowCommand, .windowLayout,
            .windowRoom, .quicklink, .appleShortcut, .extensionCommand, .meeting:
            break  // handled above
        }
    }

    /// The one funnel a built-in command runs through, from a palette row or its global shortcut.
    func runCommand(_ id: CommandID, searchQuery: String? = nil) {
        switch id {
        case .quickAI:
            if let searchQuery, !searchQuery.isEmpty {
                core.quickAICoordinator.show(draft: searchQuery)
            } else {
                core.quickAICoordinator.show()
            }
        case .aiChat:
            dismissPalette()
            core.aiChatCoordinator.toggleWindow()
        case .fixGrammar:
            core.quickActionCoordinator.run(.fixGrammar)
        case .rewrite:
            core.quickActionCoordinator.run(.rewrite)
        case .makeShorter:
            core.quickActionCoordinator.run(.makeShorter)
        case .makeLonger:
            core.quickActionCoordinator.run(.makeLonger)
        case .simplify:
            core.quickActionCoordinator.run(.simplify)
        case .changeTone:
            core.quickActionCoordinator.run(.changeTone)
        case .toneProfessional:
            core.quickActionCoordinator.run(.toneProfessional)
        case .toneCasual:
            core.quickActionCoordinator.run(.toneCasual)
        case .toneDirect:
            core.quickActionCoordinator.run(.toneDirect)
        case .toneAcademic:
            core.quickActionCoordinator.run(.toneAcademic)
        case .toneDiplomatic:
            core.quickActionCoordinator.run(.toneDiplomatic)
        case .translate:
            core.quickActionCoordinator.run(.translate)
        case .summarize:
            core.quickActionCoordinator.run(.summarize)
        case .explain:
            core.quickActionCoordinator.run(.explain)
        case .findActionItems:
            core.quickActionCoordinator.run(.findActionItems)
        case .convertTypeScript:
            core.quickActionCoordinator.run(.convertTypeScript)
        case .slackReply:
            core.quickActionCoordinator.run(.slackReply)
        case .emailReply:
            core.quickActionCoordinator.run(.emailReply)
        case .summarizeYouTube:
            core.quickActionCoordinator.run(.summarizeYouTube)
        case .calculatorHistory:
            paletteCoordinator.togglePalette(mode: .calculatorHistory, seeding: searchQuery)
        case .clipboardHistory:
            paletteCoordinator.togglePalette(mode: .clipboard, seeding: searchQuery)
        case .pasteSequentially:
            core.clipboardCoordinator.pasteNextInSequence()
        case .searchEmoji:
            paletteCoordinator.togglePalette(mode: .emoji, seeding: searchQuery)
        case .searchFiles:
            fileSearchCoordinator.show(query: searchQuery ?? "")
        case .searchMenuItems:
            menuSearchCoordinator.show(query: searchQuery ?? "")
        case .switchWindows:
            if let searchQuery, !searchQuery.isEmpty {
                windowSwitchCoordinator.show(query: searchQuery)
            } else {
                windowSwitchCoordinator.show()
            }
        case .switchWindowsBackwards:
            windowSwitchCoordinator.show(backwards: true)
        case .openCamera:
            dismissPalette()
            Task { await core.cameraCoordinator.show() }
        case .define:
            core.dictionaryCoordinator.show(term: searchQuery ?? "")
        case .openInBrowser, .runShellCommand:
            break  // Query-driven: each runs where the typed text is, never through this funnel.
        case .joinNextMeeting:
            guard core.settings.calendarEnabled else { return }
            calendarCoordinator.joinNextMeeting()
        case .copyMeetingLink:
            guard core.settings.calendarEnabled else { return }
            calendarCoordinator.copyNextMeetingLink()
        case .mySchedule:
            guard core.settings.calendarEnabled else { return }
            calendarCoordinator.showSchedule()
        case .openInCalendar:
            guard core.settings.calendarEnabled else { return }
            calendarCoordinator.openNextMeetingInCalendar()
        case .createEvent:
            guard core.settings.calendarEnabled else { return }
            calendarCoordinator.createEvent()
        case .showNotes:
            dismissPalette()
            notesCoordinator.toggle()
        case .createNote:
            dismissPalette()
            notesCoordinator.createNote()
        case .searchNotes:
            dismissPalette()
            notesCoordinator.searchNotes()
        case .searchQuicklinks:
            paletteCoordinator.togglePalette(mode: .quicklinks, seeding: searchQuery)
        case .searchSnippets:
            snippetCoordinator.showSnippets(query: searchQuery ?? "")
        case .createSnippet:
            snippetCoordinator.createSnippetFromSelection()
        case .createWindowLayout:
            dismissPalette()
            windowLayoutCoordinator.editWindowLayout(nil)
        case .captureWindowLayout:
            dismissPalette()
            windowLayoutCoordinator.captureWindowLayout()
        case .switchRoom:
            core.roomCoordinator.showRooms()
        case .createRoom:
            core.roomCoordinator.createRoom()
        case .createQuicklink:
            quicklinkCoordinator.editQuicklink(nil)
        case .createCustomCommand:
            customCommandCoordinator.editCustomCommand(nil)
        case .searchCustomCommands:
            customCommandCoordinator.showCustomCommands(query: searchQuery ?? "")
        case .importQuicklinks:
            dismissPalette()
            Task { await quicklinkCoordinator.importQuicklinks() }
        case .exportQuicklinks:
            dismissPalette()
            Task { await quicklinkCoordinator.exportQuicklinks() }
        case .exportSettings:
            dismissPalette()
            Task { await BackupActions.runExportCommand(core: core) }
        case .importSettings:
            dismissPalette()
            Task { await BackupActions.runImportCommand(core: core) }
        case .importFromRaycast:
            dismissPalette()
            settingsCoordinator.showBackupSettings()
        case .checkForUpdates:
            dismissPalette()
            core.updateCoordinator.checkForUpdates()
        case .settings:
            dismissPalette()
            settingsCoordinator.showSettings()
        case .about:
            dismissPalette()
            settingsCoordinator.showAbout()
        case .changelog:
            dismissPalette()
            settingsCoordinator.showChangelog()
        case .support:
            dismissPalette()
            core.supportCoordinator.showSupport()
        case .focusTimer:
            paletteCoordinator.togglePalette(mode: .focusTimer, seeding: searchQuery)
        case .enteAuth:
            guard core.settings.enteAuthEnabled else { return }
            paletteCoordinator.togglePalette(mode: .enteAuth, seeding: searchQuery)
        case .captureScreenText:
            dismissPalette()
            ScreenCaptureService.shared.capture(mode: .textOCR, showMessage: { [weak core] msg in
                core?.showMessage(msg)
            })
        case .askAIAboutScreenArea:
            guard core.settings.aiEnabled else { return }
            dismissPalette()
            ScreenCaptureService.shared.capture(mode: .textOCR, showMessage: nil) { [weak core] result in
                guard let text = result?.rawText.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    core?.showMessage(String(localized: "No text recognized in selected screen area"), tone: .danger)
                    return
                }
                core?.quickAICoordinator.show(draft: text)
            }
        case .scanQRCode:
            dismissPalette()
            ScreenCaptureService.shared.capture(mode: .qrCode, showMessage: { [weak core] msg in
                core?.showMessage(msg)
            })
        case .cleanClipboardURL:
            dismissPalette()
            Task {
                do {
                    if let feedback = try await SystemActionRunner.run(.cleanClipboardURL, previousApp: nil) {
                        core.showMessage(feedback.title)
                    }
                } catch {
                    core.showMessage(error.localizedDescription)
                }
            }
        case .generateDuckAddress:
            guard core.settings.duckDuckGoEmailEnabled else { return }
            if core.duckDuckGoEmailService.hasToken {
                dismissPalette()
                Task {
                    let result = await core.duckDuckGoEmailService.generateAndCopy()
                    core.showMessage(result.message, tone: result.success ? .success : .danger)
                }
            } else {
                paletteCoordinator.togglePalette(mode: .duckDuckGoEmail)
            }
        case .cleanKeyboard:
            guard core.settings.cleanKeyboardEnabled else { return }
            dismissPalette()
            core.cleanKeyboardService.startCleaning(duration: 60)
        case .keepassxc:
            guard core.settings.keepassxcEnabled else { return }
            paletteCoordinator.togglePalette(mode: .keepassxc, seeding: searchQuery)
        case .textTransformer:
            guard core.settings.textTransformerEnabled else { return }
            paletteCoordinator.togglePalette(mode: .textTransformer, seeding: searchQuery)
        case .systemStats:
            guard core.settings.statsEnabled else { return }
            paletteCoordinator.togglePalette(mode: .systemStats)
        case .dictationInsights:
            dismissPalette()
            core.settingsCoordinator.showSettings(tab: .dictation)
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// A shortcut runs these with nothing open, where a plain hide would still reset palette state.
    private func dismissPalette() {
        guard paletteCoordinator.isVisible else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    // MARK: - Row actions

    /// The typed text minus the row's own name, which is what a screen it opens may seed.
    private func remainder(of query: String?, for entry: AppEntry) -> String? {
        guard let query else { return nil }
        let alias = core.aliases.alias(for: entry.preferenceKey)
        return EntryNaming.queryRemainder(
            query, names: [entry.name] + entry.alternateTitles + [alias].compactMap { $0 })
    }

    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    func showInFinder(_ app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func showInfo(_ app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await AppLauncher.showInfoInFinder(app.url) }
    }

    func openWith(_ app: AppEntry) {
        openWithURL(app.url)
    }

    func openWithURL(_ url: URL) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open With…")
        panel.prompt = String(localized: "Open")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let appURL = panel.url {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func argumentValues(for entry: AppEntry) -> [String: String] {
        let palette = core.palette
        switch entry.kind {
        case .quicklink:
            guard let quicklink = Quicklink.id(fromEntryID: entry.id).flatMap(core.quicklinks.quicklink)
            else { return [:] }
            return QuicklinkArgumentsAccessory.values(for: quicklink, vm: palette)
        case .customCommand:
            guard let command = core.customCommands.command(entryID: entry.id) else { return [:] }
            return CustomCommandArgumentsAccessory.values(for: command, vm: palette)
        default:
            var values: [String: String] = [:]
            for argument in extensionCoordinator.commandArguments(for: entry) ?? [] {
                let typed = palette.commandArguments[PaletteState.argumentKey(entry.id, argument.name)]
                if let typed, !typed.isEmpty { values[argument.name] = typed }
            }
            return values
        }
    }

    func deepLink(for app: AppEntry) -> URL? {
        let values = argumentValues(for: app)
        guard app.kind != .extensionCommand else {
            return extensionCoordinator.deepLink(forEntryID: app.id, arguments: values)
        }
        return core.deepLinkCoordinator.url(forEntryID: app.id, values: values)
    }

    func deepLink(for action: HotKeyAction) -> URL? {
        if case .extensionCommand(let entryID) = action {
            return extensionCoordinator.deepLink(forEntryID: entryID, arguments: [:])
        }
        return action.entryID.flatMap { core.deepLinkCoordinator.url(forEntryID: $0) }
    }

    func copyDeepLink(_ url: URL) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.deepLinkCoordinator.copy(url)
    }

    /// Focus is never handed back: the relaunch takes it, or the app that refused has it.
    func restart(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await AppLauncher.restart(bundleID: bundleID, url: app.url) }
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func quit(_ app: AppEntry, force: Bool = false) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // Nothing here takes focus, so hand it back unless that app is on its way out.
        let quittingPreviousApp =
            windowController.previousApp?.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
            == app.id
        guard AppLauncher.quit(bundleID: bundleID, url: app.url, force: force) else { return }
        paletteCoordinator.hidePalette(restoreFocus: !quittingPreviousApp)
    }

    func configure(app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        if app.kind == .extensionCommand {
            core.extensionCoordinator.showExtensionSettings(for: app)
            return
        }
        if let owner = app.settingsOwner {
            core.settingsCoordinator.showSettings(tab: owner)
            return
        }
        switch app.kind {
        case .systemSettings:
            core.settingsCoordinator.showSettings(tab: .systemSettings)
        case .application:
            core.settingsCoordinator.showSettings(tab: .general)
        case .command, .systemAction, .windowCommand, .quickAction, .customCommand:
            core.settingsCoordinator.showSettings(tab: .commands)
        case .quicklink:
            core.settingsCoordinator.showSettings(tab: .quicklinks)
        case .snippet:
            core.settingsCoordinator.showSettings(tab: .snippets)
        case .appleShortcut:
            core.settingsCoordinator.showSettings(tab: .appleShortcuts)
        case .meeting:
            core.settingsCoordinator.showSettings(tab: .calendar)
        default:
            core.settingsCoordinator.showSettings(tab: .general)
        }
    }

    func beginSetAlias(for app: AppEntry) {
        Task { @MainActor in
            let current = core.aliases.alias(for: app.preferenceKey)
            let result = await core.promptAlias(entry: app, currentAlias: current)
            guard result.saved, let newAlias = result.alias else { return }
            let trimmed = newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            core.aliases.setAlias(trimmed, for: app.preferenceKey)
            if trimmed.isEmpty {
                core.showMessage(String(localized: "Alias removed for \(app.name)"), tone: .neutral)
            } else {
                core.showMessage(String(localized: "Alias “\(trimmed)” set for \(app.name)"), tone: .success)
            }
        }
    }

    func beginRecordHotKey(for app: AppEntry) {
        guard let action = app.hotKeyAction else { return }
        Task { @MainActor in
            let initial = core.hotKeys.binding(for: action)
            await core.recordHotKey(entry: app, action: action)
            let now = core.hotKeys.binding(for: action)
            if now != initial {
                if let now {
                    let text = now.keycaps.joined(separator: " ")
                    core.showMessage(String(localized: "Hotkey \(text) set for \(app.name)"), tone: .success)
                } else {
                    core.showMessage(String(localized: "Hotkey removed for \(app.name)"), tone: .neutral)
                }
            }
        }
    }
}
