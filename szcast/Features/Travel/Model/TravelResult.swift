import Foundation
import CoreLocation

public enum TravelMode: String, CaseIterable, Equatable, Sendable {
    case driving = "Driving"
    case transit = "Transit"
    case walking = "Walking"

    public var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .transit: return "tram.fill"
        case .walking: return "figure.walk"
        }
    }
}

public struct TravelRouteOption: Equatable, Sendable {
    public let mode: TravelMode
    public let durationSeconds: TimeInterval
    public let distanceMeters: CLLocationDistance
    public let routeName: String?

    public init(mode: TravelMode, durationSeconds: TimeInterval, distanceMeters: CLLocationDistance, routeName: String? = nil) {
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.routeName = routeName
    }

    public var durationFormatted: String {
        let total = Int(durationSeconds.rounded())
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        if hrs > 0 {
            return "\(hrs) hr \(mins) min"
        } else {
            return "\(max(1, mins)) min"
        }
    }

    public var distanceFormatted: String {
        let km = distanceMeters / 1000.0
        return String(format: "%.1f km", km)
    }

    public func etaFormatted(from date: Date = Date()) -> String {
        let eta = date.addingTimeInterval(durationSeconds)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: eta)
    }
}

public struct TravelResult: Equatable, Sendable {
    public let originName: String
    public let destinationName: String
    public let options: [TravelRouteOption]
    public let fastestMode: TravelMode

    public init(originName: String, destinationName: String, options: [TravelRouteOption], fastestMode: TravelMode) {
        self.originName = originName
        self.destinationName = destinationName
        self.options = options
        self.fastestMode = fastestMode
    }

    public var fastestOption: TravelRouteOption? {
        options.first(where: { $0.mode == fastestMode }) ?? options.first
    }

    public var summaryText: String {
        guard let best = fastestOption else { return "\(originName) to \(destinationName)" }
        return "\(originName) to \(destinationName): \(best.durationFormatted) (\(best.distanceFormatted) via \(best.mode.rawValue))"
    }

    public var directionsURL: URL? {
        guard let o = originName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let d = destinationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://maps.apple.com/?saddr=\(o)&daddr=\(d)")
    }
}
