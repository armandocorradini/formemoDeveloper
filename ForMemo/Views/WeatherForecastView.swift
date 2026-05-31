import SwiftUI

struct WeatherForecastView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.colorScheme)
    private var colorScheme

    private let weatherManager = WeatherManager.shared

    var body: some View {

        ZStack {
                LinearGradient(
                    colors: [backColor1, backColor2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                ScrollView {

                    VStack(spacing: 14) {

                        forecastHeader
                        forecastCards
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .topBarTrailing) {

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                    }
                }
            }
    }

    // MARK: - Header

    private var forecastHeader: some View {

        VStack(spacing: 4) {

            ZStack {

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.28),
                                        Color.white.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )

                Image(systemName: headerWeatherSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 23, weight: .medium))
            }

            Text("Weekly Forecast")
                .font(.headline.weight(.bold))

            Label("Source: Open-Meteo", systemImage: "network")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(
                color: .black.opacity(0.18),
                radius: 12,
                y: 6
            )
        )
    }

    // MARK: - Forecast Cards

    private var forecastCards: some View {

        VStack(spacing: 8) {

            ForEach(nextDays, id: \.self) { date in

                forecastRow(for: date)
            }
        }
    }

    @ViewBuilder
    private func forecastRow(for date: Date) -> some View {

        let weather = weatherManager.weather(for: date)

        HStack(alignment: .top, spacing: 12) {

            VStack(alignment: .leading, spacing: 8) {

                HStack(alignment: .center, spacing: 10) {

                    VStack(alignment: .leading, spacing: 1) {

                        Text(dayTitle(for: date))
                            .font(.subheadline.weight(.bold))

                        Text(
                            date.formatted(
                                .dateTime
                                    .day()
                                    .month(.abbreviated)
                            )
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 32, alignment: .center)

                    Spacer(minLength: 0)

                    if let weather {

                        HStack(alignment: .center, spacing: 4) {

                            Text(weatherDescription(for: weather.symbolName))
                                .font(.callout.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 110, alignment: .trailing)

                            Image(systemName: weather.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 23, weight: .medium))
                                .offset(y: -1)
                        }
                    }
                }
                .frame(minHeight: 32, alignment: .center)

                if let weather {

                    HStack(alignment: .center, spacing: 14) {

                        Label(
                            "\(weather.minTemperature)°",
                            systemImage: "thermometer.low"
                        )
                        .font(.callout.weight(.medium))

                        Label(
                            "\(weather.maxTemperature)°",
                            systemImage: "thermometer.high"
                        )
                        .font(.callout.weight(.medium))

                        Spacer(minLength: 0)

                        HStack(alignment: .center, spacing: 10) {

                            Label(
                                (Double(weather.precipitationChance) / 100)
                                    .formatted(
                                        .percent
                                            .precision(.fractionLength(0))
                                    ),
                                systemImage: "cloud.rain"
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                            Label(
                                "\(weather.windSpeed) km/h",
                                systemImage: "wind"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(windColor(for: weather.windSpeed))
                        }
                    }
                    .frame(height: 24, alignment: .center)

                    HStack(spacing: 14) {

                        if let sunrise = weather.sunrise {

                            Label(
                                sunrise.formatted(
                                    .dateTime
                                        .hour()
                                        .minute()
                                ),
                                systemImage: "sunrise.fill"
                            )
                            .font(.caption)
                        }

                        if let sunset = weather.sunset {

                            Label(
                                sunset.formatted(
                                    .dateTime
                                        .hour()
                                        .minute()
                                ),
                                systemImage: "sunset.fill"
                            )
                            .font(.caption)
                        }

                        Spacer(minLength: 0)

                        if let uvIndex = weather.uvIndex {

                            Label(
                                "UV \(uvIndex)",
                                systemImage: "sun.max"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(uvColor(for: uvIndex))
                        }

                        if let airQuality = weather.airQualityIndex {

                            Label(
                                "AQI \(airQuality)",
                                systemImage: "aqi.medium"
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(aqiColor(for: airQuality))
                        }
                    }
                    .foregroundStyle(.primary.opacity(0.72))
                }
            }

            if weather == nil {

                Spacer(minLength: 0)

                ProgressView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                        ? [
                            Color.black.opacity(0.22),
                            Color.black.opacity(0.08)
                        ]
                        : [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(
                color: colorScheme == .dark
                ? .black.opacity(0.16)
                : .black.opacity(0.06),
                radius: 14,
                y: 8
            )
        )
    }

    // Removed the entire dayMomentView helper as requested

    private func weatherDescription(for symbol: String) -> String {

        switch symbol {

        case "sun.max.fill":
            return String(localized: "Sunny")

        case "moon.stars.fill":
            return String(localized: "Clear Night")

        case "cloud.sun.fill":
            return String(localized: "Partly Cloudy")

        case "cloud.moon.fill":
            return String(localized: "Partly Cloudy Night")

        case "cloud.fill":
            return String(localized: "Cloudy")

        case "cloud.drizzle.fill":
            return String(localized: "Drizzle")

        case "cloud.sun.rain.fill":
            return String(localized: "Scattered Showers")

        case "cloud.moon.rain.fill":
            return String(localized: "Night Showers")

        case "cloud.heavyrain.fill":
            return String(localized: "Heavy Rain")

        case "cloud.sleet.fill":
            return String(localized: "Sleet")

        case "cloud.snow.fill":
            return String(localized: "Snow")

        case "cloud.fog.fill":
            return String(localized: "Fog")

        case "cloud.bolt.rain.fill":
            return String(localized: "Thunderstorm")

        default:
            return String(localized: "Variable Conditions")
        }
    }

    private func windColor(for speed: Int) -> Color {

        switch speed {
        case 0..<20:
            return .secondary

        case 20..<35:
            return .orange

        default:
            return .red
        }
    }

    private func uvColor(for index: Int) -> Color {

        switch index {
        case 0..<3:
            return .yellow

        case 3..<6:
            return .orange

        default:
            return .red
        }
    }

    private func aqiColor(for index: Int) -> Color {

        switch index {
        case 0..<50:
            return .green

        case 50..<100:
            return .yellow

        case 100..<150:
            return .orange

        default:
            return .red
        }
    }

    // MARK: - Helpers

    private var nextDays: [Date] {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    private func dayTitle(for date: Date) -> String {

        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return String(localized: "Today")
        }

        if calendar.isDateInTomorrow(date) {
            return String(localized: "Tomorrow")
        }

        return date.formatted(
            .dateTime
                .weekday(.wide)
        )
        .capitalized
    }
}

private var headerWeatherSymbol: String {

    let now = Date()
    let hour = Calendar.current.component(.hour, from: now)

    return (hour >= 20 || hour < 6)
        ? "cloud.moon.fill"
        : "cloud.sun.fill"
}

#Preview {

    WeatherForecastView()
}
