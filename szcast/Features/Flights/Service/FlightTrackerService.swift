import Foundation
import Observation

@Observable
@MainActor
public final class FlightTrackerService {
    public static let shared = FlightTrackerService()

    public private(set) var activeResult: FlightResult?

    private var cache: [String: (result: FlightResult, timestamp: Date)] = [:]
    private var inFlightQueries: Set<String> = []
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    public func parseFlightCode(from rawQuery: String) -> String? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("flight ") {
            let rest = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            let normalized = rest.replacingOccurrences(of: " ", with: "").uppercased()
            if isPlausibleFlightDesignator(normalized) {
                return normalized
            }
        }

        let normalized = trimmed.replacingOccurrences(of: " ", with: "").uppercased()
        if isPlausibleFlightDesignator(normalized) {
            return normalized
        }

        return nil
    }

    private func isPlausibleFlightDesignator(_ code: String) -> Bool {
        // Needs 2-3 characters (airline code) followed by 1-4 digits
        guard code.count >= 3 && code.count <= 8 else { return false }
        // Exclude pure numbers, hex 0x..., or common units like 10km, 500g
        if code.hasPrefix("0X") { return false }
        let letters = code.prefix(while: { $0.isLetter })
        let digits = code.dropFirst(letters.count)
        guard letters.count >= 2 && letters.count <= 3 else {
            // Also supports IATA like 6E502 where airline code has digit (e.g. 6E)
            let prefix2 = code.prefix(2)
            let rest = code.dropFirst(2)
            if prefix2.contains(where: { $0.isNumber }) && prefix2.contains(where: { $0.isLetter }) && rest.allSatisfy({ $0.isNumber }) {
                return true
            }
            return false
        }
        guard !digits.isEmpty && digits.allSatisfy({ $0.isNumber }) else { return false }
        return true
    }

    public func resolveFlight(query: String) -> FlightResult? {
        guard let flightCode = parseFlightCode(from: query) else {
            activeResult = nil
            return nil
        }

        let key = flightCode.uppercased()
        if let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            activeResult = cached.result
            return cached.result
        }

        if !inFlightQueries.contains(key) {
            inFlightQueries.insert(key)
            Task {
                await fetchFlight(code: flightCode, key: key)
            }
        }

        return activeResult
    }

    private func fetchFlight(code: String, key: String) async {
        defer { inFlightQueries.remove(key) }

        // Mode A: Public FlightRadar24 search endpoint
        guard let url = URL(string: "https://www.flightradar24.com/v1/search/web/find?query=\(code)&limit=1") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first else {
                return
            }

            let detail = first["detail"] as? [String: Any]
            let flightNum = (first["label"] as? String) ?? code
            let airlineName = (detail?["operator"] as? String) ?? "Airline"

            let originDict = detail?["origin"] as? [String: Any]
            let destDict = detail?["destination"] as? [String: Any]

            let originCode = (originDict?["code"] as? String) ?? "DEP"
            let originCity = (originDict?["city"] as? String) ?? originCode

            let destCode = (destDict?["code"] as? String) ?? "ARR"
            let destCity = (destDict?["city"] as? String) ?? destCode

            let schedule = detail?["schedule"] as? [String: Any]
            let depTime = (schedule?["departure"] as? String) ?? "Scheduled"
            let arrTime = (schedule?["arrival"] as? String) ?? "Scheduled"

            let statusText = (detail?["status"] as? String) ?? "Active"
            let status: FlightStatus
            if statusText.localizedCaseInsensitiveContains("land") {
                status = .landed
            } else if statusText.localizedCaseInsensitiveContains("delay") {
                status = .delayed
            } else if statusText.localizedCaseInsensitiveContains("cancel") {
                status = .cancelled
            } else if statusText.localizedCaseInsensitiveContains("en route") || statusText.localizedCaseInsensitiveContains("air") {
                status = .active
            } else {
                status = .scheduled
            }

            let result = FlightResult(
                flightNumber: flightNum,
                airlineName: airlineName,
                departureAirport: originCode,
                departureCity: originCity,
                departureTime: depTime,
                arrivalAirport: destCode,
                arrivalCity: destCity,
                arrivalTime: arrTime,
                status: status,
                statusDetail: statusText,
                progressPercent: status == .active ? 0.5 : (status == .landed ? 1.0 : 0.0)
            )

            cache[key] = (result, Date())
            activeResult = result
        } catch {
            // Flight lookup failed or offline; gracefully no-op
        }
    }
}
