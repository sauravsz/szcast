import Foundation

struct PodcastEpisodeResult: Identifiable, Hashable, Sendable {
    var id: String
    var showName: String
    var episodeTitle: String
    var artistName: String
    var episodeURL: URL?
    var feedURL: URL?
    var applePodcastsURL: URL?
    var releaseDate: String
    var durationSeconds: TimeInterval?
}

enum MediaFetchService {
    enum FetchError: LocalizedError {
        case missingHomebrewForInstall(String)
        case toolInstallFailed(String)
        case unsupportedURL
        case toolExecutionFailed(String)
        case podcastResolutionFailed

        var errorDescription: String? {
            switch self {
            case .missingHomebrewForInstall(let tool):
                "Could not find \(tool) or Homebrew to install it automatically."
            case .toolInstallFailed(let reason):
                "Automatic media tool installation failed: \(reason)"
            case .unsupportedURL:
                "Enter a valid http/https media or Apple Podcasts URL."
            case .toolExecutionFailed(let reason):
                "Media download failed: \(reason)"
            case .podcastResolutionFailed:
                "Could not resolve playable audio for this Apple Podcasts link."
            }
        }
    }

    static let supportedExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aac", "flac", "ogg", "opus", "aiff", "caf",
        "mp4", "mov", "mkv", "webm", "m4v", "avi"
    ]

    /// Enumerates local files and recursively expands dropped folders into playable media URLs.
    static func collectMediaFiles(from urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var collected = [URL]()
        var seen = Set<String>()

        func appendIfMedia(_ fileURL: URL) {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { return }
            let resolved = fileURL.standardizedFileURL.path
            if seen.insert(resolved).inserted {
                collected.append(fileURL)
            }
        }

        for url in urls where url.isFileURL {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                appendIfMedia(url)
            } else if let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let child as URL in enumerator {
                    appendIfMedia(child)
                }
            }
        }
        return collected
    }

    /// Ensures `yt-dlp` and `ffmpeg` exist on the system, silently installing via Homebrew if missing.
    static func ensureMediaTools() async throws -> (ytdlp: URL, ffmpeg: URL) {
        var ytdlp = await ExecutableLocator.locate("yt-dlp")
        var ffmpeg = await ExecutableLocator.locate("ffmpeg")

        var missing = [String]()
        if ytdlp == nil { missing.append("yt-dlp") }
        if ffmpeg == nil { missing.append("ffmpeg") }

        if !missing.isEmpty {
            guard let brew = await locateHomebrew() else {
                throw FetchError.missingHomebrewForInstall(missing.joined(separator: ", "))
            }
            try await runBrewInstall(packages: missing, brewURL: brew)
            if ytdlp == nil { ytdlp = await ExecutableLocator.locate("yt-dlp") }
            if ffmpeg == nil { ffmpeg = await ExecutableLocator.locate("ffmpeg") }
        }

        guard let resolvedYtdlp = ytdlp, let resolvedFfmpeg = ffmpeg else {
            throw FetchError.missingHomebrewForInstall("yt-dlp / ffmpeg")
        }
        return (resolvedYtdlp, resolvedFfmpeg)
    }

    private static func locateHomebrew() async -> URL? {
        if let found = await ExecutableLocator.locate("brew") { return found }
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func runBrewInstall(packages: [String], brewURL: URL) async throws {
        let process = Process()
        process.executableURL = brewURL
        process.arguments = ["install", "--quiet"] + packages
        var env = ExecutableLocator.environment(running: brewURL)
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        process.environment = env
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        let handle = try process.runObservingExit()
        await Task.detached(priority: .utility) { handle.wait() }.value
        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "Exit \(process.terminationStatus)"
            throw FetchError.toolInstallFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Searches Apple Podcasts via iTunes Search API using a private ephemeral URLSession.
    static func searchPodcasts(query: String) async throws -> [PodcastEpisodeResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: clean),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcastEpisode"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = comps.url else { return [] }
        let data = try await fetchDataEphemeral(from: url)

        struct LookupEnvelope: Decodable {
            struct Item: Decodable {
                let trackId: Int?
                let collectionId: Int?
                let collectionName: String?
                let trackName: String?
                let artistName: String?
                let episodeUrl: String?
                let feedUrl: String?
                let trackViewUrl: String?
                let releaseDate: String?
                let trackTimeMillis: Int?
            }
            let results: [Item]
        }

        let decoded = try JSONDecoder().decode(LookupEnvelope.self, from: data)
        return decoded.results.compactMap { item in
            let title = item.trackName ?? item.collectionName ?? ""
            guard !title.isEmpty else { return nil }
            let epURL = item.episodeUrl.flatMap(URL.init(string:))
            let feed = item.feedUrl.flatMap(URL.init(string:))
            guard epURL != nil || feed != nil else { return nil }
            let id = String(item.trackId ?? item.collectionId ?? title.hashValue)
            return PodcastEpisodeResult(
                id: id,
                showName: item.collectionName ?? "Podcast",
                episodeTitle: title,
                artistName: item.artistName ?? "",
                episodeURL: epURL,
                feedURL: feed,
                applePodcastsURL: item.trackViewUrl.flatMap(URL.init(string:)),
                releaseDate: String((item.releaseDate ?? "").prefix(10)),
                durationSeconds: item.trackTimeMillis.map { Double($0) / 1000.0 }
            )
        }
    }

    /// Resolves `podcasts.apple.com` URL (with `?i=<episodeID>` or show ID) via iTunes Lookup API & RSS fallback.
    static func resolveApplePodcastsURL(_ url: URL) async throws -> (title: String, audioURL: URL) {
        let ids = extractApplePodcastIDs(from: url)
        guard let showID = ids.showID else { throw FetchError.podcastResolutionFailed }

        var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
        comps.queryItems = [
            URLQueryItem(name: "id", value: showID),
            URLQueryItem(name: "entity", value: "podcastEpisode"),
            URLQueryItem(name: "limit", value: "100")
        ]
        guard let lookupURL = comps.url else { throw FetchError.podcastResolutionFailed }
        let data = try await fetchDataEphemeral(from: lookupURL)

        struct LookupResponse: Decodable {
            struct Entry: Decodable {
                let trackId: Int?
                let trackName: String?
                let collectionName: String?
                let episodeUrl: String?
                let feedUrl: String?
            }
            let results: [Entry]
        }

        let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
        if let episodeID = ids.episodeID,
            let match = decoded.results.first(where: { String($0.trackId ?? -1) == episodeID }),
            let epStr = match.episodeUrl, let audio = URL(string: epStr)
        {
            return (match.trackName ?? match.collectionName ?? "Podcast Episode", audio)
        }
        if let firstEp = decoded.results.first(where: { $0.episodeUrl != nil }),
            let epStr = firstEp.episodeUrl, let audio = URL(string: epStr)
        {
            return (firstEp.trackName ?? firstEp.collectionName ?? "Podcast Episode", audio)
        }
        if let feedStr = decoded.results.compactMap(\.feedUrl).first,
            let feedURL = URL(string: feedStr)
        {
            let rssData = try await fetchDataEphemeral(from: feedURL)
            if let rssAudio = RSSPodcastParser.firstEpisode(in: rssData) {
                return rssAudio
            }
        }
        throw FetchError.podcastResolutionFailed
    }

    static func extractApplePodcastIDs(from url: URL) -> (showID: String?, episodeID: String?) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let episodeID = components?.queryItems?.first(where: { $0.name == "i" })?.value
        var showID: String?
        for segment in url.pathComponents where segment.hasPrefix("id") {
            let digits = String(segment.dropFirst(2))
            if !digits.isEmpty, digits.allSatisfy(\.isNumber) {
                showID = digits
                break
            }
        }
        return (showID, episodeID)
    }

    /// Downloads audio/media from any web URL (`yt-dlp` + `ffmpeg`) or direct Apple Podcasts enclosure.
    static func fetchAudioSamples(
        from url: URL
    ) async throws -> (samples: [Float], title: String, kind: TranscriptRecordKind, sourceURL: String) {
        if url.isFileURL {
            let samples = try await DictationFileTranscriber.extractSamples(from: url)
            return (samples, url.deletingPathExtension().lastPathComponent, .fileImport, url.path)
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw FetchError.unsupportedURL
        }

        let host = url.host?.lowercased() ?? ""
        if host.contains("podcasts.apple.com") {
            let resolved = try await resolveApplePodcastsURL(url)
            let samples = try await downloadAndDecodeDirectAudio(resolved.audioURL)
            return (samples, resolved.title, .podcastImport, url.absoluteString)
        }

        if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "opus"].contains(url.pathExtension.lowercased()) {
            let samples = try await downloadAndDecodeDirectAudio(url)
            return (samples, url.deletingPathExtension().lastPathComponent, .urlImport, url.absoluteString)
        }

        let tools = try await ensureMediaTools()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("szcast-ytdlp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let title = (try? await fetchYtdlpTitle(url: url, ytdlp: tools.ytdlp)) ?? (url.host ?? "Media")
        let outputTemplate = tempDir.appendingPathComponent("audio.%(ext)s").path

        let process = Process()
        process.executableURL = tools.ytdlp
        process.arguments = [
            "--no-playlist",
            "--no-warnings",
            "--ffmpeg-location", tools.ffmpeg.deletingLastPathComponent().path,
            "--extract-audio",
            "--audio-format", "wav",
            "--postprocessor-args", "ffmpeg:-ar 16000 -ac 1",
            "-o", outputTemplate,
            url.absoluteString
        ]
        process.environment = ExecutableLocator.environment(running: tools.ytdlp)
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        let handle = try process.runObservingExit()
        await Task.detached(priority: .utility) { handle.wait() }.value

        let files = (try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        )) ?? []
        guard process.terminationStatus == 0,
            let audioFile = files.first(where: { $0.pathExtension.lowercased() == "wav" }) ?? files.first
        else {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "Exit \(process.terminationStatus)"
            throw FetchError.toolExecutionFailed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let samples = try await DictationFileTranscriber.extractSamples(from: audioFile)
        return (samples, title, .urlImport, url.absoluteString)
    }

    static func downloadAndDecodeDirectAudio(_ url: URL) async throws -> [Float] {
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("szcast-podcast-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let data = try await fetchDataEphemeral(from: url)
        try data.write(to: tempFile, options: .atomic)
        return try await DictationFileTranscriber.extractSamples(from: tempFile)
    }

    private static func fetchYtdlpTitle(url: URL, ytdlp: URL) async throws -> String? {
        let process = Process()
        process.executableURL = ytdlp
        process.arguments = ["--no-playlist", "--no-warnings", "--print", "%(title)s", url.absoluteString]
        process.environment = ExecutableLocator.environment(running: ytdlp)
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        let handle = try process.runObservingExit()
        await Task.detached(priority: .utility) { handle.wait() }.value
        guard process.terminationStatus == 0 else { return nil }
        let raw = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private static func fetchDataEphemeral(from url: URL) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var req = URLRequest(url: url)
        req.setValue("szcast/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private final class RSSPodcastParser: NSObject, XMLParserDelegate {
    private var insideItem = false
    private var currentElement = ""
    private var itemTitle = ""
    private var enclosureURL: URL?

    static func firstEpisode(in data: Data) -> (title: String, audioURL: URL)? {
        let delegate = RSSPodcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let url = delegate.enclosureURL else { return nil }
        let cleanTitle = delegate.itemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanTitle.isEmpty ? "Podcast Episode" : cleanTitle, url)
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        if currentElement == "item" { insideItem = true; itemTitle = "" }
        if insideItem && currentElement == "enclosure",
            let rawURL = attributeDict["url"], let url = URL(string: rawURL)
        {
            enclosureURL = url
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem && currentElement == "title" {
            itemTitle += string
        }
    }
}
