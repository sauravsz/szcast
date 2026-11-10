import AppKit
import Carbon.HIToolbox

/// The bindings a fresh install starts with.
///
/// Seeded once, through `HotKeyManager.setBinding`, so they are ordinary stored bindings: a user
/// who clears one keeps it cleared, and `hasSeededDefaults` records that the seed already ran.
///
/// Hyper is ⌃⌥⇧⌘ on this build (`hyperKeyIncludesShift` defaults on), so each default carries all
/// four. Spellings match `KeyShortcut.hyperChord(includesShift: true)`.
enum DefaultHotKeys {
    /// The chord every default shares: Hyper with shift, the built-in setting.
    static var hyperModifiers: NSEvent.ModifierFlags {
        KeyShortcut.hyperChord(includesShift: true)
    }

    static func combo(_ keyCode: Int) -> HotKeyBinding {
        .combo(
            KeyShortcut(
                carbonKeyCode: keyCode,
                carbonModifiers: KeyShortcut.carbonModifiers(from: hyperModifiers)))
    }

    /// Search Snippets, window halves, maximise and reasonable size.
    static var bindings: [(HotKeyAction, HotKeyBinding)] {
        [
            (.command(.searchSnippets), combo(kVK_ANSI_S)),
            (.windowCommand(id: .leftHalf), combo(kVK_ANSI_J)),
            (.windowCommand(id: .rightHalf), combo(kVK_ANSI_L)),
            (.windowCommand(id: .maximize), combo(kVK_ANSI_I)),
            (.windowCommand(id: .reasonableSize), combo(kVK_ANSI_K)),
        ]
    }
}
