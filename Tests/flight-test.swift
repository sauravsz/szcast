import Foundation

@main
@MainActor
struct FlightTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        let service = FlightTrackerService.shared

        // Query Parsing Tests
        expect(service.parseFlightCode(from: "flight BA1444") == "BA1444", "flight BA1444 -> BA1444")
        expect(service.parseFlightCode(from: "flight ba 1444") == "BA1444", "flight ba 1444 -> BA1444")
        expect(service.parseFlightCode(from: "flight 6e5") == "6E5", "flight 6e5 -> 6E5")
        expect(service.parseFlightCode(from: "BA1444") == "BA1444", "bare BA1444 -> BA1444")
        expect(service.parseFlightCode(from: "AI101") == "AI101", "bare AI101 -> AI101")
        expect(service.parseFlightCode(from: "LH400") == "LH400", "bare LH400 -> LH400")

        // Rejections (hex numbers, words, math)
        expect(service.parseFlightCode(from: "0xFF") == nil, "0xFF rejected")
        expect(service.parseFlightCode(from: "10km") == nil, "10km rejected")
        expect(service.parseFlightCode(from: "hello") == nil, "hello rejected")
        expect(service.parseFlightCode(from: "2+2") == nil, "2+2 rejected")

        // FlightResult Tests
        let flight = FlightResult(
            flightNumber: "BA1444",
            airlineName: "British Airways",
            departureAirport: "LHR",
            departureCity: "London",
            departureTime: "14:15",
            departureTerminal: "T5",
            departureGate: "B32",
            arrivalAirport: "JFK",
            arrivalCity: "New York",
            arrivalTime: "17:30",
            status: .active,
            statusDetail: "En Route (+10m)",
            progressPercent: 0.65
        )

        expect(flight.flightNumber == "BA1444", "flight number matches")
        expect(flight.status == .active, "flight status is active")
        expect(flight.summaryText.contains("BA1444 (British Airways): LHR → JFK"), "summary format matches")

        print("FlightTests: \(passes) passed, \(failures) failed")
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
