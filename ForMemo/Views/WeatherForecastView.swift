import SwiftUI

struct WeatherForecastView: View {

    @Environment(\.dismiss)
    private var dismiss

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

                    VStack(spacing: 18) {

                        forecastHeader
                        forecastCards
                    }
                    .padding()
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

        VStack(spacing: 8) {

            ZStack {

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.06),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )

                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 2) {

                Text("Weekly Forecast")
                    .font(.title2.bold())

                Label("Source: Open-Meteo", systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Real-time weather forecast for the next 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(
                cornerRadius: 34,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(
                    cornerRadius: 34,
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
                    cornerRadius: 34,
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
                radius: 18,
                y: 10
            )
        )
    }

    // MARK: - Forecast Cards

    private var forecastCards: some View {

        VStack(spacing: 6) {

            ForEach(nextDays, id: \.self) { date in

                forecastRow(for: date)
            }
        }
    }

    @ViewBuilder
    private func forecastRow(for date: Date) -> some View {

        let weather = weatherManager.weather(for: date)

        HStack(alignment: .top, spacing: 18) {

            VStack(alignment: .leading, spacing: 0) {

                Text(dayTitle(for: date))
                    .font(.subheadline.weight(.semibold))
                    .frame(height: 24)

                Text(
                    date.formatted(
                        .dateTime
                            .day()
                            .month(.abbreviated)
                    )
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 24, alignment: .center)

                if let weather {

                    HStack(spacing: 14) {

                        Label(
                            "\(weather.minTemperature)°",
                            systemImage: "thermometer.low"
                        )

                        Label(
                            "\(weather.maxTemperature)°",
                            systemImage: "thermometer.high"
                        )
                    }
                    .frame(height: 24, alignment: .center)
                }
            }

            Spacer(minLength: 0)

            if let weather {

                VStack(alignment: .trailing, spacing: 0) {

                    HStack(alignment: .center, spacing: 10) {

                        Spacer(minLength: 0)

                        Text(weatherDescription(for: weather.symbolName))
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.trailing)

                        Image(systemName: weather.symbolName)
                            .font(.system(size: 22))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)

                    HStack(alignment: .center, spacing: 14) {

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
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: 24)

                    HStack(alignment: .center, spacing: 14) {

//                        if let uvIndex = weather.uvIndex {
//
//                            Text("UV \(uvIndex)")
//                                .font(.caption.weight(.semibold))
//                                .foregroundStyle(uvColor(for: uvIndex))
//                        }
               

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
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    HStack(spacing: 18) {

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
                            .foregroundStyle(.mint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

            } else {

                ProgressView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(
                    cornerRadius: 30,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.22),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 30,
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
                color: .black.opacity(0.16),
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

        case "cloud.sun.fill":
            return String(localized: "Partly Cloudy")

        case "cloud.fill":
            return String(localized: "Cloudy")

        case "cloud.rain.fill":
            return String(localized: "Rain")

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
    }
}

#Preview {

    WeatherForecastView()
}
