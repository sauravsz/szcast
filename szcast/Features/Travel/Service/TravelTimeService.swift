import Foundation
import MapKit
import Observation

@Observable
@MainActor
public final class TravelTimeService {
    public static let shared = TravelTimeService()

    public private(set) var activeResult: TravelResult?

    private var cache: [String: (result: TravelResult, timestamp: Date)] = [:]
    private var inFlightQueries: Set<String> = []
    private let cacheTTL: TimeInterval = 1800 // 30 minutes

    public func parseTravelQuery(from rawQuery: String) -> (origin: String, destination: String)? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Patterns:
        // "time from X to Y", "travel time from X to Y", "drive from X to Y"
        // "from X to Y", "X to Y travel time", "X to Y time"
        var working = lower
        for prefix in ["travel time from ", "time from ", "drive from ", "walking time from ", "transit time from ", "from "] {
            if working.hasPrefix(prefix) {
                working = String(working.dropFirst(prefix.count))
                break
            }
        }
        for suffix in [" travel time", " travel", " time"] {
            if working.hasSuffix(suffix) {
                working = String(working.dropLast(suffix.count))
                break
            }
        }

        // Split on " to "
        guard let toRange = working.range(of: " to ") else { return nil }
        let originStr = String(working[..<toRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let destStr = String(working[toRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Ignore unit conversions like "10 km to miles" or "100 usd to eur"
        if isUnitConversion(origin: originStr, destination: destStr) {
            return nil
        }

        guard originStr.count >= 2, destStr.count >= 2 else { return nil }
        return (originStr.capitalized, destStr.capitalized)
    }

    private func isUnitConversion(origin: String, destination: String) -> Bool {
        let words = origin.split(whereSeparator: \.isWhitespace)
        if let first = words.first, first.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) {
            return true
        }
        return false
    }

    public func resolveTravel(query: String) -> TravelResult? {
        guard let endpoints = parseTravelQuery(from: query) else {
            activeResult = nil
            return nil
        }

        let key = "\(endpoints.origin) -> \(endpoints.destination)".lowercased()
        if let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            activeResult = cached.result
            return cached.result
        }

        if !inFlightQueries.contains(key) {
            inFlightQueries.insert(key)
            Task {
                await fetchDirections(origin: endpoints.origin, destination: endpoints.destination, key: key)
            }
        }

        return activeResult
    }

    private func fetchDirections(origin: String, destination: String, key: String) async {
        defer { inFlightQueries.remove(key) }

        do {
            let origins = try await CLGeocoder().geocodeAddressString(origin)
            let dests = try await CLGeocoder().geocodeAddressString(destination)
            guard let originItem = origins.first, let destItem = dests.first else { return }

            let originMapItem = MKMapItem(placemark: MKPlacemark(placemark: originItem))
            let destMapItem = MKMapItem(placemark: MKPlacemark(placemark: destItem))

            let modes: [(TravelMode, MKDirectionsTransportType)] = [
                (.driving, .automobile),
                (.transit, .transit),
                (.walking, .walking)
            ]

            var routeOptions: [TravelRouteOption] = []

            for (mode, transportType) in modes {
                let request = MKDirections.Request()
                request.source = originMapItem
                request.destination = destMapItem
                request.transportType = transportType
                request.requestsAlternateRoutes = false

                let directions = MKDirections(request: request)
                if let response = try? await directions.calculate(), let route = response.routes.first {
                    routeOptions.append(TravelRouteOption(
                        mode: mode,
                        durationSeconds: route.expectedTravelTime,
                        distanceMeters: route.distance,
                        routeName: route.name.isEmpty ? nil : route.name
                    ))
                }
            }

            guard !routeOptions.isEmpty else { return }

            let fastest = routeOptions.min(by: { $0.durationSeconds < $1.durationSeconds })?.mode ?? .driving

            let originDisplayName = originItem.locality ?? originItem.name ?? origin
            let destDisplayName = destItem.locality ?? destItem.name ?? destination

            let result = TravelResult(
                originName: originDisplayName,
                destinationName: destDisplayName,
                options: routeOptions,
                fastestMode: fastest
            )

            cache[key] = (result, Date())
            activeResult = result
        } catch {
            // Geocoding or MapKit directions failed; gracefully no-op
        }
    }
}
