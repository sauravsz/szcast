import Foundation

@main
enum SzcastCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            printUsage()
            exit(0)
        }

        do {
            switch args[0] {
            case "-h", "--help", "help":
                printUsage()
            case "-v", "--version", "version":
                print("szcast-cli 1.0")
            case "transcribe":
                try await runTranscribe(Array(args.dropFirst()))
            case "podcast":
                try await runPodcast(Array(args.dropFirst()))
            case "models":
                try await runModels(Array(args.dropFirst()))
            case "history":
                try await runHistory(Array(args.dropFirst()))
            case "export":
                try await runExport(Array(args.dropFirst()))
            default:
                // Shorthand: `szcast-cli <file-or-url> ...`
                try await runTranscribe(args)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func runTranscribe(_ args: [String]) async throws {
        var target: String?
        var model = DictationModel.redux
        var format = TranscriptExportFormat.txt
        var outputURL: URL?
        var speakerCount: Int?
        var useVAD = true
        var language: String?
        var saveToHistory = false

        var idx = 0
        while idx < args.count {
            let arg = args[idx]
            switch arg {
            case "--model", "-m":
                idx += 1
                guard idx < args.count, let parsed = DictationModel(rawValue: args[idx]) else {
                    throw NSError(domain: "szcast-cli", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Unknown model. Available: \(DictationModel.allCases.map(\.rawValue).joined(separator: ", "))"
                    ])
                }
                model = parsed
            case "--format", "-f":
                idx += 1
                guard idx < args.count, let parsed = TranscriptExportFormat(rawValue: args[idx].lowercased()) else {
                    throw NSError(domain: "szcast-cli", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Unknown format. Available: txt, md, srt, vtt, json, dapt, pdf, docx"
                    ])
                }
                format = parsed
            case "--output", "-o":
                idx += 1
                guard idx < args.count else { break }
                outputURL = URL(fileURLWithPath: args[idx])
            case "--speakers", "-s":
                idx += 1
                guard idx < args.count else { break }
                let val = args[idx].lowercased()
                speakerCount = val == "auto" ? 0 : (Int(val) ?? 0)
            case "--no-vad":
                useVAD = false
            case "--lang", "-l":
                idx += 1
                if idx < args.count { language = args[idx] }
            case "--save":
                saveToHistory = true
            default:
                if !arg.hasPrefix("-") && target == nil { target = arg }
            }
            idx += 1
        }

        guard let target else {
            throw NSError(domain: "szcast-cli", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Missing file path or media URL."
            ])
        }

        guard let modelDir = try await resolveOrDownload(model: model) else {
            throw NSError(domain: "szcast-cli", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not locate or download model \(model.rawValue)."
            ])
        }
        let vadDir = useVAD ? try? await resolveOrDownload(support: .sileroVAD) : nil
        let diarDir = speakerCount != nil ? try? await resolveOrDownload(support: .speakerDiarization) : nil

        let fetched: (samples: [Float], title: String, kind: TranscriptRecordKind, sourceURL: String)
        if let webURL = URL(string: target), let scheme = webURL.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            fetched = try await MediaFetchService.fetchAudioSamples(from: webURL)
        } else {
            let fileURL = URL(fileURLWithPath: target)
            let samples = try await DictationFileTranscriber.extractSamples(from: fileURL)
            fetched = (samples, fileURL.deletingPathExtension().lastPathComponent, .fileImport, fileURL.path)
        }

        let session = DictationInferenceSession()
        let ranges = fetched.samples.count <= DictationWire.maximumSamples
            ? [0..<fetched.samples.count]
            : DictationAudioChunks.ranges(in: fetched.samples, maximum: DictationWire.maximumSamples)

        var words = [TranscriptWord]()
        var segments = [TranscriptSegment]()
        var texts = [String]()

        for range in ranges {
            let chunk = Array(fetched.samples[range])
            let req = DictationWire.Request(
                id: UUID(),
                model: model,
                directory: modelDir,
                sampleCount: chunk.count,
                language: language,
                useVAD: useVAD,
                vadDirectory: vadDir,
                diarizeSpeakers: speakerCount,
                diarizationDirectory: diarDir
            )
            let part = try session.transcribe(samples: chunk, request: req)
            let offset = Double(range.lowerBound) / Double(DictationWire.sampleRate)
            if !part.text.isEmpty { texts.append(part.text) }
            words += part.words.map {
                TranscriptWord(text: $0.text, start: $0.start + offset, end: $0.end + offset, confidence: $0.confidence)
            }
            segments += part.segments.map { seg in
                TranscriptSegment(
                    id: seg.id,
                    speaker: seg.speaker,
                    text: seg.text,
                    start: seg.start + offset,
                    end: seg.end + offset,
                    words: seg.words.map {
                        TranscriptWord(text: $0.text, start: $0.start + offset, end: $0.end + offset, confidence: $0.confidence)
                    }
                )
            }
        }

        let record = TranscriptRecord(
            kind: fetched.kind,
            title: fetched.title,
            createdAt: Date(),
            duration: Double(fetched.samples.count) / Double(DictationWire.sampleRate),
            text: texts.joined(separator: " "),
            segments: segments,
            sourceURL: fetched.sourceURL,
            modelID: model.rawValue
        )

        if saveToHistory {
            await MainActor.run {
                let store = sharedTranscriptStore()
                store.upsert(record)
            }
        }

        try emit(record: record, format: format, outputURL: outputURL)
    }

    private static func runPodcast(_ args: [String]) async throws {
        guard let sub = args.first else {
            throw NSError(domain: "szcast-cli", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Usage: szcast-cli podcast search <query>"
            ])
        }
        switch sub {
        case "search":
            let query = args.dropFirst().joined(separator: " ")
            let results = try await MediaFetchService.searchPodcasts(query: query)
            for item in results {
                let dur = item.durationSeconds.map(TranscriptTimeFormat.formatClock) ?? "--:--"
                let url = item.applePodcastsURL?.absoluteString ?? item.episodeURL?.absoluteString ?? ""
                print("[\(item.releaseDate)] \(item.showName) — \(item.episodeTitle) (\(dur))\n  \(url)")
            }
        default:
            try await runTranscribe(args)
        }
    }

    private static func runModels(_ args: [String]) async throws {
        let sub = args.first ?? "list"
        switch sub {
        case "list":
            for model in DictationModel.allCases {
                let status = resolvedModelDirectory(for: model) == nil ? "not downloaded" : "installed"
                print("\(model.rawValue)\t\(model.title)\t(\(model.approximateInstalledMegabytes) MB)\t[\(status)]")
            }
        case "download":
            guard args.count >= 2, let model = DictationModel(rawValue: args[1]) else {
                throw NSError(domain: "szcast-cli", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Specify a model: \(DictationModel.allCases.map(\.rawValue).joined(separator: ", "))"
                ])
            }
            _ = try await resolveOrDownload(model: model)
            print("Downloaded \(model.rawValue)")
        default:
            throw NSError(domain: "szcast-cli", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Usage: szcast-cli models list | download <model>"
            ])
        }
    }

    private static func runHistory(_ args: [String]) async throws {
        var query = ""
        var limit = 25
        var idx = 0
        while idx < args.count {
            if args[idx] == "--search", idx + 1 < args.count { query = args[idx + 1]; idx += 2 }
            else if args[idx] == "--limit", idx + 1 < args.count { limit = Int(args[idx + 1]) ?? 25; idx += 2 }
            else { idx += 1 }
        }
        let rows = await MainActor.run {
            let store = sharedTranscriptStore()
            return query.isEmpty ? store.all(limit: limit) : store.search(query: query, limit: limit)
        }
        for row in rows {
            print("\(row.id.uuidString)\t[\(row.kind.label)]\t\(TranscriptTimeFormat.formatClock(row.duration))\t\(row.title)")
        }
    }

    private static func runExport(_ args: [String]) async throws {
        guard let rawID = args.first, let uuid = UUID(uuidString: rawID) else {
            throw NSError(domain: "szcast-cli", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Usage: szcast-cli export <uuid> --format <fmt> [--output <file>]"
            ])
        }
        var format = TranscriptExportFormat.txt
        var outputURL: URL?
        var idx = 1
        while idx < args.count {
            if (args[idx] == "--format" || args[idx] == "-f"), idx + 1 < args.count,
                let parsed = TranscriptExportFormat(rawValue: args[idx + 1].lowercased())
            {
                format = parsed
                idx += 2
            } else if (args[idx] == "--output" || args[idx] == "-o"), idx + 1 < args.count {
                outputURL = URL(fileURLWithPath: args[idx + 1])
                idx += 2
            } else {
                idx += 1
            }
        }
        let found = await MainActor.run { sharedTranscriptStore().record(id: uuid) }
        guard let found else {
            throw NSError(domain: "szcast-cli", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Transcript \(uuid.uuidString) not found."
            ])
        }
        try emit(record: found, format: format, outputURL: outputURL)
    }

    private static func emit(record: TranscriptRecord, format: TranscriptExportFormat, outputURL: URL?) throws {
        let data = try TranscriptExporter.exportData(record, format: format) {
            TranscriptPDFExporter.render(record: $0)
        }
        if let outputURL {
            try data.write(to: outputURL, options: .atomic)
            FileHandle.standardError.write(Data("Wrote \(outputURL.path)\n".utf8))
        } else if (format == .pdf || format == .docx) {
            FileHandle.standardOutput.write(data)
        } else if let text = String(data: data, encoding: .utf8) {
            print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
        }
    }

    @MainActor
    private static func sharedTranscriptStore() -> TranscriptStore {
        let base = appSupportDirectory()
        return TranscriptStore(
            databaseURL: base.appendingPathComponent("transcripts.sqlite3"),
            audioDirectory: base.appendingPathComponent("AudioRecordings", isDirectory: true)
        )
    }

    private static func appSupportDirectory() -> URL {
        for bundleID in ["com.sauravsz.szcast", "com.sauravsz.szcast.dev"] {
            let candidate = AppPaths.applicationSupport(bundleID: bundleID)
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("transcripts.sqlite3").path
            ) {
                return candidate
            }
        }
        return AppPaths.applicationSupport(bundleID: "com.sauravsz.szcast")
    }

    private static func candidateCacheRoots() -> [URL] {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return [
            caches.appendingPathComponent("com.sauravsz.szcast/Dictation"),
            caches.appendingPathComponent("com.sauravsz.szcast.dev/Dictation"),
            appSupport.appendingPathComponent("FluidAudio/Models"),
            appSupport.appendingPathComponent("EnviousWispr/Models")
        ]
    }

    private static func resolvedModelDirectory(for model: DictationModel) -> URL? {
        for root in candidateCacheRoots() {
            for folder in model.possibleFolderNames {
                let candidate = root.appendingPathComponent(folder)
                if model.requiredFiles.allSatisfy({
                    FileManager.default.fileExists(atPath: candidate.appendingPathComponent($0).path)
                }) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func resolveOrDownload(model: DictationModel) async throws -> URL? {
        if let existing = resolvedModelDirectory(for: model) { return existing }
        let dest = candidateCacheRoots()[0].appendingPathComponent(model.folderName)
        FileHandle.standardError.write(Data("Downloading \(model.rawValue)…\n".utf8))
        try await DictationModelDownloader.download(model, destination: dest)
        return dest
    }

    private static func resolveOrDownload(support: DictationSupportModel) async throws -> URL? {
        for root in candidateCacheRoots() {
            for folder in support.possibleFolderNames {
                let candidate = root.appendingPathComponent(folder)
                if support.requiredFiles.allSatisfy({
                    FileManager.default.fileExists(atPath: candidate.appendingPathComponent($0).path)
                }) {
                    return candidate
                }
            }
        }
        let dest = candidateCacheRoots()[0].appendingPathComponent(support.folderName)
        try await DictationModelDownloader.download(support, destination: dest)
        return dest
    }

    private static func printUsage() {
        let usage = """
            szcast-cli — Offline CoreML Transcription & Transcript Exporter

            USAGE:
              szcast-cli transcribe <file-or-url> [options]
              szcast-cli podcast search <query>
              szcast-cli models [list | download <model>]
              szcast-cli history [--search <query>] [--limit <n>]
              szcast-cli export <uuid> --format <fmt> [--output <path>]

            OPTIONS:
              -m, --model <id>     redux (default), ultra, nemotron-0.6b, qwen-0.6b, qwen-1.7b, sravaani-1.0, whisper-apex, indic-flex
              -f, --format <fmt>   txt, md, srt, vtt, json, dapt, pdf, docx
              -o, --output <path>  Write exported output to file instead of stdout
              -s, --speakers <n>   Speaker diarization count (auto or 1..12)
              -l, --lang <code>    Optional ISO language code (e.g. en, hi, bn)
                  --no-vad         Disable CoreML Silero VAD chunking
                  --save           Persist resulting transcript into szcast SQLite FTS5 history
            """
        print(usage)
    }
}
