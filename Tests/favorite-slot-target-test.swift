import Foundation

@main
struct FavoriteSlotTargetTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // Pinned favorites head the flat order, so a blank launcher answers from the head.
        check(
            "⌘1 on a blank launcher opens the first row",
            FavoriteSlots.target(slot: 0, rowCount: 8, leadCardOffset: 0) == .row(0))
        check(
            "⌘3 opens the third row",
            FavoriteSlots.target(slot: 2, rowCount: 8, leadCardOffset: 0) == .row(2))

        // A leading card shifts every row by one.
        check(
            "a lead card shifts the target by one",
            FavoriteSlots.target(slot: 0, rowCount: 8, leadCardOffset: 1) == .row(1))
        check(
            "the shift holds further down the list",
            FavoriteSlots.target(slot: 3, rowCount: 8, leadCardOffset: 1) == .row(4))

        // Past the end of the list: swallowed, so the palette does not jump.
        check(
            "a digit past the last row does nothing",
            FavoriteSlots.target(slot: 7, rowCount: 5, leadCardOffset: 0) == .none)
        check(
            "the offset cannot push a digit past the end",
            FavoriteSlots.target(slot: 4, rowCount: 5, leadCardOffset: 1) == .none)
        check(
            "an empty list answers nothing",
            FavoriteSlots.target(slot: 0, rowCount: 0, leadCardOffset: 0) == .none)
        check(
            "a negative slot answers nothing",
            FavoriteSlots.target(slot: -1, rowCount: 8, leadCardOffset: 0) == .none)

        // The last reachable row and the first unreachable one, so the boundary cannot drift.
        check(
            "the final row is reachable",
            FavoriteSlots.target(slot: 4, rowCount: 5, leadCardOffset: 0) == .row(4))
        check(
            "one past the final row is not",
            FavoriteSlots.target(slot: 5, rowCount: 5, leadCardOffset: 0) == .none)

        print(failures == 0 ? "PASSED" : "FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
