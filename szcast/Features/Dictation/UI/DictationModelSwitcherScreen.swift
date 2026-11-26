import AppKit
import SwiftUI

struct DictationModelSwitcherScreen: PaletteScreen {
    struct Option: Identifiable {
        enum Kind {
            case local(DictationModel)
            case cloud(DictationCloudSpeechProvider, modelName: String)
        }

        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let badge: String
        let isActive: Bool
        let systemImage: String
    }

    let core: AppCore
    let vm: PaletteState

    private var coordinator: DictationCoordinator { core.dictationCoordinator }
    private var settings: AppSettings { core.settings }

    var rows: [Option] {
        var list: [Option] = []

        for model in DictationModel.allCases where coordinator.models.isInstalled(model) {
            let isActive = settings.dictationTranscriptionProvider == .local && settings.dictationModel == model
            list.append(
                Option(
                    id: "local:\(model.rawValue)",
                    kind: .local(model),
                    title: model.title,
                    subtitle: "\(model.coverage) — \(model.summary)",
                    badge: String(localized: "Local"),
                    isActive: isActive,
                    systemImage: "cpu"
                )
            )
        }

        if DictationCloudSpeechService.hasAPIKey(
            for: .groq,
            groqAPIKey: settings.groqAPIKey,
            deepgramAPIKey: settings.deepgramAPIKey
        ) {
            let modelName = settings.dictationGroqTranscriptionModel
            let isActive = settings.dictationTranscriptionProvider == .cloud
                && settings.dictationCloudSpeechProvider == .groq
            list.append(
                Option(
                    id: "cloud:groq",
                    kind: .cloud(.groq, modelName: modelName),
                    title: "Groq · \(modelName)",
                    subtitle: String(localized: "Ultra-fast cloud Whisper speech recognition via Groq LPU."),
                    badge: String(localized: "Cloud"),
                    isActive: isActive,
                    systemImage: "cloud.fill"
                )
            )
        }

        if DictationCloudSpeechService.hasAPIKey(
            for: .deepgram,
            groqAPIKey: settings.groqAPIKey,
            deepgramAPIKey: settings.deepgramAPIKey
        ) {
            let modelName = settings.dictationDeepgramModel
            let isActive = settings.dictationTranscriptionProvider == .cloud
                && settings.dictationCloudSpeechProvider == .deepgram
            list.append(
                Option(
                    id: "cloud:deepgram",
                    kind: .cloud(.deepgram, modelName: modelName),
                    title: "Deepgram · \(modelName)",
                    subtitle: String(localized: "Low-latency cloud speech recognition powered by Deepgram."),
                    badge: String(localized: "Cloud"),
                    isActive: isActive,
                    systemImage: "cloud.fill"
                )
            )
        }

        let trimmed = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
                || $0.badge.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var primaryActionTitle: String { String(localized: "Set Active") }

    func actions(at selection: Int) -> PopoverMenuContent? {
        PopoverMenuContent(
            header: String(localized: "Transcription Models"),
            items: [
                PopoverMenuItem(
                    title: String(localized: "Set Active Model"),
                    systemImage: "checkmark.circle",
                    shortcut: "↵"
                ) {
                    activate(at: selection)
                },
                PopoverMenuItem(
                    title: String(localized: "Open Model Library"),
                    systemImage: "slider.horizontal.3",
                    startsSection: true,
                    shortcut: "⌘,"
                ) {
                    openModelLibrary()
                }
            ]
        )
    }

    func activate(at selection: Int) {
        let items = rows
        guard items.indices.contains(selection) else {
            openModelLibrary()
            return
        }
        let option = items[selection]
        switch option.kind {
        case .local(let model):
            coordinator.activateLocalModel(model)
            core.paletteCoordinator.hidePalette()
            core.showMessage(String(localized: "Active speech model: \(model.title)"), tone: .success)
        case .cloud(let cloudProvider, let modelName):
            settings.dictationTranscriptionProvider = .cloud
            settings.dictationCloudSpeechProvider = cloudProvider
            core.paletteCoordinator.hidePalette()
            core.showMessage(
                String(localized: "Active speech model: \(cloudProvider.title) (\(modelName))"),
                tone: .success
            )
        }
    }

    func secondary(at selection: Int) -> Bool {
        openModelLibrary()
        return true
    }

    private func openModelLibrary() {
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        core.settingsCoordinator.showSettings(tab: .dictation, revealing: .section(.modelLibrarySpeech))
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let items = rows
        return AnyView(
            VStack(spacing: 0) {
                if items.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No ready transcription models"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Download a Local model or add a Cloud API key in Dictation › Model Library."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        Button(String(localized: "Open Model Library")) {
                            openModelLibrary()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Spacing.xxl)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, option in
                                    DictationModelOptionRow(
                                        option: option,
                                        slot: FavoriteSlots.digit(at: index),
                                        isSelected: index == selection,
                                        onSelect: { activate(at: index) }
                                    )
                                    .id(option.id)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                        .onChange(of: selection) { _, newValue in
                            guard items.indices.contains(newValue) else { return }
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(items[newValue].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        )
    }
}

private struct DictationModelOptionRow: View {
    let option: DictationModelSwitcherScreen.Option
    let slot: Character?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: option.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(option.isActive ? Color.accentColor : .secondary)
                .frame(width: 26, height: 26)
                .background((option.isActive ? Color.accentColor : Color.secondary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(option.title)
                        .font(.body.weight(option.isActive ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(option.badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                }

                Text(option.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            SlotChordReveal(slot: slot) {
                if option.isActive {
                    Label(String(localized: "Active"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isSelected ? Theme.Colors.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
