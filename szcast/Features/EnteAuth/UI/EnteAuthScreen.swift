import AppKit
import SwiftUI

struct EnteAuthScreen: PaletteScreen {
    let store: EnteAuthStore
    let core: AppCore
    let vm: PaletteState

    struct Row: Identifiable {
        let id: String
        let account: EnteAuthAccount?
        let tokenInfo: TOTPEngine.TokenInfo?
        let isImportAction: Bool
        let title: String
        let subtitle: String?
    }

    var rows: [Row] {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if store.accounts.isEmpty {
            let foundExport = store.findExportFile()
            let sub = foundExport != nil
                ? String(localized: "Found '\(foundExport!.lastPathComponent)' in Downloads! Press Return to import.")
                : String(localized: "Place ente_auth.txt in ~/Downloads and press Return to import.")
            return [
                Row(
                    id: "empty-import",
                    account: nil,
                    tokenInfo: nil,
                    isImportAction: true,
                    title: String(localized: "Import Accounts from Ente Auth"),
                    subtitle: sub
                )
            ]
        }

        let now = Date()
        var list: [Row] = []

        for acc in store.accounts {
            if !query.isEmpty {
                let matchesIssuer = acc.issuer.lowercased().contains(query)
                let matchesUser = acc.username.lowercased().contains(query)
                let matchesTags = acc.tags.contains { $0.lowercased().contains(query) }
                let matchesNotes = acc.notes?.lowercased().contains(query) ?? false
                guard matchesIssuer || matchesUser || matchesTags || matchesNotes else {
                    continue
                }
            }

            let info = TOTPEngine.tokenInfo(
                secret: acc.secret,
                timestamp: now,
                period: acc.period,
                digits: acc.digits,
                algorithm: acc.algorithm
            )

            list.append(
                Row(
                    id: acc.id.uuidString,
                    account: acc,
                    tokenInfo: info,
                    isImportAction: false,
                    title: acc.displayTitle,
                    subtitle: acc.username.isEmpty ? nil : acc.username
                )
            )
        }

        // Frecency sort: highest useCount first, then alphabetical by issuer
        list.sort { a, b in
            let countA = a.account?.useCount ?? 0
            let countB = b.account?.useCount ?? 0
            if countA != countB { return countA > countB }
            return (a.account?.issuer ?? "") < (b.account?.issuer ?? "")
        }

        return list
    }

    var primaryActionTitle: String {
        if store.accounts.isEmpty {
            return String(localized: "Import Accounts")
        }
        return String(localized: "Copy TOTP")
    }

    func activate(at selection: Int) {
        let items = rows
        guard items.indices.contains(selection) else { return }
        let row = items[selection]

        if row.isImportAction {
            let result = store.importSecrets()
            core.showMessage(result.message, tone: result.success ? .success : .danger)
            if result.success {
                core.paletteCoordinator.hidePalette()
            }
            return
        }

        guard let acc = row.account, let info = row.tokenInfo else { return }

        // Copy raw TOTP code to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.currentCode, forType: .string)

        store.recordUsage(id: acc.id)
        core.paletteCoordinator.hidePalette()
        core.showMessage(String(localized: "Copied \(acc.issuer) TOTP (\(info.currentFormatted)) to clipboard"), tone: .success)
    }

    func secondary(at selection: Int) -> Bool {
        let items = rows
        guard items.indices.contains(selection) else { return false }
        let row = items[selection]

        guard let acc = row.account, let info = row.tokenInfo else { return false }

        // Paste directly into frontmost app
        let app = NSWorkspace.shared.frontmostApplication
        store.recordUsage(id: acc.id)
        core.paletteCoordinator.hidePalette()

        Paster.pasteString(info.currentCode, previousApp: app) {
            core.showMessage(String(localized: "Pasted \(acc.issuer) TOTP (\(info.currentFormatted))"), tone: .success)
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let items = rows
        let isSelectionValid = items.indices.contains(selection)

        return AnyView(
            VStack(spacing: 0) {
                if items.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "key.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No matching 2FA accounts found"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Check your query or press ⌘I to import from ente_auth.txt"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Spacing.xxl)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                                EnteAuthRowView(
                                    row: row,
                                    isSelected: index == selection,
                                    onSelect: { activate(at: index) }
                                )
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
        )
    }
}

private struct EnteAuthRowView: View {
    let row: EnteAuthScreen.Row
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            iconView

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let sub = row.subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let info = row.tokenInfo {
                tokenView(info: info)
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

    private var iconView: some View {
        let isImport = row.isImportAction
        let iconColor: Color = isImport ? Color.accentColor : Theme.Colors.brand
        return Image(systemName: isImport ? "arrow.down.doc.fill" : "key.fill")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(iconColor)
            .frame(width: 24, height: 24)
            .background(iconColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func tokenView(info: TOTPEngine.TokenInfo) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Next: \(info.nextFormatted)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            Text(info.currentFormatted)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            Text("\(info.timeRemaining)s")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(countdownTextColor(info.timeRemaining))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(countdownBadgeBackground(info.timeRemaining))
                .clipShape(Capsule())
        }
    }

    private func countdownTextColor(_ remaining: Int) -> Color {
        if remaining > 10 { return Color.green }
        if remaining > 5 { return Color.orange }
        return Color.red
    }

    private func countdownBadgeBackground(_ remaining: Int) -> Color {
        if remaining > 10 { return Color.green.opacity(0.18) }
        if remaining > 5 { return Color.orange.opacity(0.2) }
        return Color.red.opacity(0.25)
    }
}
