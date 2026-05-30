import Foundation
import CoreLocation
import Observation
import SwiftUI

// MARK: - Daily Weather Info

struct DailyWeatherInfo {

    let date: Date

    let symbolName: String
    let weatherCode: Int

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
    let hourly: OpenMeteoHourly
}

private struct OpenMeteoDaily: Decodable {

    let time: [String]

    let weather_code: [Int]

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

private struct OpenMeteoHourly: Decodable {

    let time: [String]

    let weather_code: [Int]
    let cloud_cover: [Int]
    let precipitation_probability: [Int]
    let precipitation: [Double]
}

    private(set) var weatherByDay: [Date: DailyWeatherInfo] = [:]

    private(set) var isAvailable: Bool = false
    private(set) var refreshID = UUID()

    private var lastRefresh: Date = .distantPast

    private let refreshInterval: TimeInterval = 1800

    private var retryCount = 0

    private init() {}

    // MARK: - Public

    func weather(for date: Date) -> DailyWeatherInfo? {

        guard showWeatherForecast else {
            return nil
        }

        let key = Calendar.current.startOfDay(for: date)

        let snapshot = weatherByDay

        guard var weather = snapshot[key] else {
            return nil
        }

        if Calendar.current.isDateInToday(date),
           let sunrise = weather.sunrise,
           let sunset = weather.sunset {

            let now = Date()

            let calendar = Calendar.current

            let currentHour = calendar.component(.hour, from: now)
            let sunriseHour = calendar.component(.hour, from: sunrise)
            let sunsetHour = calendar.component(.hour, from: sunset)

            let isDay = currentHour >= sunriseHour
                && currentHour < sunsetHour

            weather = DailyWeatherInfo(
                date: weather.date,
                symbolName: {

                    let generated = symbol(
                        for: weather.weatherCode,
                        cloudCover: weather.cloudCover,
                        precipitationChance: weather.precipitationChance,
                        precipitationAmount: weather.precipitationAmount,
                        windSpeed: weather.windSpeed,
                        isDay: isDay
                    )

                    guard !isDay else {
                        return generated
                    }

                    return generated
                        .replacingOccurrences(of: "sun.max", with: "moon.stars")
                        .replacingOccurrences(of: "cloud.sun", with: "cloud.moon")
                        .replacingOccurrences(of: "sun.haze", with: "moon.haze")
                }(),
                weatherCode: weather.weatherCode,
                minTemperature: weather.minTemperature,
                maxTemperature: weather.maxTemperature,
                precipitationChance: weather.precipitationChance,
                precipitationAmount: weather.precipitationAmount,
                windSpeed: weather.windSpeed,
                sunrise: weather.sunrise,
                sunset: weather.sunset,
                uvIndex: weather.uvIndex,
                airQualityIndex: weather.airQualityIndex,
                cloudCover: weather.cloudCover
            )
        }

        return weather
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

            guard retryCount < 3 else {
                isAvailable = false
                return
            }

            retryCount += 1

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

            retryCount = 0

            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude

            let urlString = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(latitude)&longitude=\(longitude)&daily=pm10_max&timezone=auto"

            let forecastURLString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset,uv_index_max,cloud_cover_mean&hourly=weather_code,cloud_cover,precipitation_probability,precipitation&forecast_days=7&timezone=auto"

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

            let localDateFormatter = DateFormatter()

            localDateFormatter.locale = Locale(identifier: "en_US_POSIX")

            localDateFormatter.timeZone = .current

            localDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

            for index in decoded.daily.time.indices {

                guard let date = formatter.date(from: decoded.daily.time[index]) else {
                    continue
                }

                let key = Calendar.current.startOfDay(for: date)

                let weatherCode = decoded.daily.weather_code[safe: index] ?? 0

                let daytimeCodes = hourlyWeatherCodes(
                    for: date,
                    hourly: decoded.hourly
                )

                let dominantWeatherCode = dominantDaytimeWeatherCode(
                    fallback: weatherCode,
                    hourlyCodes: daytimeCodes
                )

                let daytimePrecipitationChance = daytimePrecipitationProbability(
                    for: date,
                    hourly: decoded.hourly
                )

                let daytimePrecipitationAmount = daytimePrecipitationAmount(
                    for: date,
                    hourly: decoded.hourly
                )

                let precipitationChance = max(
                    Double(daytimePrecipitationChance),
                    decoded.daily.precipitation_probability_max[index] * 0.45
                )

                let precipitationAmount = max(
                    daytimePrecipitationAmount,
                    decoded.daily.precipitation_sum[index] * 0.35
                )

                let windSpeed = decoded.daily.wind_speed_10m_max[index]

                let uvIndex = decoded.daily.uv_index_max[index]

                let airQuality = index < pm10Values.count
                    ? pm10Values[index]
                    : nil

                let sunrise = localDateFormatter.date(
                    from: decoded.daily.sunrise[index]
                )

                let sunset = localDateFormatter.date(
                    from: decoded.daily.sunset[index]
                )

                let now = Date()

                let isCurrentlyDaytime: Bool

                if Calendar.current.isDateInToday(date),
                   let sunrise,
                   let sunset {

                    let currentHour = Calendar.current.component(.hour, from: now)
                    let sunriseHour = Calendar.current.component(.hour, from: sunrise)
                    let sunsetHour = Calendar.current.component(.hour, from: sunset)

                    isCurrentlyDaytime = currentHour >= sunriseHour
                        && currentHour < sunsetHour

                } else {

                    isCurrentlyDaytime = true
                }

                updated[key] = DailyWeatherInfo(
                    date: date,
                    symbolName: symbol(
                        for: dominantWeatherCode,
                        cloudCover: decoded.daily.cloud_cover_mean[index],
                        precipitationChance: Int(precipitationChance.rounded()),
                        precipitationAmount: precipitationAmount,
                        windSpeed: Int(windSpeed.rounded()),
                        isDay: isCurrentlyDaytime
                    ),
                    weatherCode: dominantWeatherCode,
                    minTemperature: Int(decoded.daily.temperature_2m_min[index].rounded()),
                    maxTemperature: Int(decoded.daily.temperature_2m_max[index].rounded()),
                    precipitationChance: Int(precipitationChance.rounded()),
                    precipitationAmount: precipitationAmount,
                    windSpeed: Int(windSpeed.rounded()),
                    sunrise: sunrise,
                    sunset: sunset,
                    uvIndex: uvIndex.map { Int($0.rounded()) },
                    airQualityIndex: airQuality.map { Int($0.rounded()) },
                    cloudCover: decoded.daily.cloud_cover_mean[index]
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
        precipitationChance: Int,
        precipitationAmount: Double,
        windSpeed: Int,
        isDay: Bool = true
    ) -> String {

        let condition = WeatherCondition(code: weatherCode)

        let clouds = max(0, min(cloudCover ?? 0, 100))

        let sunshineScore = max(
            0,
            115
            - clouds
            - Int(Double(precipitationChance) * 0.38)
            - Int(precipitationAmount * 3.2)
        )
        let severeWeatherCodes: Set<Int> = [63, 65, 81, 82, 95, 96, 99]

        let isSevereWeather = severeWeatherCodes.contains(weatherCode)

        // Strong rain
        if precipitationAmount >= 8 {
            return "cloud.heavyrain.fill"
        }

        // Real thunderstorms only
        if [95, 96, 99].contains(weatherCode) {

            if precipitationChance >= 80,
               precipitationAmount >= 8 {

                return "cloud.bolt.rain.fill"
            }

            return isDay
                ? "cloud.sun.rain.fill"
                : "cloud.moon.rain.fill"
        }


        // Pleasant / mostly dry days
        if sunshineScore >= 28,
           precipitationAmount < 2,
           precipitationChance < 72 {

            return isDay
                ? "cloud.sun.fill"
                : "cloud.moon.fill"
        }

        // Windy dry conditions
        if windSpeed >= 45,
           precipitationAmount < 1 {

            return "wind"
        }

        // Light precipitation should not dominate the whole day icon
        // Persistent drizzle / humid grey weather
        if precipitationAmount >= 0.3,
           precipitationAmount < 1.2,
           precipitationChance >= 55,
           clouds >= 70 {

            return "cloud.drizzle.fill"
        }

        // Ignore isolated weak showers during otherwise pleasant days
        if !isSevereWeather,
           sunshineScore >= 46,
           precipitationAmount < 2.2,
           precipitationChance < 72 {

            return isDay
                ? "cloud.sun.fill"
                : "cloud.moon.fill"
        }

        // Real scattered showers only if truly relevant
        if precipitationAmount >= 2.2,
           precipitationChance >= 68 {

            if sunshineScore >= 42 {

                return isDay
                    ? "cloud.sun.rain.fill"
                    : "cloud.moon.rain.fill"
            }

            return "cloud.rain.fill"
        }

        return condition.symbolName(
            isDay: isDay,
            cloudCover: cloudCover
        )
    }

    private func hourlyWeatherCodes(
        for date: Date,
        hourly: OpenMeteoHourly
    ) -> [Int] {

        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current

        let (startHour, endHour) = weatherEvaluationWindow(for: date)

    #if DEBUG
        print("🌤️ Weather code window: \(startHour)-\(endHour)")
    #endif

        return zip(hourly.time.indices, hourly.time)
            .compactMap { index, rawDate in

                guard let parsedDate = formatter.date(from: rawDate) else {
                    return nil
                }

                guard calendar.isDate(parsedDate, inSameDayAs: date) else {
                    return nil
                }

                let hour = calendar.component(.hour, from: parsedDate)

                guard (startHour...endHour).contains(hour) else {
                    return nil
                }

                return hourly.weather_code[safe: index]
            }
    }

    private func daytimePrecipitationProbability(
        for date: Date,
        hourly: OpenMeteoHourly
    ) -> Int {

        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current

        let (startHour, endHour) = weatherEvaluationWindow(for: date)

    #if DEBUG
        print("🌧️ Rain probability window: \(startHour)-\(endHour)")
    #endif

        let values = zip(hourly.time.indices, hourly.time)
            .compactMap { index, rawDate -> Int? in

                guard let parsedDate = formatter.date(from: rawDate) else {
                    return nil
                }

                guard calendar.isDate(parsedDate, inSameDayAs: date) else {
                    return nil
                }

                let hour = calendar.component(.hour, from: parsedDate)

                guard (startHour...endHour).contains(hour) else {
                    return nil
                }

                return hourly.precipitation_probability[safe: index]
            }

        guard !values.isEmpty else {
            return 0
        }

        let sorted = values.sorted()

        return sorted[sorted.count / 2]
    }

    private func daytimePrecipitationAmount(
        for date: Date,
        hourly: OpenMeteoHourly
    ) -> Double {

        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current

        let (startHour, endHour) = weatherEvaluationWindow(for: date)

    #if DEBUG
        print("🌦️ Rain amount window: \(startHour)-\(endHour)")
    #endif

        return zip(hourly.time.indices, hourly.time)
            .compactMap { index, rawDate -> Double? in

                guard let parsedDate = formatter.date(from: rawDate) else {
                    return nil
                }

                guard calendar.isDate(parsedDate, inSameDayAs: date) else {
                    return nil
                }

                let hour = calendar.component(.hour, from: parsedDate)

                guard (startHour...endHour).contains(hour) else {
                    return nil
                }

                return hourly.precipitation[safe: index]
            }
            .reduce(0, +) / 2.8
    }

    private func dominantDaytimeWeatherCode(
        fallback: Int,
        hourlyCodes: [Int]
    ) -> Int {

        guard !hourlyCodes.isEmpty else {
            return fallback
        }

        var weightedScores: [Int: Double] = [:]

        for code in hourlyCodes {

            let baseWeight: Double

            switch code {

            // Clear / pleasant
            case 0:
                baseWeight = 5.5

            case 1:
                baseWeight = 5.0

            case 2:
                baseWeight = 4.2

            // Overcast
            case 3:
                baseWeight = 2.4

            // Fog
            case 45, 48:
                baseWeight = 1.8

            // Drizzle
            case 51, 53, 55:
                baseWeight = 1.4

            // Light rain / isolated showers
            case 61, 80:
                baseWeight = 0.9

            // Moderate rain
            case 63, 81:
                baseWeight = 0.45

            // Heavy rain / violent showers
            case 65, 82:
                baseWeight = 0.15

            // Thunderstorm
            case 95, 96, 99:
                baseWeight = 0.08

            default:
                baseWeight = 1.0
            }

            weightedScores[code, default: 0] += baseWeight
        }

        // Strong sunshine bias
        let sunshineHours = hourlyCodes.filter {
            [0, 1, 2].contains($0)
        }.count

        if sunshineHours >= 5 {

            if sunshineHours >= 7 {
                return 0
            }

            return 1
        }

        return weightedScores
            .max(by: { $0.value < $1.value })?
            .key ?? fallback
    }
    
    
    private func weatherEvaluationWindow(
        for date: Date
    ) -> (startHour: Int, endHour: Int) {

        let calendar = Calendar.current

        guard calendar.isDateInToday(date) else {

            return (10, 17)
        }

        let currentHour = calendar.component(.hour, from: .now)

        switch currentHour {

        case ..<10:

            return (10, 17)

        case 10..<14:

            return (
                currentHour,
                min(currentHour + 7, 18)
            )

        case 14..<16:

            return (
                currentHour,
                min(currentHour + 5, 19)
            )

        case 16..<18:

            return (
                currentHour,
                min(currentHour + 4, 20)
            )

        case 18..<21:

            return (
                currentHour,
                21
            )

        default:

            return (
                currentHour,
                23
            )
        }
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

            case 0..<20:

                return isDay
                    ? "sun.max.fill"
                    : "moon.stars.fill"

            case 20..<85:

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

            case 0..<92:

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

            return isDay
                ? "cloud.sun.fill"
                : "cloud.moon.fill"

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

private extension Array {

    subscript(safe index: Int) -> Element? {

        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
