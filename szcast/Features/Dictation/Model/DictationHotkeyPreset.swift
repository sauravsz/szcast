import AppKit
import Carbon.HIToolbox
import Foundation

enum DictationHotkeyPreset: String, CaseIterable, Identifiable, Sendable {
    case fn = "fn"
    case optionSpace = "option_space"
    case controlSpace = "control_space"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fn:
            return String(localized: "Fn (Globe) Key")
        case .optionSpace:
            return String(localized: "Option + Space (⌥Space)")
        case .controlSpace:
            return String(localized: "Control + Space (⌃Space)")
        case .custom:
            return String(localized: "Record custom hotkey…")
        }
    }

    var shortTitle: String {
        switch self {
        case .fn:
            return String(localized: "Fn key")
        case .optionSpace:
            return "⌥Space"
        case .controlSpace:
            return "⌃Space"
        case .custom:
            return String(localized: "Custom")
        }
    }

    var summary: String {
        switch self {
        case .fn:
            return String(localized: "Hold or press the Fn / Globe key")
        case .optionSpace:
            return String(localized: "Press ⌥ and Space together")
        case .controlSpace:
            return String(localized: "Press ⌃ and Space together")
        case .custom:
            return String(localized: "Record any custom shortcut or modifier")
        }
    }

    static let optionSpaceBinding = HotKeyBinding.combo(
        KeyShortcut(carbonKeyCode: kVK_Space, carbonModifiers: optionKey)
    )

    static let controlSpaceBinding = HotKeyBinding.combo(
        KeyShortcut(carbonKeyCode: kVK_Space, carbonModifiers: controlKey)
    )

    var binding: HotKeyBinding? {
        switch self {
        case .fn:
            return .globe
        case .optionSpace:
            return Self.optionSpaceBinding
        case .controlSpace:
            return Self.controlSpaceBinding
        case .custom:
            return nil
        }
    }

    static func preset(for binding: HotKeyBinding?) -> DictationHotkeyPreset {
        guard let binding else { return .custom }
        if binding == .globe {
            return .fn
        } else if binding == optionSpaceBinding {
            return .optionSpace
        } else if binding == controlSpaceBinding {
            return .controlSpace
        } else {
            return .custom
        }
    }
}
