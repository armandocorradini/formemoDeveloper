import Foundation
import CoreLocation
import Observation
import SwiftUI

// MARK: - Daily Weather Info

struct DailyWeatherInfo {

    let date: Date

    let symbolName: String

    let minTemperature: Int
    let maxTemperature: Int

    let precipitationChance: Int
    let precipitationAmount: Double

    let windSpeed: Int

    let sunrise: Date?
    let sunset: Date?

    let uvIndex: Int?
    let airQualityIndex: Int?

    let cloudCover: Int?

    let morningSymbolName: String
    let afternoonSymbolName: String
    let eveningSymbolName: String
}

// MARK: - Weather Manager

@MainActor
@Observable
final class WeatherManager {

    static let shared = WeatherManager()

    @ObservationIgnored
    @AppStorage("showWeatherForecast")
    private var showWeatherForecast: Bool = true

// MARK: - Open Meteo Response

private struct OpenMeteoResponse: Decodable {

    let daily: OpenMeteoDaily
}

private struct OpenMeteoDaily: Decodable {

    let time: [String]

    let weathercode: [Int]

    let temperature_2m_min: [Double]
    let temperature_2m_max: [Double]

    let precipitation_probability_max: [Double]
    let precipitation_sum: [Double]

    let wind_speed_10m_max: [Double]

    let sunrise: [String]
    let sunset: [String]

    let uv_index_max: [Double?]
    let cloud_cover_mean: [Int]
    

}

    private(set) var weatherByDay: [Date: DailyWeatherInfo] = [:]

    private(set) var isAvailable: Bool = false
    private(set) var refreshID = UUID()

    private var lastRefresh: Date = .distantPast

    private let refreshInterval: TimeInterval = 1800

    private init() {}

    // MARK: - Public

    func weather(for date: Date) -> DailyWeatherInfo? {

        guard showWeatherForecast else {
            return nil
        }

        let key = Calendar.current.startOfDay(for: date)

        let snapshot = weatherByDay

        return snapshot[key]
    }

    func refreshIfNeeded() async {
#if DEBUG
        print("🌍 refreshIfNeeded called")
#endif
        guard showWeatherForecast else {
            weatherByDay = [:]
            refreshID = UUID()
            isAvailable = false
            return
        }
        guard Date().timeIntervalSince(lastRefresh) > refreshInterval else {
            return
        }

        await refresh()
    }

    func refresh() async {
#if DEBUG
        print("🌦️ refresh() entered")
#endif

        guard let location = LocationReminderManager.shared.currentLocation else {

#if DEBUG
            print("📍 No current location available for WeatherKit")
#endif

            // Request a fresh one-shot location for WeatherKit.
            // This reuses the existing location pipeline safely
            // without affecting geofence reminders.
            LocationReminderManager.shared.requestCurrentLocation()

            isAvailable = false

            // Retry automatically after CoreLocation has time
            // to deliver a fresh location update.
            Task {
                try? await Task.sleep(for: .seconds(2))
                await refresh()
            }

            return
        }

        do {

#if DEBUG
            print("🌦️ Weather refresh for: \(location.coordinate.latitude), \(location.coordinate.longitude)")
#endif

            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude

            let urlString = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(latitude)&longitude=\(longitude)&daily=pm10_max&timezone=auto"

            let forecastURLString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset,uv_index_max,cloud_cover_mean&timezone=auto"

            guard let url = URL(string: forecastURLString),
                  let airQualityURL = URL(string: urlString) else {
                isAvailable = false
                return
            }

            async let forecastResponse = URLSession.shared.data(from: url)
            async let airQualityResponse = URLSession.shared.data(from: airQualityURL)

            let (data, _) = try await forecastResponse
            let (airQualityData, _) = try await airQualityResponse

            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

            let airQualityDecoded = try JSONSerialization.jsonObject(with: airQualityData) as? [String: Any]

            let airQualityDaily = (airQualityDecoded?["daily"] as? [String: Any])

            let pm10Values = airQualityDaily?["pm10_max"] as? [Double?] ?? []

            var updated: [Date: DailyWeatherInfo] = [:]

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]

            for index in decoded.daily.time.indices {

                guard let date = formatter.date(from: decoded.daily.time[index]) else {
                    continue
                }

                let key = Calendar.current.startOfDay(for: date)

                let precipitationChance = decoded.daily.precipitation_probability_max[index]

                let precipitationAmount = decoded.daily.precipitation_sum[index]

                let windSpeed = decoded.daily.wind_speed_10m_max[index]

                let uvIndex = decoded.daily.uv_index_max[index]

                let airQuality = index < pm10Values.count
                    ? pm10Values[index]
                    : nil

                let sunrise = ISO8601DateFormatter().date(
                    from: decoded.daily.sunrise[index]
                )

                let sunset = ISO8601DateFormatter().date(
                    from: decoded.daily.sunset[index]
                )

                updated[key] = DailyWeatherInfo(
                    date: date,
                    symbolName: symbol(
                        for: decoded.daily.weathercode[index],
                        cloudCover: decoded.daily.cloud_cover_mean[index],
                        isDay: true
                    ),
                    minTemperature: Int(decoded.daily.temperature_2m_min[index].rounded()),
                    maxTemperature: Int(decoded.daily.temperature_2m_max[index].rounded()),
                    precipitationChance: Int(precipitationChance.rounded()),
                    precipitationAmount: precipitationAmount,
                    windSpeed: Int(windSpeed.rounded()),
                    sunrise: sunrise,
                    sunset: sunset,
                    uvIndex: uvIndex.map { Int($0.rounded()) },
                    airQualityIndex: airQuality.map { Int($0.rounded()) },
                    cloudCover: decoded.daily.cloud_cover_mean[index],
                    morningSymbolName: symbol(
                        for: decoded.daily.weathercode[index],
                        cloudCover: decoded.daily.cloud_cover_mean[index],
                        isDay: true
                    ),
                    afternoonSymbolName: symbol(
                        for: decoded.daily.weathercode[index],
                        cloudCover: decoded.daily.cloud_cover_mean[index],
                        isDay: true
                    ),
                    eveningSymbolName: symbol(
                        for: decoded.daily.weathercode[index],
                        cloudCover: decoded.daily.cloud_cover_mean[index],
                        isDay: false
                    )
                )
            }

            weatherByDay = updated
            refreshID = UUID()

#if DEBUG
            print("🌤️ Weather forecast loaded: \(updated.count) days")
#endif

            isAvailable = !updated.isEmpty
            lastRefresh = Date()

        } catch {

#if DEBUG
            print("❌ Open-Meteo fetch error:", error)
#endif

            refreshID = UUID()
            isAvailable = false
        }
    }

    // MARK: - Weather Symbol Mapping

    private func symbol(
        for weatherCode: Int,
        cloudCover: Int?,
        isDay: Bool = true
    ) -> String {

        let condition = WeatherCondition(code: weatherCode)

        return condition.symbolName(
            isDay: isDay,
            cloudCover: cloudCover
        )
    }
}

// MARK: - Weather Condition

enum WeatherCondition: Int, Sendable {

    // Clear / Clouds

    case clearSky = 0
    case mainlyClear = 1
    case partlyCloudy = 2
    case overcast = 3

    // Fog

    case fog = 45
    case depositingRimeFog = 48

    // Drizzle

    case drizzleLight = 51
    case drizzleModerate = 53
    case drizzleDense = 55

    // Freezing Drizzle

    case freezingDrizzleLight = 56
    case freezingDrizzleDense = 57

    // Rain

    case rainSlight = 61
    case rainModerate = 63
    case rainHeavy = 65

    // Freezing Rain

    case freezingRainLight = 66
    case freezingRainHeavy = 67

    // Snow

    case snowFallSlight = 71
    case snowFallModerate = 73
    case snowFallHeavy = 75
    case snowGrains = 77

    // Rain Showers

    case rainShowersSlight = 80
    case rainShowersModerate = 81
    case rainShowersViolent = 82

    // Snow Showers

    case snowShowersSlight = 85
    case snowShowersHeavy = 86

    // Thunderstorm

    case thunderstorm = 95
    case thunderstormHailSlight = 96
    case thunderstormHailHeavy = 99

    // Unknown

    case unknown = -1

    init(code: Int?) {

        guard let code else {
            self = .unknown
            return
        }

        self = Self(rawValue: code) ?? .unknown
    }
}

// MARK: - Symbol Mapping

extension WeatherCondition {

    nonisolated
    func symbolName(
        isDay: Bool,
        cloudCover: Int? = nil
    ) -> String {

        let clouds = max(0, min(cloudCover ?? 0, 100))

        switch self {

        // =====================================================
        // Thunderstorm
        // =====================================================

        case .thunderstorm,
             .thunderstormHailSlight,
             .thunderstormHailHeavy:

            return "cloud.bolt.rain.fill"

        // =====================================================
        // Snow
        // =====================================================

        case .snowFallSlight,
             .snowFallModerate,
             .snowFallHeavy,
             .snowGrains,
             .snowShowersSlight,
             .snowShowersHeavy:

            return "cloud.snow.fill"

        // =====================================================
        // Heavy Rain
        // =====================================================

        case .rainHeavy,
             .freezingRainHeavy,
             .rainShowersViolent:

            return "cloud.heavyrain.fill"

        // =====================================================
        // Moderate Rain
        // =====================================================

        case .rainModerate,
             .freezingRainLight,
             .rainShowersModerate:

            return isDay
                ? "cloud.sun.rain.fill"
                : "cloud.moon.rain.fill"

        // =====================================================
        // Light Rain / Drizzle
        // =====================================================

        case .rainSlight,
             .rainShowersSlight,
             .drizzleLight,
             .drizzleModerate:

            if clouds < 55 {

                return isDay
                    ? "cloud.sun.rain.fill"
                    : "cloud.moon.rain.fill"
            }

            return "cloud.drizzle.fill"

        // =====================================================
        // Dense / Freezing Drizzle
        // =====================================================

        case .drizzleDense,
             .freezingDrizzleLight,
             .freezingDrizzleDense:

            return "cloud.sleet.fill"

        // =====================================================
        // Fog
        // =====================================================

        case .fog,
             .depositingRimeFog:

            return "cloud.fog.fill"

        // =====================================================
        // Clear Sky
        // =====================================================

        case .clearSky:

            switch clouds {

            case 0..<12:

                return isDay
                    ? "sun.max.fill"
                    : "moon.stars.fill"

            case 12..<58:

                return isDay
                    ? "cloud.sun.fill"
                    : "cloud.moon.fill"

            case 58..<88:

                return isDay
                    ? "cloud.sun.fill"
                    : "cloud.moon.fill"

            default:

                return "cloud.fill"
            }

        // =====================================================
        // Mainly Clear
        // =====================================================

        case .mainlyClear:

            switch clouds {

            case 0..<82:

                return isDay
                    ? "cloud.sun.fill"
                    : "cloud.moon.fill"

            default:

                return "cloud.fill"
            }

        // =====================================================
        // Partly Cloudy
        // =====================================================

        case .partlyCloudy:

            switch clouds {

            case 0..<90:

                return isDay
                    ? "cloud.sun.fill"
                    : "cloud.moon.fill"

            default:

                return "cloud.fill"
            }

        // =====================================================
        // Overcast
        // =====================================================

        case .overcast:

            return "cloud.fill"

        // =====================================================
        // Unknown
        // =====================================================

        case .unknown:

            return isDay
                ? "cloud.sun.fill"
                : "cloud.moon.fill"
        }
    }
}
