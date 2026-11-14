import SwiftUI

struct TravelCardView: View {
    @Environment(\.metrics) private var metrics
    let travel: TravelResult
    let selected: Bool

    init(travel: TravelResult, selected: Bool) {
        self.travel = travel
        self.selected = selected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            // Header: Origin -> Destination
            HStack(spacing: metrics.spacing.sm) {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(travel.originName)
                    .font(metrics.typography.rowTitle.weight(.semibold))
                    .foregroundStyle(.primary)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)

                Text(travel.destinationName)
                    .font(metrics.typography.rowTitle.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if let fastest = travel.fastestOption {
                    Text("Fastest: \(fastest.durationFormatted)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, metrics.spacing.sm)
                        .padding(.vertical, metrics.spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                                .fill(Theme.Colors.controlSurface)
                        )
                }
            }

            // Route mode pills
            HStack(spacing: metrics.spacing.lg) {
                ForEach(travel.options, id: \.mode) { option in
                    let isFastest = option.mode == travel.fastestMode
                    HStack(spacing: metrics.spacing.sm) {
                        Image(systemName: option.mode.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(isFastest ? .primary : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: metrics.spacing.xs) {
                                Text(option.durationFormatted)
                                    .font(isFastest ? .body.weight(.bold) : .body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("(\(option.distanceFormatted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: metrics.spacing.xs) {
                                Text(option.mode.rawValue)
                                    .font(metrics.typography.compactKeyCap)
                                    .foregroundStyle(.secondary)
                                if let route = option.routeName {
                                    Text("• \(route)")
                                        .font(metrics.typography.compactKeyCap)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, metrics.spacing.md)
                    .padding(.vertical, metrics.spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .fill(isFastest ? Theme.Colors.controlSurface : Color.clear)
                    )
                }
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.md)
        .leadCard(selected: selected)
    }
}
