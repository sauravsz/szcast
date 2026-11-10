import Foundation

/// ⌘1…⌘9 then ⌘0 for the tenth; favorites past it are listed but carry no chord.
enum FavoriteSlots {
    static let digits: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    /// ANSI number-row key codes in visual order 1…9,0. This is layout-independent.
    private static let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]

    /// The favorite a digit launches, or nil when that key is not a slot.
    static func index(for digit: Character) -> Int? { digits.firstIndex(of: digit) }

    /// The favorite a physical number-row key launches, or nil when that key is not a slot.
    static func index(forKeyCode keyCode: UInt16) -> Int? {
        numberRowKeyCodes.firstIndex(of: keyCode)
    }

    static func digit(at index: Int) -> Character? {
        digits.indices.contains(index) ? digits[index] : nil
    }

    /// Where a ⌘-digit lands: the Nth row of the flat activation order, favorites included.
    /// Pinned favorites head that order, so one rule answers the blank and typed cases alike.
    enum Target: Equatable {
        /// A row index in the launcher's `rows`.
        case row(Int)
        /// Nothing at that position, so the digit is swallowed and the palette stays put.
        case none
    }

    /// - Parameters:
    ///   - slot: zero-based slot, so ⌘1 is 0.
    ///   - rowCount: how many rows the flat activation order holds.
    ///   - leadCardOffset: 1 when a calc/color/meeting card leads, 0 otherwise.
    static func target(slot: Int, rowCount: Int, leadCardOffset: Int) -> Target {
        guard slot >= 0 else { return .none }
        let row = slot + leadCardOffset
        return row < rowCount ? .row(row) : .none
    }
}
