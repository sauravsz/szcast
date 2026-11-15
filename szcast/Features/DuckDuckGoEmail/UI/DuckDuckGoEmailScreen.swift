import AppKit
import SwiftUI

struct DuckDuckGoEmailScreen: PaletteScreen {
    let service: DuckDuckGoEmailService
    let core: AppCore
    let vm: PaletteState

    @State private var inputToken: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    struct Row: Identifiable {
        let id: String
        let title: String
    }

    var rows: [Row] {
        if service.hasToken {
            return [Row(id: "generate", title: String(localized: "Generate Address"))]
        } else {
            return [Row(id: "save", title: String(localized: "Save Token"))]
        }
    }

    var primaryActionTitle: String {
        service.hasToken ? String(localized: "Generate Address") : String(localized: "Save Token")
    }

    func activate(at selection: Int) {
        if service.hasToken {
            Task { @MainActor in
                core.paletteCoordinator.hidePalette()
                let result = await service.generateAndCopy()
                core.showMessage(result.message, tone: result.success ? .success : .danger)
            }
        } else {
            let clean = inputToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                errorMessage = String(localized: "Please enter a valid token.")
                return
            }
            service.token = clean
            Task { @MainActor in
                core.paletteCoordinator.hidePalette()
                let result = await service.generateAndCopy()
                core.showMessage(result.message, tone: result.success ? .success : .danger)
            }
        }
    }

    func secondary(at selection: Int) -> Bool {
        return false
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "DuckDuckGo Email Protection"))
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(String(localized: "Generate on-demand private @duck.com forwarding addresses."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)

                Divider()

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if service.hasToken {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text(String(localized: "DuckDuckGo Token is configured in Keychain."))
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }

                        Button {
                            Task { @MainActor in
                                core.paletteCoordinator.hidePalette()
                                let result = await service.generateAndCopy()
                                core.showMessage(result.message, tone: result.success ? .success : .danger)
                            }
                        } label: {
                            Label(String(localized: "Generate & Copy New Duck Address (Hyper + D)"), systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orange)

                        Button(role: .destructive) {
                            service.token = nil
                        } label: {
                            Text(String(localized: "Reset Token…"))
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "Paste your DuckDuckGo Email Bearer token below:"))
                            .font(.callout.weight(.medium))

                        TextField("Bearer token...", text: $inputToken)
                            .textFieldStyle(.roundedBorder)

                        if let err = errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(Color.red)
                        }

                        HStack(spacing: Theme.Spacing.md) {
                            Button {
                                if let url = URL(string: "https://duckduckgo.com/email") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label(String(localized: "Get Token (duckduckgo.com/email)"), systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.link)
                            .font(.caption)

                            Spacer()

                            Button(String(localized: "Save & Generate Address")) {
                                activate(at: 0)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.orange)
                            .disabled(inputToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)

                Spacer()
            }
        )
    }
}
