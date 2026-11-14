import SwiftUI

struct WeatherCardView: View {
    @Environment(\.metrics) private var metrics
    let weather: WeatherResult
    let selected: Bool

    init(weather: WeatherResult, selected: Bool) {
        self.weather = weather
        self.selected = selected
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            // Left: Icon + Location + Condition + Temp
            HStack(spacing: metrics.spacing.md) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 32, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                    Text(weather.locationName)
                        .font(metrics.typography.rowTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(weather.conditionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(weather.formatTemp(weather.currentTemp))
                    .font(metrics.typography.calcResult.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.leading, metrics.spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 32)

            // Middle: High/Low & Feels Like
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                HStack(spacing: metrics.spacing.xs) {
                    Text("H: \(weather.formatTemp(weather.highTemp))")
                        .foregroundStyle(.primary)
                    Text("L: \(weather.formatTemp(weather.lowTemp))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))

                HStack(spacing: metrics.spacing.xs) {
                    Text("Feels like \(weather.formatTemp(weather.apparentTemp))")
                        .foregroundStyle(.secondary)
                    if weather.humidity > 0 {
                        Text("• \(weather.humidity)%")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !weather.hourly.isEmpty {
                Divider()
                    .frame(height: 32)

                // Right: 4-Hour Forecast Strip
                HStack(spacing: metrics.spacing.md) {
                    ForEach(Array(weather.hourly.prefix(4).enumerated()), id: \.offset) { _, slot in
                        VStack(spacing: metrics.spacing.xxs) {
                            Text(slot.time)
                                .font(metrics.typography.compactKeyCap)
                                .foregroundStyle(.tertiary)
                            Image(systemName: slot.symbol)
                                .font(.system(size: 14))
                                .symbolRenderingMode(.multicolor)
                            Text(weather.formatTemp(slot.temperature))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .leadCard(selected: selected)
    }
}
