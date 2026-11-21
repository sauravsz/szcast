import AppKit

/// Owns emoji delivery: frequency tallies the base glyph, the configured tone applies at copy time.
@MainActor
final class EmojiCoordinator {
    private let frequentEmoji: FrequentEmojiStore
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private weak var core: AppCore?

    init(
        frequentEmoji: FrequentEmojiStore,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore? = nil
    ) {
        self.frequentEmoji = frequentEmoji
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func pasteEmoji(_ entry: EmojiEntry, tone: EmojiSkinTone? = nil, query: String? = nil) {
        recordAndAutoKeyword(entry, query: query)
        let resolvedTone = tone ?? settings.emojiSkinTone
        let text = entry.display(tone: resolvedTone)
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteString(text, previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry, tone: EmojiSkinTone? = nil, query: String? = nil) {
        recordAndAutoKeyword(entry, query: query)
        let resolvedTone = tone ?? settings.emojiSkinTone
        let text = entry.display(tone: resolvedTone)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyString(text)
    }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry, tone: EmojiSkinTone? = nil, query: String? = nil) {
        recordAndAutoKeyword(entry, query: query)
        let resolvedTone = tone ?? settings.emojiSkinTone
        let text = entry.display(tone: resolvedTone)
        windowController.pasteStringKeepingWindowOpen(text)
    }

    func copyUnicode(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        let unicodeScalars = entry.glyph.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyString(unicodeScalars)
    }

    func editCustomKeywords(for entry: EmojiEntry) {
        guard let core else { return }
        Task {
            let existing = CustomEmojiKeywordStore.shared.keywords(for: entry.glyph)
            if let updated = await core.dialogs.editEmojiKeywords(
                glyph: entry.glyph,
                name: entry.name,
                currentKeywords: existing
            ) {
                CustomEmojiKeywordStore.shared.setKeywords(updated, for: entry.glyph)
            }
        }
    }

    private func recordAndAutoKeyword(_ entry: EmojiEntry, query: String?) {
        frequentEmoji.record(entry.glyph)
        if settings.emojiSaveAIKeywords, let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            CustomEmojiKeywordStore.shared.addKeyword(query, for: entry.glyph)
        }
    }
}
