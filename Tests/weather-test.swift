import Foundation

@main
@MainActor
struct WeatherTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        let service = WeatherService.shared

        // Query Parsing Tests
        expect(service.parseLocation(from: "weather in Paris") == "paris", "weather in Paris -> paris")
        expect(service.parseLocation(from: "temperature in Tokyo") == "tokyo", "temperature in Tokyo -> tokyo")
        expect(service.parseLocation(from: "forecast for New York") == "new york", "forecast for New York -> new york")
        expect(service.parseLocation(from: "London weather") == "london", "London weather -> london")
        expect(service.parseLocation(from: "Tokyo forecast") == "tokyo", "Tokyo forecast -> tokyo")
        expect(service.parseLocation(from: "weather here") == "here", "weather here -> here")
        expect(service.parseLocation(from: "weather now") == "now", "weather now -> now")

        // Non-weather queries must be rejected
        expect(service.parseLocation(from: "10 km to miles") == nil, "10 km to miles is not weather")
        expect(service.parseLocation(from: "time from Paris to Lyon") == nil, "travel query is not weather")
        expect(service.parseLocation(from: "hi") == nil, "hi is not weather")

        // WMO Code Tests
        let clear = WeatherService.weatherCodeInfo(0)
        expect(clear.condition == "Clear Sky" && clear.symbol == "sun.max.fill", "code 0 is clear sky")

        let rain = WeatherService.weatherCodeInfo(61)
        expect(rain.condition == "Rain" && rain.symbol == "cloud.rain.fill", "code 61 is rain")

        let thunder = WeatherService.weatherCodeInfo(95)
        expect(thunder.condition == "Thunderstorm" && thunder.symbol == "cloud.bolt.fill", "code 95 is thunderstorm")

        // WeatherResult Formatting Tests
        var result = WeatherResult(
            locationName: "Paris, FR",
            currentTemp: 18.4,
            apparentTemp: 17.2,
            conditionText: "Partly Cloudy",
            symbolName: "cloud.sun.fill",
            highTemp: 22.0,
            lowTemp: 13.0,
            humidity: 65,
            windSpeed: 12.0,
            hourly: [
                WeatherHourly(time: "14:00", temperature: 18.0, symbol: "cloud.sun.fill"),
                WeatherHourly(time: "15:00", temperature: 19.0, symbol: "cloud.sun.fill")
            ],
            isFahrenheit: false
        )

        expect(result.formatTemp(result.currentTemp) == "18°C", "current temp in celsius is 18°C")
        expect(result.summaryText == "Paris, FR: Partly Cloudy, 18°C (High: 22°C, Low: 13°C)", "celsius summary")

        result.isFahrenheit = true
        expect(result.formatTemp(result.currentTemp) == "65°F", "current temp in fahrenheit is 65°F")
        expect(result.summaryText == "Paris, FR: Partly Cloudy, 65°F (High: 72°F, Low: 55°F)", "fahrenheit summary")

        print("WeatherTests: \(passes) passed, \(failures) failed")
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
