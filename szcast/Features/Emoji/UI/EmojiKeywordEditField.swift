import SwiftUI

struct EmojiKeywordEditField: View {
    @Environment(\.metrics) private var metrics
    @Bindable var state: EmojiKeywordInputState
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(state.glyph)
                .font(.system(size: 20))

            TextField("", text: $state.text, prompt: Text(state.placeholder).foregroundStyle(Theme.Colors.textTertiary))
                .textFieldStyle(.plain)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .focused($isFocused)
                .lineLimit(1)
                .onAppear {
                    isFocused = true
                }

            if !state.text.isEmpty {
                Button {
                    state.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.menuRowHeight)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}
