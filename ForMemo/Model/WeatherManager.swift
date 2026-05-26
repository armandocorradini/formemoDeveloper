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

            let forecastURLString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset,uv_index_max&timezone=auto"

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
                    symbolName: symbol(for: decoded.daily.weathercode[index]),
                    minTemperature: Int(decoded.daily.temperature_2m_min[index].rounded()),
                    maxTemperature: Int(decoded.daily.temperature_2m_max[index].rounded()),
                    precipitationChance: Int(precipitationChance.rounded()),
                    precipitationAmount: precipitationAmount,
                    windSpeed: Int(windSpeed.rounded()),
                    sunrise: sunrise,
                    sunset: sunset,
                    uvIndex: uvIndex.map { Int($0.rounded()) },
                    airQualityIndex: airQuality.map { Int($0.rounded()) },
                    morningSymbolName: symbol(for: decoded.daily.weathercode[index]),
                    afternoonSymbolName: symbol(for: decoded.daily.weathercode[index]),
                    eveningSymbolName: symbol(for: decoded.daily.weathercode[index])
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

    private func symbol(for weatherCode: Int) -> String {

        switch weatherCode {

        case 0:
            return "sun.max.fill"

        case 1, 2:
            return "cloud.sun.fill"

        case 3:
            return "cloud.fill"

        case 45, 48:
            return "cloud.fog.fill"

        case 51, 53, 55:
            return "cloud.drizzle.fill"

        case 61, 63, 65:
            return "cloud.rain.fill"

        case 71, 73, 75:
            return "snow"

        case 95, 96, 99:
            return "cloud.bolt.rain.fill"

        default:
            return "cloud.fill"
        }
    }
}
