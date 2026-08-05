import SwiftUI

struct WeatherDayView: View {

    let date: Date
    var showsCloseButton: Bool = false
    var cameFromForecast: Bool = false
    var closeAction: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let weatherManager = WeatherManager.shared
    @State private var forceRefresh = UUID()

    var body: some View {

        let _ = weatherManager.refreshID
        let _ = forceRefresh

        ZStack {
            AppGlassBackground()

            ScrollView {

                VStack(spacing: 12) {

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
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)

                    } else {

                        heroCard

                        hourlySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .contentMargins(.bottom, 70, for: .scrollContent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(navigationTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
            }
            if !cameFromForecast {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: navigationWeatherSymbol)
                        .symbolRenderingMode(.multicolor)
                }
            }
            if showsCloseButton && !cameFromForecast {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WeatherForecastView(
                            showsCloseButton: true,
                            closeAction: closeAction
                        )
                    } label: {
                        Image(systemName: "7.circle")
                    }
                }
            }
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
                            .symbolRenderingMode(.hierarchical)
                         
                    }
                }
            }
        }
        .onChange(of: weatherManager.refreshID) { _, _ in
            forceRefresh = UUID()
        }
        .task {
            await weatherManager.refreshIfNeeded()
        }
    }

    private var navigationTitle: String {

        date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
        )
    }

    private var navigationWeatherSymbol: String {
        if Calendar.current.isDateInToday(date) {
            return weatherManager.representativeSymbol(for: date)
        }
        return weatherManager.weather(for: date)?.symbolName
            ?? "cloud.sun.fill"
    }

    private var heroCard: some View {

        let weather = weatherManager.weather(for: date)

        return HStack {

            if let sunrise = weather?.sunrise {
                Label(
                    sunrise.formatted(.dateTime.hour().minute()),
                    systemImage: "sunrise.fill"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            Spacer()

            HStack(spacing: 10) {

                Text("\(weather?.minTemperature ?? 0)°")
                    .foregroundStyle(
                        (weather?.minTemperature ?? 0) >= 35 ? .red :
                        (weather?.minTemperature ?? 0) >= 30 ? .orange :
                        (weather?.minTemperature ?? 0) <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                        .white
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(weather?.maxTemperature ?? 0)°")
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        (weather?.maxTemperature ?? 0) >= 35 ? .red :
                        (weather?.maxTemperature ?? 0) >= 30 ? .orange :
                        (weather?.maxTemperature ?? 0) <= 0 ? Color(red: 0.65, green: 0.88, blue: 1.00) :
                        .white
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            if let sunset = weather?.sunset {
                Label(
                    sunset.formatted(.dateTime.hour().minute()),
                    systemImage: "sunset.fill"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.72, blue: 1.00),
                            Color(red: 0.08, green: 0.12, blue: 0.45)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var hourlySection: some View {

        VStack(spacing: 8) {

            if weatherManager.hourlyWeather(for: date).isEmpty {

                if weatherManager.isLoading {

                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)

                } else if !weatherManager.lastLoadFailed {

                    ContentUnavailableView(
                        String(localized: "Weather Unavailable"),
                        systemImage: "icloud.slash"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            ForEach(
                weatherManager.hourlyWeather(for: date).filter { item in

                    guard Calendar.current.isDateInToday(date) else {
                        return true
                    }

                    let currentHour = Calendar.current.component(.hour, from: Date())

                    return item.hour >= currentHour
                },
                id: \.date
            ) { item in

                let isCurrentHour = Calendar.current.isDateInToday(date)
                    && Calendar.current.component(.hour, from: Date()) == item.hour

                VStack(alignment: .leading, spacing: 10) {

                    HStack(spacing: 12) {

                        Text(String(format: "%02d:00", item.hour))
                            .font(isCurrentHour ? .subheadline.weight(.bold) : .subheadline)
                            .monospacedDigit()
                            .frame(width: 55, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(1)

                        Image(systemName: item.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                            .frame(width: 30)

                        Text(
                            weatherManager.weatherDescription(
                                weatherCode: item.weatherCode,
                                isDay: item.symbolName.contains("sun")
                            )
                        )
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                        Spacer()

                        Text("\(item.temperature)°")
                            .font(.headline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                            .foregroundStyle(
                                item.temperature >= 35 ? .red :
                                item.temperature >= 30 ? .orange :
                                item.temperature <= 0 ? .cyan :
                                .primary
                            )
                    }

                    HStack(spacing: 16) {
                        // metrics labels
                        Label(
                            (Double(item.precipitationChance) / 100)
                                .formatted(.percent.precision(.fractionLength(0))),
                            systemImage: "cloud.rain"
                        )
                            .foregroundStyle(item.precipitationChance >= 80 ? .red : item.precipitationChance >= 40 ? .orange : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Label("\(item.windSpeed) km/h", systemImage: "wind")
                            .foregroundStyle(item.windSpeed >= 40 ? .red : item.windSpeed >= 25 ? .orange : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Label("UV \(item.uvIndex)", systemImage: "sun.max")
                            .foregroundStyle(item.uvIndex >= 8 ? .red : item.uvIndex >= 4 ? .orange : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Label(
                            (Double(item.humidity) / 100)
                                .formatted(.percent.precision(.fractionLength(0))),
                            systemImage: "drop.fill"
                        )
                            .foregroundStyle(item.humidity >= 85 ? .red : item.humidity >= 70 ? .orange : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Spacer()
                    }
                    .layoutPriority(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(cardBackground)
                .overlay {
                    if isCurrentHour {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.blue.opacity(0.7), lineWidth: 2)
                    }
                }
            }
        }
    }

    private var cardBackground: some View {

        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.015 : 0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
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
    }

}
