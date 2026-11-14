import SwiftUI

struct FlightCardView: View {
    @Environment(\.metrics) private var metrics
    let flight: FlightResult
    let selected: Bool

    init(flight: FlightResult, selected: Bool) {
        self.flight = flight
        self.selected = selected
    }

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            // Header: Airline + Flight Number + Status
            HStack {
                HStack(spacing: metrics.spacing.sm) {
                    Image(systemName: "airplane")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("\(flight.airlineName) \(flight.flightNumber)")
                        .font(metrics.typography.rowTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(flight.statusDetail ?? flight.status.rawValue)
                    .font(metrics.typography.compactKeyCap.weight(.medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .fill(Theme.Colors.controlSurface)
                    )
            }

            // Route Bar: Origin -> Destination
            HStack(spacing: metrics.spacing.xl) {
                // Origin
                VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                    Text(flight.departureAirport)
                        .font(metrics.typography.calcResult.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(flight.departureCity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Dep: \(flight.departureTime)")
                        .font(metrics.typography.compactKeyCap)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Flight Progress Indicator
                VStack(spacing: metrics.spacing.xxs) {
                    Image(systemName: "airplane.departure")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Theme.Colors.controlSurface)
                        .frame(height: 2)
                        .overlay(alignment: .leading) {
                            if let progress = flight.progressPercent {
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(width: geo.size.width * CGFloat(progress))
                                }
                            }
                        }
                }
                .frame(width: 80)

                // Destination
                VStack(alignment: .trailing, spacing: metrics.spacing.xxs) {
                    Text(flight.arrivalAirport)
                        .font(metrics.typography.calcResult.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(flight.arrivalCity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Arr: \(flight.arrivalTime)")
                        .font(metrics.typography.compactKeyCap)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.md)
        .leadCard(selected: selected)
    }

    private var statusColor: Color {
        switch flight.status {
        case .landed: return .secondary
        case .active: return .blue
        case .delayed: return .orange
        case .cancelled: return .red
        default: return .secondary
        }
    }
}
