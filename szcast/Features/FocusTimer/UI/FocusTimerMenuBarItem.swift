import SwiftUI

struct FocusTimerMenuBarLabel: View {
    private var coordinator: FocusTimerCoordinator { AppCore.shared.focusTimerCoordinator }

    var body: some View {
        if coordinator.isActive {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: coordinator.status == .paused ? "pause.fill" : "timer")
                    .accessibilityHidden(true)
                Text(coordinator.formattedRemaining)
                    .monospacedDigit()
            }
            .accessibilityLabel(Text(verbatim: "Focus Timer: \(coordinator.formattedRemaining)"))
        } else {
            EmptyView()
        }
    }
}

struct FocusTimerMenuBarMenu: View {
    private var coordinator: FocusTimerCoordinator { AppCore.shared.focusTimerCoordinator }
    private var settings: AppSettings { AppCore.shared.settings }

    var body: some View {
        Group {
            Section {
                Text("\(coordinator.mode.title) • \(coordinator.formattedRemaining)")

                if coordinator.status == .running {
                    Button("Pause", systemImage: "pause.fill") {
                        coordinator.pause()
                    }
                } else if coordinator.status == .paused {
                    Button("Resume", systemImage: "play.fill") {
                        coordinator.resume()
                    }
                } else {
                    Button("Start", systemImage: "play.fill") {
                        coordinator.start(mode: coordinator.mode)
                    }
                }

                if coordinator.isActive {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        coordinator.reset()
                    }
                }
            }

            Section("Presets") {
                Button(
                    "Start Focus (\(settings.focusTimerWorkDuration)m)",
                    systemImage: FocusTimerMode.work.sfSymbol
                ) {
                    coordinator.start(mode: .work)
                }
                Button(
                    "Start Short Break (\(settings.focusTimerShortBreak)m)",
                    systemImage: FocusTimerMode.shortBreak.sfSymbol
                ) {
                    coordinator.start(mode: .shortBreak)
                }
                Button(
                    "Start Long Break (\(settings.focusTimerLongBreak)m)",
                    systemImage: FocusTimerMode.longBreak.sfSymbol
                ) {
                    coordinator.start(mode: .longBreak)
                }
            }
        }
    }
}
