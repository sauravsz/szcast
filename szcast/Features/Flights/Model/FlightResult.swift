import Foundation

public enum FlightStatus: String, Equatable, Sendable {
    case scheduled = "Scheduled"
    case active = "En Route"
    case landed = "Landed"
    case delayed = "Delayed"
    case cancelled = "Cancelled"
    case unknown = "Active"
}

public struct FlightResult: Equatable, Sendable {
    public let flightNumber: String
    public let airlineName: String
    public let departureAirport: String
    public let departureCity: String
    public let departureTime: String
    public let departureTerminal: String?
    public let departureGate: String?

    public let arrivalAirport: String
    public let arrivalCity: String
    public let arrivalTime: String
    public let arrivalTerminal: String?
    public let arrivalGate: String?

    public let status: FlightStatus
    public let statusDetail: String?
    public let progressPercent: Double?

    public init(
        flightNumber: String,
        airlineName: String,
        departureAirport: String,
        departureCity: String,
        departureTime: String,
        departureTerminal: String? = nil,
        departureGate: String? = nil,
        arrivalAirport: String,
        arrivalCity: String,
        arrivalTime: String,
        arrivalTerminal: String? = nil,
        arrivalGate: String? = nil,
        status: FlightStatus,
        statusDetail: String? = nil,
        progressPercent: Double? = nil
    ) {
        self.flightNumber = flightNumber
        self.airlineName = airlineName
        self.departureAirport = departureAirport
        self.departureCity = departureCity
        self.departureTime = departureTime
        self.departureTerminal = departureTerminal
        self.departureGate = departureGate
        self.arrivalAirport = arrivalAirport
        self.arrivalCity = arrivalCity
        self.arrivalTime = arrivalTime
        self.arrivalTerminal = arrivalTerminal
        self.arrivalGate = arrivalGate
        self.status = status
        self.statusDetail = statusDetail
        self.progressPercent = progressPercent
    }

    public var summaryText: String {
        "\(flightNumber) (\(airlineName)): \(departureAirport) → \(arrivalAirport), \(status.rawValue) (\(statusDetail ?? departureTime))"
    }
}
