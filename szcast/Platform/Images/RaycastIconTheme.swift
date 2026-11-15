import AppKit
import SwiftUI

/// Raycast-style color themes and symbol-to-palette mapper.
/// Gives every symbol tile a vibrant squircle background and white foreground glyph.
enum RaycastIconTheme {
    // MARK: - Native Raycast Palette

    static let red = NSColor(srgbRed: 0.99, green: 0.35, blue: 0.35, alpha: 1.0)       // #FC5C65 Coral Red
    static let orange = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.20, alpha: 1.0)    // #FF9433 Vibrant Orange
    static let yellow = NSColor(srgbRed: 1.00, green: 0.77, blue: 0.18, alpha: 1.0)    // #FFC42E Gold / Yellow
    static let green = NSColor(srgbRed: 0.16, green: 0.84, blue: 0.44, alpha: 1.0)     // #28D670 Emerald Green
    static let mint = NSColor(srgbRed: 0.06, green: 0.77, blue: 0.65, alpha: 1.0)      // #0FB9A6 Mint
    static let teal = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.82, alpha: 1.0)      // #26BFD1 Teal
    static let sky = NSColor(srgbRed: 0.27, green: 0.67, blue: 0.98, alpha: 1.0)       // #45AAF2 Sky Blue
    static let royal = NSColor(srgbRed: 0.24, green: 0.44, blue: 0.89, alpha: 1.0)     // #3D70E3 Royal Blue
    static let purple = NSColor(srgbRed: 0.65, green: 0.37, blue: 0.92, alpha: 1.0)    // #A55EEA Purple / Violet
    static let magenta = NSColor(srgbRed: 0.93, green: 0.31, blue: 0.62, alpha: 1.0)   // #EC4E9E Magenta
    static let crimson = NSColor(srgbRed: 0.94, green: 0.24, blue: 0.31, alpha: 1.0)   // #F03D4F Crimson
    static let slate = NSColor(srgbRed: 0.38, green: 0.47, blue: 0.58, alpha: 1.0)     // #627894 Slate

    // Pre-allocated SymbolTints
    static let tintRed = SymbolTint(key: "rc-red", color: red)
    static let tintOrange = SymbolTint(key: "rc-orange", color: orange)
    static let tintYellow = SymbolTint(key: "rc-yellow", color: yellow)
    static let tintGreen = SymbolTint(key: "rc-green", color: green)
    static let tintMint = SymbolTint(key: "rc-mint", color: mint)
    static let tintTeal = SymbolTint(key: "rc-teal", color: teal)
    static let tintSky = SymbolTint(key: "rc-sky", color: sky)
    static let tintRoyal = SymbolTint(key: "rc-royal", color: royal)
    static let tintPurple = SymbolTint(key: "rc-purple", color: purple)
    static let tintMagenta = SymbolTint(key: "rc-magenta", color: magenta)
    static let tintCrimson = SymbolTint(key: "rc-crimson", color: crimson)
    static let tintSlate = SymbolTint(key: "rc-slate", color: slate)

    private static let fallbackTints: [SymbolTint] = [
        tintRed, tintOrange, tintYellow, tintGreen,
        tintSky, tintRoyal, tintPurple, tintTeal,
        tintCrimson, tintMagenta, tintMint, tintSlate
    ]

    // MARK: - Symbol Tint Resolution

    static func tint(forSymbol name: String) -> SymbolTint {
        let clean = name.lowercased()

        // Snippets / Quotes
        if clean.contains("curlybraces") || clean.contains("quote") || clean == "text.quote" {
            return tintRed
        }

        // Web / Quicklinks / Mail
        if clean.contains("link") || clean.contains("globe") || clean.contains("safari")
            || clean.contains("network") || clean.contains("envelope") || clean.contains("tray")
            || clean.contains("arrow.up.right") {
            return tintOrange
        }

        // Notes / Drafts / Emoji / Favorites
        if clean.contains("note") || clean.contains("pencil") || clean.contains("highlighter")
            || clean.contains("smiling") || clean.contains("star") {
            return tintYellow
        }

        // Calculator / Math / Finance / Numbers
        if clean.contains("equal") || clean.contains("plusminus") || clean.contains("number")
            || clean.contains("function") || clean.contains("divide") || clean.contains("multiply")
            || clean.contains("dollar") || clean.contains("percent") || clean.contains("chart") {
            return tintGreen
        }

        // Security / Keys / Passwords / Ente / KeePassXC
        if clean.contains("key") || clean.contains("lock") || clean.contains("shield") {
            return tintGreen
        }

        // Clipboard / Copy / Files / Finder
        if clean.contains("clipboard") || clean.contains("folder") || clean.contains("magnifyingglass")
            || clean.contains("doc.on") || clean.contains("externaldrive") || clean == "doc" {
            return tintSky
        }

        // Window Management / Rectangles / Layouts
        if clean.contains("macwindow") || clean.contains("rectangle") || clean.contains("square.split")
            || clean.contains("split.2x") || clean.contains("sidebar") {
            return tintRoyal
        }

        // AI / LLMs / Sparkles / Extensions
        if clean.contains("sparkle") || clean.contains("bubble") || clean.contains("wand")
            || clean.contains("puzzlepiece") || clean.contains("brain") || clean.contains("cpu") {
            return tintPurple
        }

        // Calendar / Clock / Meetings / Dictation / Voice
        if clean.contains("calendar") || clean.contains("clock") || clean.contains("timer")
            || clean.contains("hourglass") || clean.contains("video") || clean.contains("mic") {
            return tintCrimson
        }

        // Clean Keyboard / Peripherals / Devices
        if clean.contains("keyboard") || clean.contains("headphone") || clean.contains("speaker") {
            return tintTeal
        }

        // Display Tweaks / Brightness / Displays
        if clean.contains("sun.") || clean.contains("slider.horizontal") || clean == "display" {
            return tintOrange
        }

        // System Settings / Terminal / Utilities
        if clean.contains("gear") || clean.contains("terminal") || clean.contains("wrench")
            || clean.contains("hammer") || clean.contains("slider.vertical") {
            return tintSlate
        }

        // Deterministic fallback based on symbol name hash
        let hash = abs(clean.hashValue)
        return fallbackTints[hash % fallbackTints.count]
    }

    // MARK: - Color Wrappers for SwiftUI

    static func color(forSymbol name: String) -> Color {
        Color(nsColor: tint(forSymbol: name).color)
    }

    static func tabColor(for tabName: String) -> Color {
        Color(nsColor: tint(forSymbol: tabName).color)
    }
}
