import SwiftUI

struct EmojiSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureCommandsSection(owner: .emoji, anchor: .emojiCommands)

            Section {
                EmojiColumnCountPicker(selection: $settings.emojiGridColumns)

                Picker(selection: $settings.emojiPrimaryAction) {
                    ForEach(EmojiPrimaryAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                } label: {
                    SettingsRowTitle(.emojiAppearance, "Primary Action")
                    Text(settings.emojiPrimaryAction.subtitle)
                }

                SettingsRow(title: "Emoji Skin Tone", anchor: .emojiAppearance) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(EmojiSkinTone.allCases) { tone in
                            let selected = settings.emojiSkinTone == tone
                            Button {
                                settings.emojiSkinTone = tone
                            } label: {
                                Text(tone.sample)
                                    .font(.system(size: Theme.Size.emojiSkinToneGlyph))
                                    .settingsOptionSegment(isSelected: selected)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tone.title)
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                            .help(tone.title)
                        }
                    }
                }

                Toggle(isOn: $settings.emojiSaveAIKeywords) {
                    SettingsRowTitle(.emojiAppearance, "Save AI-generated custom keywords")
                    Text("Stores your search terms as custom keywords on the emoji you copied or pasted.")
                }
            } header: {
                SettingsSectionHeader(.emojiAppearance)
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SettingsRowTitle(.emojiAppearance, "Replace System Emoji Picker")
                    Text("To replace macOS's default Character Viewer (⌃⌘Space or Globe/Fn key), record your preferred shortcut directly on the 'Search Emoji & Symbols' command above in the Commands table.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.emoji)
    }
}

/// Five previews make the picker's starting density legible before the user opens it.
private struct EmojiColumnCountPicker: View {
    @Binding var selection: EmojiGridColumns

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsRowTitle(.emojiAppearance, "Column Count")

            HStack(spacing: Theme.Spacing.xl) {
                ForEach(EmojiGridColumns.allCases) { columns in
                    option(columns)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func option(_ columns: EmojiGridColumns) -> some View {
        let isSelected = selection == columns
        return Button {
            selection = columns
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                EmojiColumnCountPreview(columns: columns.rawValue, isSelected: isSelected)
                Text(columns.rawValue, format: .number)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(columns.rawValue) columns")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EmojiColumnCountPreview: View {
    let columns: Int
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        EmojiGridDots(columns: columns)
            .fill(isSelected ? Theme.Colors.textTertiary : Theme.Colors.border)
            .background(
                shape.fill(isSelected ? Theme.Colors.controlSurface : Color.clear)
            )
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.border : Theme.Colors.cardStroke,
                    lineWidth: Theme.Size.hairline)
            )
            .clipShape(shape)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: Theme.Size.emojiSettingsGridPreview)
    }
}

/// Dots share one lattice, so horizontal and vertical runs meet on the exact same point.
private struct EmojiGridDots: Shape {
    let columns: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = CGFloat(columns)
        let step = rect.width / count
        let radius = step * 0.18
        for row in 0..<columns {
            for col in 0..<columns {
                let center = CGPoint(
                    x: (CGFloat(col) + 0.5) * step,
                    y: (CGFloat(row) + 0.5) * step)
                path.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2))
            }
        }
        return path
    }
}
