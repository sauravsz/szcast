import Foundation

public struct WeatherHourly: Equatable, Sendable {
    public let time: String
    public let temperature: Double
    public let symbol: String

    public init(time: String, temperature: Double, symbol: String) {
        self.time = time
        self.temperature = temperature
        self.symbol = symbol
    }
}

public struct WeatherResult: Equatable, Sendable {
    public let locationName: String
    public let currentTemp: Double
    public let apparentTemp: Double
    public let conditionText: String
    public let symbolName: String
    public let highTemp: Double
    public let lowTemp: Double
    public let humidity: Int
    public let windSpeed: Double
    public let hourly: [WeatherHourly]
    public var isFahrenheit: Bool

    public init(
        locationName: String,
        currentTemp: Double,
        apparentTemp: Double,
        conditionText: String,
        symbolName: String,
        highTemp: Double,
        lowTemp: Double,
        humidity: Int,
        windSpeed: Double,
        hourly: [WeatherHourly],
        isFahrenheit: Bool = false
    ) {
        self.locationName = locationName
        self.currentTemp = currentTemp
        self.apparentTemp = apparentTemp
        self.conditionText = conditionText
        self.symbolName = symbolName
        self.highTemp = highTemp
        self.lowTemp = lowTemp
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.hourly = hourly
        self.isFahrenheit = isFahrenheit
    }

    public func formatTemp(_ temp: Double) -> String {
        let val = isFahrenheit ? (temp * 9.0 / 5.0 + 32.0) : temp
        return "\(Int(val.rounded()))°\(isFahrenheit ? "F" : "C")"
    }

    public var summaryText: String {
        "\(locationName): \(conditionText), \(formatTemp(currentTemp)) (High: \(formatTemp(highTemp)), Low: \(formatTemp(lowTemp)))"
    }
}
