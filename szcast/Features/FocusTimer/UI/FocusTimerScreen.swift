import SwiftUI

struct FocusTimerScreen: PaletteScreen {
    let coordinator: FocusTimerCoordinator
    let core: AppCore
    let vm: PaletteState

    struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let symbol: String
        let run: () -> Void
    }

    var rows: [Row] {
        let settings = core.settings
        var list: [Row] = []

        switch coordinator.status {
        case .running:
            list.append(
                Row(
                    id: "pause",
                    title: String(localized: "Pause Timer"),
                    subtitle: coordinator.formattedRemaining,
                    symbol: "pause.fill",
                    run: { coordinator.pause() }
                ))
            list.append(
                Row(
                    id: "reset",
                    title: String(localized: "Reset Timer"),
                    subtitle: nil,
                    symbol: "arrow.counterclockwise",
                    run: { coordinator.reset() }
                ))
            list.append(
                Row(
                    id: "break-short",
                    title: String(localized: "Switch to Short Break"),
                    subtitle: "\(settings.focusTimerShortBreak) minutes",
                    symbol: FocusTimerMode.shortBreak.sfSymbol,
                    run: { coordinator.start(mode: .shortBreak) }
                ))
            list.append(
                Row(
                    id: "break-long",
                    title: String(localized: "Switch to Long Break"),
                    subtitle: "\(settings.focusTimerLongBreak) minutes",
                    symbol: FocusTimerMode.longBreak.sfSymbol,
                    run: { coordinator.start(mode: .longBreak) }
                ))

        case .paused:
            list.append(
                Row(
                    id: "resume",
                    title: String(localized: "Resume Timer"),
                    subtitle: coordinator.formattedRemaining,
                    symbol: "play.fill",
                    run: { coordinator.resume() }
                ))
            list.append(
                Row(
                    id: "reset",
                    title: String(localized: "Reset Timer"),
                    subtitle: nil,
                    symbol: "arrow.counterclockwise",
                    run: { coordinator.reset() }
                ))
            list.append(
                Row(
                    id: "focus",
                    title: String(localized: "Start New Focus Session"),
                    subtitle: "\(settings.focusTimerWorkDuration) minutes",
                    symbol: FocusTimerMode.work.sfSymbol,
                    run: { coordinator.start(mode: .work) }
                ))

        case .idle:
            list.append(
                Row(
                    id: "start-work",
                    title: String(localized: "Start Focus Session"),
                    subtitle: "\(settings.focusTimerWorkDuration) minutes",
                    symbol: FocusTimerMode.work.sfSymbol,
                    run: { coordinator.start(mode: .work) }
                ))
            list.append(
                Row(
                    id: "start-short-break",
                    title: String(localized: "Start Short Break"),
                    subtitle: "\(settings.focusTimerShortBreak) minutes",
                    symbol: FocusTimerMode.shortBreak.sfSymbol,
                    run: { coordinator.start(mode: .shortBreak) }
                ))
            list.append(
                Row(
                    id: "start-long-break",
                    title: String(localized: "Start Long Break"),
                    subtitle: "\(settings.focusTimerLongBreak) minutes",
                    symbol: FocusTimerMode.longBreak.sfSymbol,
                    run: { coordinator.start(mode: .longBreak) }
                ))
        }

        return list
    }

    var primaryActionTitle: String {
        switch coordinator.status {
        case .running: return String(localized: "Pause")
        case .paused: return String(localized: "Resume")
        case .idle: return String(localized: "Start")
        }
    }

    func activate(at selection: Int) {
        let items = rows
        guard items.indices.contains(selection) else { return }
        items[selection].run()
    }

    func secondary(at selection: Int) -> Bool {
        false
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            VStack(spacing: Theme.Spacing.md) {
                // Header Card
                VStack(spacing: Theme.Spacing.xs) {
                    HStack {
                        Image(systemName: coordinator.mode.sfSymbol)
                            .foregroundStyle(.secondary)
                        Text(coordinator.mode.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(statusDescription)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusBadgeBackground)
                            .clipShape(Capsule())
                    }

                    Text(coordinator.formattedRemaining)
                        .font(.system(size: 44, weight: .light, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(.vertical, Theme.Spacing.xs)

                    ProgressView(value: coordinator.progress)
                        .tint(progressTint)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.rowHover)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)

                // Actions List
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: Theme.Spacing.md) {
                                Image(systemName: row.symbol)
                                    .frame(width: 20)
                                    .foregroundStyle(.primary)
                                Text(row.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(index == selection ? Theme.Colors.selection : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activate(at: index)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
        )
    }

    private var statusDescription: String {
        switch coordinator.status {
        case .running: return String(localized: "Active")
        case .paused: return String(localized: "Paused")
        case .idle: return String(localized: "Ready")
        }
    }

    private var statusBadgeBackground: Color {
        switch coordinator.status {
        case .running: return Color.green.opacity(0.2)
        case .paused: return Color.orange.opacity(0.2)
        case .idle: return Color.secondary.opacity(0.15)
        }
    }

    private var progressTint: Color {
        switch coordinator.mode {
        case .work: return Color.accentColor
        case .shortBreak, .longBreak: return Color.green
        }
    }
}
