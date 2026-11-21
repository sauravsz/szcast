import SwiftUI

/// A colour entry's preview: the colour swatch, copied text, and interactive conversion pills.
struct ColorPreview: View {
    @Environment(\.metrics) private var metrics
    let color: ColorValue
    let text: String
    @State private var copiedFormat: ColorFormat?

    /// Fixed at any pane width: stretched edge to edge a sample reads as a background.
    private static let swatchSize = CGSize(width: 200, height: 100)

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            ColorSwatch(color: color, cornerRadius: metrics.radius.card)
                .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)

            Text(text)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            VStack(spacing: metrics.spacing.xs) {
                ForEach(primaryFormats, id: \.self) { format in
                    let formatted = format.string(for: color)
                    Button {
                        Paster.copyPlainText(formatted)
                        copiedFormat = format
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            if copiedFormat == format { copiedFormat = nil }
                        }
                    } label: {
                        HStack(spacing: metrics.spacing.sm) {
                            Text(format.title)
                                .font(metrics.typography.bar)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            Text(formatted)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if copiedFormat == format {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.green)
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .padding(.horizontal, metrics.spacing.sm)
                        .padding(.vertical, metrics.spacing.xs)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Copy as \(format.title)")
                }
            }
            .padding(.horizontal, metrics.spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, metrics.spacing.md)
    }

    private var primaryFormats: [ColorFormat] {
        [.hex, .rgba, .hsl, .nsColor]
    }
}
