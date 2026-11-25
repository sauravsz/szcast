import SwiftUI
import UniformTypeIdentifiers

struct TranscriptStudioWindowView: View {
    @Bindable var coordinator: TranscriptStudioCoordinator
    @State private var urlInput = ""
    @State private var questionInput = ""
    @State private var renamingSpeaker: String?
    @State private var speakerNewName = ""
    @State private var editableTitle = ""

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            if let record = coordinator.selectedRecord {
                detailView(record: record)
            } else {
                emptyDetailView
            }
        }
        .sheet(isPresented: $coordinator.isURLSheetPresented) {
            urlAndPodcastSheet
        }
        .sheet(isPresented: Binding(
            get: { renamingSpeaker != nil },
            set: { if !$0 { renamingSpeaker = nil } }
        )) {
            if let old = renamingSpeaker, let record = coordinator.selectedRecord {
                renameSpeakerSheet(oldName: old, record: record)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search transcripts…", text: $coordinator.searchQuery)
                        .textFieldStyle(.plain)
                    if !coordinator.searchQuery.isEmpty {
                        Button { coordinator.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(title: "All", kind: nil)
                        ForEach(TranscriptRecordKind.allCases) { kind in
                            filterChip(title: kind.label, kind: kind)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Button {
                        if coordinator.meetingState.isRecording {
                            coordinator.meetingState.stopRecording()
                        } else {
                            coordinator.meetingState.startRecording()
                        }
                    } label: {
                        Label(
                            coordinator.meetingState.isRecording ? "Stop" : "Record",
                            systemImage: coordinator.meetingState.isRecording ? "stop.fill" : "record.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(coordinator.meetingState.isRecording ? .red : .accentColor)
                    .controlSize(.small)

                    Button {
                        coordinator.pickMediaFilesAndFolders()
                    } label: {
                        Label("Import", systemImage: "folder.badge.plus")
                    }
                    .controlSize(.small)

                    Button {
                        coordinator.isURLSheetPresented = true
                    } label: {
                        Label("URL", systemImage: "link")
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)

            Divider()

            if !coordinator.ingest.jobs.isEmpty {
                batchQueueBar
                Divider()
            }

            List(coordinator.filteredRecords, selection: Binding(
                get: { coordinator.selectedRecordID },
                set: { coordinator.selectRecord($0) }
            )) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: item.kind.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        Text("·")
                        Text(TranscriptTimeFormat.formatClock(item.duration))
                        if !item.speakerNames.isEmpty {
                            Text("· \(item.speakerNames.count) spk")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                .tag(item.id)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        coordinator.deleteRecord(item)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in coordinator.handleDroppedURLs([url]) }
                }
            }
            return true
        }
    }

    private func filterChip(title: String, kind: TranscriptRecordKind?) -> some View {
        let active = coordinator.selectedKind == kind
        return Button(title) {
            coordinator.selectedKind = kind
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: active ? .semibold : .regular))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
            in: Capsule()
        )
        .foregroundStyle(active ? Color.accentColor : Color.primary)
    }

    private var batchQueueBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(coordinator.ingest.isProcessingBatch ? coordinator.ingest.activeStatusText : "Queue finished")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if !coordinator.ingest.isProcessingBatch {
                    Button("Clear") { coordinator.ingest.clearFinishedJobs() }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                }
            }
            ForEach(coordinator.ingest.jobs.suffix(4)) { job in
                HStack(spacing: 6) {
                    switch job.status {
                    case .queued:
                        Image(systemName: "clock").foregroundStyle(.secondary)
                    case .preparing, .transcribing:
                        ProgressView().controlSize(.mini)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                    Text(job.title).font(.caption2).lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Detail

    private func detailView(record: TranscriptRecord) -> some View {
        VStack(spacing: 0) {
            if coordinator.meetingState.isRecording {
                liveMeetingBanner
                Divider()
            }

            detailHeader(record: record)
            Divider()

            if coordinator.playback.canPlay {
                audioScrubberBar
                Divider()
            }

            if coordinator.isFindBarVisible {
                findAndReplaceBar(record: record)
                Divider()
            }

            switch coordinator.activeTab {
            case .transcript:
                transcriptTab(record: record)
            case .notes:
                notesTab(record: record)
            case .askAI:
                askAITab(record: record)
            }
        }
        .onAppear { editableTitle = record.title }
        .onChange(of: record.id) { _, _ in editableTitle = record.title }
    }

    private var liveMeetingBanner: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text("Recording Meeting — Mic (\"Me\") + System Audio (\"Others\")")
                .font(.caption.weight(.semibold))
            Spacer()
            Button {
                coordinator.meetingState.toggleMute()
            } label: {
                Label(
                    coordinator.meetingState.isMuted ? "Unmute Mic" : "Mute Mic",
                    systemImage: coordinator.meetingState.isMuted ? "mic.slash.fill" : "mic.fill"
                )
            }
            .controlSize(.small)
            .tint(coordinator.meetingState.isMuted ? .red : .secondary)

            Button("Cancel", role: .cancel) {
                coordinator.meetingState.cancelRecording()
            }
            .controlSize(.small)

            Button("Stop & Summarize") {
                coordinator.meetingState.stopRecording()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }

    private func detailHeader(record: TranscriptRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Title", text: $editableTitle, onCommit: {
                    coordinator.updateTitle(editableTitle, for: record)
                })
                .font(.title3.weight(.semibold))
                .textFieldStyle(.plain)

                if coordinator.isBusyProcessing {
                    ProgressView().controlSize(.small)
                }

                Picker("", selection: $coordinator.activeTab) {
                    ForEach(TranscriptStudioCoordinator.StudioTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Menu {
                    Button("Auto Speakers") { coordinator.rediarize(record, speakerCount: 0) }
                    Divider()
                    ForEach(1...12, id: \.self) { count in
                        Button("\(count) Speaker\(count == 1 ? "" : "s")") {
                            coordinator.rediarize(record, speakerCount: count)
                        }
                    }
                } label: {
                    Label("Speakers", systemImage: "person.2.wave.2")
                }
                .controlSize(.small)
                .disabled(coordinator.isBusyProcessing)

                Button {
                    coordinator.isFindBarVisible.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command])
                .controlSize(.small)
                .help("Find & Replace  ⌘F")

                Menu {
                    ForEach(TranscriptExportFormat.allCases) { fmt in
                        Button(fmt.displayName) {
                            coordinator.export(record, format: fmt)
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Label(record.kind.label, systemImage: record.kind.symbol)
                Text("·")
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text("\(record.wordCount) words")
                Text("·")
                Text(TranscriptTimeFormat.formatClock(record.duration))
                if let modelID = record.modelID {
                    Text("· \(modelID)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var audioScrubberBar: some View {
        HStack(spacing: 10) {
            Button {
                coordinator.playback.togglePlayPause()
            } label: {
                Image(systemName: coordinator.playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button { coordinator.playback.skip(by: -10) } label: {
                Image(systemName: "gobackward.10")
            }
            .buttonStyle(.borderless)

            Text(TranscriptTimeFormat.formatClock(coordinator.playback.currentTime))
                .font(.caption.monospacedDigit())

            Slider(
                value: Binding(
                    get: { coordinator.playback.currentTime },
                    set: { coordinator.playback.seek(to: $0) }
                ),
                in: 0...max(0.1, coordinator.playback.duration)
            )

            Text(TranscriptTimeFormat.formatClock(coordinator.playback.duration))
                .font(.caption.monospacedDigit())

            Button { coordinator.playback.skip(by: 10) } label: {
                Image(systemName: "goforward.10")
            }
            .buttonStyle(.borderless)

            Button(String(format: "%.2gx", coordinator.playback.rate)) {
                coordinator.playback.cycleRate()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func findAndReplaceBar(record: TranscriptRecord) -> some View {
        HStack(spacing: 8) {
            TextField("Find…", text: $coordinator.findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
            TextField("Replace with…", text: $coordinator.replaceQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
            Toggle("Aa", isOn: $coordinator.findCaseSensitive)
                .toggleStyle(.button)
                .controlSize(.small)
            Button("Replace All") {
                coordinator.replaceAllOccurrences(in: record)
            }
            .controlSize(.small)
            if coordinator.undoManager.canUndo {
                Button("Undo") { coordinator.undoManager.undo() }
                    .controlSize(.small)
            }
            Spacer()
            Button { coordinator.isFindBarVisible = false } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    private func transcriptTab(record: TranscriptRecord) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(record.segments) { segment in
                    let isActive = coordinator.playback.isPlaying
                        && coordinator.playback.currentTime >= segment.start
                        && coordinator.playback.currentTime <= max(segment.end, segment.start + 0.5)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Button(TranscriptTimeFormat.formatClock(segment.start)) {
                                coordinator.playback.seek(to: segment.start, autoPlay: true)
                            }
                            .font(.caption.monospacedDigit())
                            .buttonStyle(.borderless)
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                            if !segment.speaker.isEmpty {
                                Button(segment.speaker) {
                                    renamingSpeaker = segment.speaker
                                    speakerNewName = segment.speaker
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .buttonStyle(.plain)
                                .help("Click to rename speaker across this transcript")
                            }

                            Spacer()
                            Button {
                                Paster.copyPlainText(segment.text)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }

                        if !segment.words.isEmpty && coordinator.playback.canPlay {
                            FlowWordView(words: segment.words, currentTime: coordinator.playback.currentTime) { word in
                                coordinator.playback.seek(to: word.start, autoPlay: true)
                            }
                        } else {
                            Text(segment.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(
                        isActive ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }
            .padding(14)
        }
    }

    private func notesTab(record: TranscriptRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Structured Notes")
                        .font(.headline)
                    Spacer()
                    Button("Generate Notes with AI") {
                        coordinator.generateNotes(for: record)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(coordinator.isBusyProcessing)
                }

                if !record.summary.isEmpty {
                    GroupBox("Summary") {
                        Text(record.summary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(6)
                    }
                }
                if !record.actionItems.isEmpty {
                    GroupBox("Action Items") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(record.actionItems, id: \.self) { item in
                                Text("• \(item)").textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                }
                if !record.decisions.isEmpty {
                    GroupBox("Decisions") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(record.decisions, id: \.self) { item in
                                Text("• \(item)").textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                }
                if record.summary.isEmpty && record.actionItems.isEmpty && record.decisions.isEmpty {
                    Text("Click \"Generate Notes with AI\" to summarize long transcripts into action items and decisions.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            .padding(14)
        }
    }

    private func askAITab(record: TranscriptRecord) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let history = coordinator.qaHistories[record.id] ?? []
                    if history.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(
                                ["Summarize key points", "List all action items", "What were the open questions?"],
                                id: \.self
                            ) { prompt in
                                Button(prompt) {
                                    coordinator.askQuestion(prompt, for: record)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 8)
                    }
                    ForEach(history) { msg in
                        HStack {
                            if msg.isUser { Spacer(minLength: 48) }
                            Text(msg.text)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(
                                    msg.isUser ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                            if !msg.isUser { Spacer(minLength: 48) }
                        }
                    }
                    if coordinator.isAnsweringQuestion {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(14)
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask anything about this transcript…", text: $questionInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let q = questionInput
                        questionInput = ""
                        coordinator.askQuestion(q, for: record)
                    }
                Button("Send") {
                    let q = questionInput
                    questionInput = ""
                    coordinator.askQuestion(q, for: record)
                }
                .buttonStyle(.borderedProminent)
                .disabled(questionInput.trimmingCharacters(in: .whitespaces).isEmpty || coordinator.isAnsweringQuestion)
            }
            .padding(10)
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("No Transcript Selected")
                .font(.headline)
            Text("Drop audio/video files or folders here, record a meeting, or import a YouTube / Apple Podcasts link.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            HStack(spacing: 10) {
                Button("Import Files or Folder") { coordinator.pickMediaFilesAndFolders() }
                Button("Import URL / Podcast") { coordinator.isURLSheetPresented = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sheets

    private var urlAndPodcastSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transcribe URL or Apple Podcast")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("https://youtube.com/... or https://podcasts.apple.com/...", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        coordinator.ingestURLString(urlInput)
                        urlInput = ""
                    }
                Button("Transcribe URL") {
                    coordinator.ingestURLString(urlInput)
                    urlInput = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            Text("Search Apple Podcasts")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Search shows or episodes…", text: $coordinator.podcastQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { coordinator.runPodcastSearch() }
                Button("Search") { coordinator.runPodcastSearch() }
                    .disabled(coordinator.isSearchingPodcasts)
            }

            List(coordinator.podcastResults) { episode in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.episodeTitle)
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(episode.showName) · \(episode.releaseDate)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Transcribe") {
                        coordinator.transcribePodcastEpisode(episode)
                    }
                    .controlSize(.small)
                }
            }
            .frame(height: 220)

            HStack {
                Spacer()
                Button("Close", role: .cancel) { coordinator.isURLSheetPresented = false }
            }
        }
        .padding(18)
        .frame(width: 540)
    }

    private func renameSpeakerSheet(oldName: String, record: TranscriptRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Speaker \"\(oldName)\"")
                .font(.headline)
            TextField("Speaker name", text: $speakerNewName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { renamingSpeaker = nil }
                Button("Rename") {
                    coordinator.renameSpeaker(oldName: oldName, to: speakerNewName, in: record)
                    renamingSpeaker = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 320)
    }
}

private struct FlowWordView: View {
    let words: [TranscriptWord]
    let currentTime: TimeInterval
    let onTap: (TranscriptWord) -> Void

    var body: some View {
        WordWrapLayout(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let highlighted = currentTime >= word.start && currentTime <= max(word.end, word.start + 0.15)
                Button {
                    onTap(word)
                } label: {
                    Text(word.text)
                        .font(.body)
                        .padding(.horizontal, 2)
                        .background(
                            highlighted ? Color.accentColor.opacity(0.28) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WordWrapLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
