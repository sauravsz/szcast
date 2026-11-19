import Foundation

/// A query that names a row must not be handed on whole to the screen that row opens:
/// `search menu bar items` opens menu search, it does not search for that phrase.
@main
@MainActor
struct LauncherQueryRemainderTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// The row `Search Menu Bar Items` carries its English title as an alternate.
    static let menuBar = ["Search Menu Bar Items", "Search Menu Items"]

    static func main() {
        // The query is nothing but the row's name: the screen opens blank, not filtered.
        expect(
            EntryNaming.queryRemainder("search menu bar items", names: menuBar) == "",
            "a query that is only the row's name leaves an empty seed")
        expect(
            EntryNaming.queryRemainder("Search Menu Bar Items", names: menuBar) == "",
            "stripping is case-insensitive")

        // The reported bug: the whole phrase was being passed on as the search term.
        expect(
            EntryNaming.queryRemainder("search menu bar items safari", names: menuBar) == "safari",
            "text after the row's name is what the screen seeds")
        expect(
            EntryNaming.queryRemainder("search files report", names: ["Search Files"]) == "report",
            "a different command keeps its own trailing text")

        // Partial and over-long words must not be mistaken for the name.
        expect(
            EntryNaming.queryRemainder("search menu bar it", names: menuBar) == nil,
            "a partial word is not the name")
        expect(
            EntryNaming.queryRemainder("search menu", names: menuBar) == nil,
            "a prefix of the name is not the name")
        expect(
            EntryNaming.queryRemainder("search menu bar itemser", names: menuBar) == nil,
            "a longer word is not the name")
        expect(
            EntryNaming.queryRemainder("menu bar items", names: menuBar) == nil,
            "the name must lead the query")

        // Whitespace and ordering.
        expect(
            EntryNaming.queryRemainder("  search   menu bar items   tools  ", names: menuBar)
                == "tools",
            "outer and internal whitespace do not defeat the strip")
        expect(
            EntryNaming.queryRemainder("", names: menuBar) == nil,
            "an empty query consumes nothing")
        expect(
            EntryNaming.queryRemainder("   ", names: menuBar) == nil,
            "a whitespace-only query consumes nothing")

        // The longest name wins, so a shorter alternate cannot eat part of a longer one.
        let overlapping = ["Search Files", "Search"]
        expect(
            EntryNaming.queryRemainder("search files report", names: overlapping) == "report",
            "the longest matching name is stripped")

        // An alias is a name too: it was typed instead of the title.
        expect(
            EntryNaming.queryRemainder("sf report", names: ["Search Files", "sf"]) == "report",
            "a stored alias strips like the title")

        // Nil and empty are distinct: nil means "nothing consumed", so the caller keeps the query.
        expect(
            EntryNaming.queryRemainder("report", names: menuBar) == nil,
            "an unrelated query consumes nothing")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
