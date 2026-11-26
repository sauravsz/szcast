import SwiftUI

struct SnippetFolderIconView: View {
    let icon: String?
    var size: CGFloat = 20

    var body: some View {
        if let entryIcon = SnippetFaviconService.resolveFolderIcon(icon) {
            EntryIconView(source: entryIcon)
                .frame(width: size, height: size)
        } else if let custom = icon?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            Text(verbatim: String(custom.prefix(2)))
                .font(.system(size: size * 0.72))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: max(4, size * 0.24), style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
        } else {
            EntryIconView(source: .symbol("folder.fill"))
                .frame(width: size, height: size)
        }
    }
}
