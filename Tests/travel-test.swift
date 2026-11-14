import Foundation
import CoreLocation

@main
@MainActor
struct TravelTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        let service = TravelTimeService.shared

        // Query Parsing Tests
        if let pair1 = service.parseTravelQuery(from: "time from Paris to Lyon") {
            expect(pair1.origin.lowercased() == "paris" && pair1.destination.lowercased() == "lyon", "time from Paris to Lyon parsed")
        } else {
            expect(false, "time from Paris to Lyon failed to parse")
        }

        if let pair2 = service.parseTravelQuery(from: "travel time from London to Oxford") {
            expect(pair2.origin.lowercased() == "london" && pair2.destination.lowercased() == "oxford", "London to Oxford parsed")
        } else {
            expect(false, "London to Oxford failed to parse")
        }

        if let pair3 = service.parseTravelQuery(from: "Paris to Lyon travel time") {
            expect(pair3.origin.lowercased() == "paris" && pair3.destination.lowercased() == "lyon", "Paris to Lyon travel time parsed")
        } else {
            expect(false, "Paris to Lyon travel time failed to parse")
        }

        // Rejections (Math & Unit conversions must NOT match as travel)
        expect(service.parseTravelQuery(from: "10 km to miles") == nil, "10 km to miles rejected")
        expect(service.parseTravelQuery(from: "100 usd to eur") == nil, "100 usd to eur rejected")
        expect(service.parseTravelQuery(from: "2+2") == nil, "2+2 rejected")

        // Route Formatting Tests
        let driving = TravelRouteOption(mode: .driving, durationSeconds: 5400, distanceMeters: 120_000, routeName: "Via A1")
        expect(driving.durationFormatted == "1 hr 30 min", "5400s is 1 hr 30 min")
        expect(driving.distanceFormatted == "120.0 km", "120_000m is 120.0 km")

        let transit = TravelRouteOption(mode: .transit, durationSeconds: 2700, distanceMeters: 110_000, routeName: "TGV")
        expect(transit.durationFormatted == "45 min", "2700s is 45 min")

        let walking = TravelRouteOption(mode: .walking, durationSeconds: 86400, distanceMeters: 100_000)
        expect(walking.durationFormatted == "24 hr 0 min", "86400s is 24 hr 0 min")

        let result = TravelResult(
            originName: "Paris",
            destinationName: "Lyon",
            options: [driving, transit, walking],
            fastestMode: .transit
        )

        expect(result.fastestOption?.mode == .transit, "fastest option is transit")
        expect(result.summaryText == "Paris to Lyon: 45 min (110.0 km via Transit)", "summary text format")
        expect(result.directionsURL?.absoluteString.contains("saddr=Paris&daddr=Lyon") == true, "directions url")

        print("TravelTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }
}
