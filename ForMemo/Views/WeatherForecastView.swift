import SwiftUI

struct WeatherForecastView: View {
    @Environment(\.dismiss)
    private var dismiss

    let showsCloseButton: Bool

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }


    @Environment(\.colorScheme)
    private var colorScheme

private let weatherManager = WeatherManager.shared

@State private var showUnavailableMessage = false

    var body: some View {

        let _ = weatherManager.refreshID
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
            .navigationTitle("Weekly Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 70, for: .scrollContent)
            .toolbar {
                if showsCloseButton {
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
            .onAppear {

                showUnavailableMessage = false

                Task {

                    await weatherManager.refreshIfNeeded()

                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        let hasForecast = nextDays.contains {
                            weatherManager.weather(for: $0) != nil
                        }
                        showUnavailableMessage = !hasForecast
                    }
                }
            }
    }

    // MARK: - Header

    private var forecastHeader: some View {
        VStack(spacing: 4) {
//            Text("Weekly Forecast")
//                .font(.headline.weight(.bold))
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
            .fill(
                colorScheme == .dark
                ? Color(red: 0.08, green: 0.09, blue: 0.12)
                : Color.white.opacity(0.84)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.white.opacity(0.35),
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
                            colorScheme == .dark ? Color.white.opacity(0.30) : Color.white.opacity(0.65),
                            colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.20),
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

        let hasForecast = nextDays.contains {
            weatherManager.weather(for: $0) != nil
        }

        return VStack(spacing: 8) {

            if !hasForecast {

                if showUnavailableMessage {

                    ContentUnavailableView(
                        String(localized: "Weather Unavailable"),
                        systemImage: "wifi.slash",
                        description: Text(
                            String(localized: "Unable to load the weather forecast. Check your internet connection and try again.")
                        )
                    )
                    .padding(.top, 40)

                } else {

                    VStack(spacing: 12) {

                        ProgressView()

                        Text(String(localized: "Loading Forecast..."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                }

            } else {

                ForEach(nextDays, id: \.self) { date in
                    forecastRow(for: date)
                }
            }
        }
    }

    @ViewBuilder
    private func forecastRow(for date: Date) -> some View {

        let weather = weatherManager.weather(for: date)
        let hourlyForecast = weatherManager.hourlyWeather(for: date)

        HStack(alignment: .top, spacing: 12) {

            VStack(alignment: .leading, spacing: 8) {

                HStack(alignment: .center, spacing: 10) {

                    VStack(alignment: .leading, spacing: 1) {

                        Text(dayTitle(for: date))
                            .font(.subheadline.weight(.bold))

                        Text(
                            Calendar.current.isDateInToday(date) ||
                            Calendar.current.isDateInTomorrow(date)
                            ? date.formatted(
                                .dateTime
                                    .weekday(.abbreviated)
                                    .day()
                                    .month(.abbreviated)
                            )
                            : date.formatted(
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

                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.blue.opacity(colorScheme == .dark ? 0.55 : 0.65),
                                                Color.indigo.opacity(colorScheme == .dark ? 0.35 : 0.45)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 44, height: 44)

                                Image(systemName: weather.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 20, weight: .medium))
                            }
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

                    if !hourlyForecast.isEmpty {

                        Rectangle()
                            .fill(.secondary.opacity(0.30))
                            .frame(height: 0.5)
                            .padding(.vertical, 4)

                        HStack(spacing: 0) {

                            ForEach(hourlyForecast, id: \.date) { item in

                                let currentHour = Calendar.current.component(.hour, from: Date())
                                let nextForecastHour = hourlyForecast.first(where: { $0.hour >= currentHour })?.hour
                                let highlightHour = Calendar.current.isDateInToday(date)
                                    ? nextForecastHour
                                    : nil

                                VStack(spacing: 2) {

                                    Image(systemName: item.symbolName)
                                        .symbolRenderingMode(.multicolor)
                                        .font(.caption2)

                                    Text("\(item.hour)")
                                        .font(
                                            .system(
                                                size: 9,
                                                weight: highlightHour == item.hour
                                                    ? .bold
                                                    : .medium
                                            )
                                        )
                                        .foregroundStyle(.white)
                                        .overlay(alignment: .bottom) {
                                            if highlightHour == item.hour {
                                                Capsule()
                                                    .fill(.white)
                                                    .frame(width: 10, height: 2)
                                                    .offset(y: 6)
                                            }
                                        }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                            .fill(
                                colorScheme == .light
                                ? Color.black.opacity(0.55)
                                : Color.clear
                            )
                        )
//                        .background(
//                            RoundedRectangle(cornerRadius: 14, style: .continuous)
//                                .fill(
//                                    LinearGradient(
//                                        colors: [
//                                            Color(red: 0.03, green: 0.08, blue: 0.22),
//                                            Color(red: 0.06, green: 0.14, blue: 0.34),
//                                            Color(red: 0.10, green: 0.22, blue: 0.50),
//                                            Color(red: 0.14, green: 0.30, blue: 0.64),
//                                            Color(red: 0.18, green: 0.36, blue: 0.75),
//                                            Color(red: 0.24, green: 0.46, blue: 0.88),
//                                            Color(red: 0.18, green: 0.36, blue: 0.75),
//                                            Color(red: 0.14, green: 0.30, blue: 0.64),
//                                            Color(red: 0.10, green: 0.22, blue: 0.50),
//                                            Color(red: 0.06, green: 0.14, blue: 0.34),
//                                            Color(red: 0.03, green: 0.08, blue: 0.22)
//                                        ],
//                                        startPoint: .leading,
//                                        endPoint: .trailing
//                                    )
//                                )
//                        )
                        .padding(.top, 2)
                    }
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
            .fill(
                Color(.systemBackground).opacity(
                    colorScheme == .dark ? 0.22 : 0.26
                )
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
