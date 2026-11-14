import Foundation
import Observation

@Observable
@MainActor
public final class WeatherService {
    public static let shared = WeatherService()

    public private(set) var activeResult: WeatherResult?
    public var useFahrenheit: Bool = false {
        didSet {
            if var current = activeResult {
                current.isFahrenheit = useFahrenheit
                activeResult = current
            }
        }
    }

    private var cache: [String: (result: WeatherResult, timestamp: Date)] = [:]
    private var inFlightQueries: Set<String> = []
    private let cacheTTL: TimeInterval = 900 // 15 minutes

    public func parseLocation(from rawQuery: String) -> String? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 3 else { return nil }

        let prefixes = [
            "weather in ", "weather for ", "weather at ", "weather of ", "weather ",
            "temperature in ", "temperature for ", "temperature at ", "temperature of ", "temp in ", "temp for ",
            "forecast in ", "forecast for ", "forecast at "
        ]

        for prefix in prefixes {
            if trimmed.hasPrefix(prefix) {
                let loc = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                if !loc.isEmpty && !loc.contains(" to ") && !loc.contains(" from ") {
                    return loc
                }
            }
        }

        let suffixes = [" weather", " temperature", " forecast"]
        for suffix in suffixes {
            if trimmed.hasSuffix(suffix) {
                let loc = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
                if !loc.isEmpty && !loc.contains(" to ") && !loc.contains(" from ") {
                    return loc
                }
            }
        }

        return nil
    }

    public func resolveWeather(query: String) -> WeatherResult? {
        guard let location = parseLocation(from: query) else {
            activeResult = nil
            return nil
        }

        let key = location.lowercased()
        if let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            var res = cached.result
            res.isFahrenheit = useFahrenheit
            activeResult = res
            return res
        }

        if !inFlightQueries.contains(key) {
            inFlightQueries.insert(key)
            Task {
                await fetchWeather(for: location, key: key)
            }
        }

        return activeResult
    }

    private func fetchWeather(for location: String, key: String) async {
        defer { inFlightQueries.remove(key) }

        guard let encodedName = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encodedName)&count=1") else {
            return
        }

        do {
            let (geoData, _) = try await URLSession.shared.data(from: geoURL)
            guard let geoJson = try JSONSerialization.jsonObject(with: geoData) as? [String: Any],
                  let results = geoJson["results"] as? [[String: Any]],
                  let first = results.first,
                  let lat = first["latitude"] as? Double,
                  let lon = first["longitude"] as? Double else {
                return
            }

            let cityName = (first["name"] as? String) ?? location.capitalized
            let country = (first["country_code"] as? String) ?? ""
            let displayName = country.isEmpty ? cityName : "\(cityName), \(country)"

            let forecastURLString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&hourly=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto"

            guard let forecastURL = URL(string: forecastURLString) else { return }
            let (forecastData, _) = try await URLSession.shared.data(from: forecastURL)
            guard let forecastJson = try JSONSerialization.jsonObject(with: forecastData) as? [String: Any],
                  let current = forecastJson["current"] as? [String: Any],
                  let currentTemp = current["temperature_2m"] as? Double else {
                return
            }
            let apparentTemp = (current["apparent_temperature"] as? Double) ?? currentTemp
            let weatherCode = (current["weather_code"] as? Int) ?? 0
            let humidity = (current["relative_humidity_2m"] as? Int) ?? 0
            let windSpeed = (current["wind_speed_10m"] as? Double) ?? 0.0

            var highTemp = currentTemp
            var lowTemp = currentTemp
            if let daily = forecastJson["daily"] as? [String: Any],
               let highs = daily["temperature_2m_max"] as? [Double],
               let lows = daily["temperature_2m_min"] as? [Double] {
                highTemp = highs.first ?? currentTemp
                lowTemp = lows.first ?? currentTemp
            }

            var hourlyForecasts: [WeatherHourly] = []
            if let hourly = forecastJson["hourly"] as? [String: Any],
               let times = hourly["time"] as? [String],
               let temps = hourly["temperature_2m"] as? [Double],
               let codes = hourly["weather_code"] as? [Int] {
                let count = min(times.count, min(temps.count, codes.count))
                // Take next 5 slots
                let takeCount = min(5, count)
                for i in 0..<takeCount {
                    let timeStr = times[i]
                    let hourPart = timeStr.split(separator: "T").last.map(String.init) ?? "+\(i + 1)h"
                    let shortHour = String(hourPart.prefix(5))
                    let symbol = weatherCodeToSymbol(codes[i])
                    hourlyForecasts.append(WeatherHourly(time: shortHour, temperature: temps[i], symbol: symbol))
                }
            }

            let (condition, symbol) = Self.weatherCodeInfo(weatherCode)

            let result = WeatherResult(
                locationName: displayName,
                currentTemp: currentTemp,
                apparentTemp: apparentTemp,
                conditionText: condition,
                symbolName: symbol,
                highTemp: highTemp,
                lowTemp: lowTemp,
                humidity: humidity,
                windSpeed: windSpeed,
                hourly: hourlyForecasts,
                isFahrenheit: useFahrenheit
            )

            cache[key] = (result, Date())
            activeResult = result
        } catch {
            // Network failure or timeout; do not block user typing
        }
    }

    public static func weatherCodeInfo(_ code: Int) -> (condition: String, symbol: String) {
        switch code {
        case 0:
            return ("Clear Sky", "sun.max.fill")
        case 1:
            return ("Mainly Clear", "sun.max.fill")
        case 2:
            return ("Partly Cloudy", "cloud.sun.fill")
        case 3:
            return ("Overcast", "cloud.fill")
        case 45, 48:
            return ("Fog", "cloud.fog.fill")
        case 51, 53, 55:
            return ("Drizzle", "cloud.drizzle.fill")
        case 56, 57:
            return ("Freezing Drizzle", "cloud.sleet.fill")
        case 61, 63, 65:
            return ("Rain", "cloud.rain.fill")
        case 66, 67:
            return ("Freezing Rain", "cloud.sleet.fill")
        case 71, 73, 75, 77:
            return ("Snow", "cloud.snow.fill")
        case 80, 81, 82:
            return ("Rain Showers", "cloud.heavyrain.fill")
        case 85, 86:
            return ("Snow Showers", "cloud.snow.fill")
        case 95:
            return ("Thunderstorm", "cloud.bolt.fill")
        case 96, 99:
            return ("Hail Thunderstorm", "cloud.bolt.rain.fill")
        default:
            return ("Fair", "cloud.sun.fill")
        }
    }

    private func weatherCodeToSymbol(_ code: Int) -> String {
        Self.weatherCodeInfo(code).symbol
    }
}
