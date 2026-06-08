import SwiftUI

struct WeatherForecastView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private let weatherManager = WeatherManager.shared

    let showsCloseButton: Bool
    var closeAction: (() -> Void)? = nil

    init(
        showsCloseButton: Bool = false,
        closeAction: (() -> Void)? = nil
    ) {
        self.showsCloseButton = showsCloseButton
        self.closeAction = closeAction
    }

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
                VStack(spacing: 10) {

                    if weatherManager.lastLoadFailed {

                        ContentUnavailableView {
                            Label(
                                String(localized: "Weather Unavailable"),
                                systemImage: "wifi.slash"
                            )
                        } description: {
                            Text(
                                String(localized: "Unable to load the weather forecast. Check your internet connection and try again.")
                            )
                        }
                        .padding(.top, 80)

                    } else {

                        weatherHeroHeader

                        forecastContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .contentMargins(.bottom, 70, for: .scrollContent)
        .navigationTitle("7 Days")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await weatherManager.refreshIfNeeded()
        }
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let closeAction {
                            closeAction()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    private var weatherHeroHeader: some View {
        return VStack(spacing: 4) {

            if weatherManager.weather(for: Date()) != nil {

                Image(systemName: currentWeatherSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 44))
                    .saturation(colorScheme == .light ? 1.25 : 1.0)
                    .brightness(colorScheme == .light ? 0.2 : 0.0)

                Text(weatherDescription(for: currentWeatherSymbol))
                    .font(.headline.weight(.regular))
                    .foregroundStyle(.primary)

                Text("Source: Open-Meteo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -20)
        .padding(.bottom, 8)
    }
    private var currentWeatherSymbol: String {
        weatherManager.representativeSymbol(for: Date())
    }

    private var forecastContent: some View {
        VStack(spacing: 8) {

            ForEach(nextDays, id: \.self) { date in

                let weather = weatherManager.weather(for: date)

                NavigationLink {
                    WeatherDayView(
                        date: date,
                        showsCloseButton: showsCloseButton,
                        cameFromForecast: true,
                        closeAction: closeAction
                    )
                } label: {

                    HStack(spacing: 16) {

                        VStack(alignment: .leading, spacing: 4) {

                            Text(dayTitle(for: date))
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Text(
                                Calendar.current.isDateInToday(date) ||
                                Calendar.current.isDateInTomorrow(date) ||
                                (
                                    Calendar.current.date(byAdding: .day, value: 2, to: Date())
                                        .map { Calendar.current.isDate(date, inSameDayAs: $0) }
                                    ?? false
                                )
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        }
                        .frame(width: 115, alignment: .leading)

                        if let weather {

                            let dayIcon = weatherManager.representativeSymbol(for: date)

                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("\(weather.minTemperature)°")
                                        .foregroundStyle(
                                            weather.minTemperature >= 35 ? .red :
                                            weather.minTemperature >= 30 ? .orange :
                                            weather.minTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                            .primary.opacity(0.75)
                                        )
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)

                                    Spacer()

                                    Text("\(weather.maxTemperature)°")
                                        .foregroundStyle(
                                            weather.maxTemperature >= 35 ? .red :
                                            weather.maxTemperature >= 30 ? .orange :
                                            weather.maxTemperature <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                                            .primary
                                        )
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .font(.subheadline)

                                ZStack(alignment: .center) {
                                    Rectangle()
                                        .frame(height: 2)
                                        .foregroundColor(.secondary.opacity(0.3))

                                    Circle()
                                        .fill(.primary)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .frame(width: 110, alignment: .center)
                            .frame(maxHeight: .infinity)

                            Image(systemName: dayIcon)
                                .symbolRenderingMode(.multicolor)
                                .font(.title3)
                                .saturation(colorScheme == .light ? 1.25 : 1.0)
                                .brightness(colorScheme == .light ? 0.2 : 0.0)
                                .frame(width: 40)

                        } else {

                            HStack {
                                Spacer()

                                if weatherManager.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "cloud.slash")
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.015 : 0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(colorScheme == .dark ? 0.30 : 1.00),
                                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.60),
                                                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.25)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.35
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(colorScheme == .dark ? 0.005 : 0.01),
                                                Color.clear,
                                                Color.clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .shadow(
                                color: .black.opacity(colorScheme == .dark ? 0.04 : 0.01),
                                radius: 14,
                                y: 5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nextDays: [Date] {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    private func weatherDescription(for symbolName: String) -> String {
        switch symbolName {
        case "sun.max.fill":
            return String(localized: "Sunny")
        case "cloud.sun.fill":
            return String(localized: "Partly Cloudy")
        case "cloud.fill":
            return String(localized: "Cloudy")
        case "cloud.heavyrain.fill":
            return String(localized: "Heavy Rain")
        case "cloud.snow.fill":
            return String(localized: "Snow")
        case "cloud.bolt.rain.fill":
            return String(localized: "Thunderstorm")
        default:
            return String(localized: "Variable Conditions")
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

        if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: Date()),
           calendar.isDate(date, inSameDayAs: dayAfterTomorrow) {
            return String(localized: "Day After Tomorrow")
        }

        return date.formatted(
            .dateTime
                .weekday(.wide)
        )
        .capitalized
    }
}
#Preview {
    NavigationStack {
        WeatherForecastView()
    }
}
