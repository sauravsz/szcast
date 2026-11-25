import Foundation

@main
struct MediaIngestTest {
    static func main() async throws {
        // 1. Test recursive folder media collection.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("szcast-media-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("sub/deep")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let m4a = root.appendingPathComponent("episode.m4a")
        let mp4 = nested.appendingPathComponent("meeting.MP4")
        let txt = nested.appendingPathComponent("readme.txt")
        try Data([1]).write(to: m4a)
        try Data([2]).write(to: mp4)
        try Data([3]).write(to: txt)

        let discovered = MediaFetchService.collectMediaFiles(from: [root, m4a])
        let paths = discovered.map(\.lastPathComponent).sorted()
        guard paths == ["episode.m4a", "meeting.MP4"] else {
            fatalError("Media file collector unexpected output: \(paths)")
        }

        // 2. Test Apple Podcasts URL ID parser (show + episode vs show-only).
        let epURL = URL(string: "https://podcasts.apple.com/us/podcast/lex-fridman-podcast/id1434243584?i=1000678901234")!
        let parsedEp = MediaFetchService.extractApplePodcastIDs(from: epURL)
        guard parsedEp.showID == "1434243584", parsedEp.episodeID == "1000678901234" else {
            fatalError("Apple Podcasts episode URL parse failed: \(parsedEp)")
        }

        let showURL = URL(string: "https://podcasts.apple.com/us/podcast/atp/id617416468")!
        let parsedShow = MediaFetchService.extractApplePodcastIDs(from: showURL)
        guard parsedShow.showID == "617416468", parsedShow.episodeID == nil else {
            fatalError("Apple Podcasts show URL parse failed: \(parsedShow)")
        }

        // 3. Test yt-dlp & ffmpeg auto-check / install availability.
        let tools = try await MediaFetchService.ensureMediaTools()
        guard FileManager.default.isExecutableFile(atPath: tools.ytdlp.path),
            FileManager.default.isExecutableFile(atPath: tools.ffmpeg.path)
        else {
            fatalError("Media tools check failed")
        }

        print("MediaIngest folder scan, Apple Podcasts URL parser & yt-dlp/ffmpeg check passed")
    }
}
