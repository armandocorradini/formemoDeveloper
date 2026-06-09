import SwiftUI

struct BackgroundCustomizationView: View {

    @AppStorage("backgroundColor1Hex")
    private var color1Hex: String = defaultBackColor1.toHex() ?? ""

    @AppStorage("backgroundColor2Hex")
    private var color2Hex: String = defaultBackColor2.toHex() ?? ""

    private var color1: Binding<Color> {
        Binding(
            get: {
                Color(hex: color1Hex) ?? defaultBackColor1
            },
            set: {
                color1Hex = $0.toHex() ?? color1Hex
            }
        )
    }

    private var color2: Binding<Color> {
        Binding(
            get: {
                Color(hex: color2Hex) ?? defaultBackColor2
            },
            set: {
                color2Hex = $0.toHex() ?? color2Hex
            }
        )
    }

    private let presets: [(String, Color, Color)] = [
        ("Default", defaultBackColor1, defaultBackColor2),

        ("Ocean", Color(red: 0.08, green: 0.18, blue: 0.38), Color(red: 0.00, green: 0.55, blue: 0.80)),
        ("Aurora", Color(red: 0.00, green: 0.45, blue: 0.50), Color(red: 0.35, green: 0.15, blue: 0.65)),
        ("Night", Color(red: 0.12, green: 0.16, blue: 0.35), Color.black),
        ("Emerald", Color(red: 0.00, green: 0.40, blue: 0.25), Color(red: 0.00, green: 0.55, blue: 0.45)),
        ("Lavender", Color(red: 0.40, green: 0.22, blue: 0.60), Color(red: 0.20, green: 0.25, blue: 0.55)),
        ("Fire", Color(red: 0.70, green: 0.12, blue: 0.10), Color(red: 0.95, green: 0.45, blue: 0.10)),
        ("Rose", Color(red: 0.65, green: 0.15, blue: 0.35), Color(red: 0.90, green: 0.25, blue: 0.45)),
        ("Midnight", Color.black, Color(red: 0.08, green: 0.15, blue: 0.35)),
        ("Arctic", Color(red: 0.00, green: 0.30, blue: 0.40), Color(red: 0.55, green: 0.80, blue: 0.95)),
        ("Galaxy", Color(red: 0.15, green: 0.10, blue: 0.40), Color(red: 0.45, green: 0.20, blue: 0.65)),
        ("Carbon", Color(red: 0.18, green: 0.18, blue: 0.20), Color(red: 0.32, green: 0.34, blue: 0.38)),

        ("Sky", Color(red: 0.60, green: 0.82, blue: 1.00), Color(red: 0.88, green: 0.95, blue: 1.00)),
        ("Sand", Color(red: 0.85, green: 0.76, blue: 0.60), Color(red: 0.68, green: 0.60, blue: 0.48)),
        ("Sunset", Color(red: 1.00, green: 0.70, blue: 0.55), Color(red: 1.00, green: 0.82, blue: 0.78)),
        ("Mint", Color(red: 0.65, green: 0.92, blue: 0.82), Color(red: 0.80, green: 0.98, blue: 0.92)),
        ("Pearl", Color(red: 0.96, green: 0.96, blue: 0.98), Color(red: 0.84, green: 0.86, blue: 0.90)),
        ("Lavender Light", Color(red: 0.85, green: 0.80, blue: 0.98), Color(red: 0.78, green: 0.88, blue: 1.00)),
        ("Ruby", Color(red: 0.55, green: 0.08, blue: 0.18), Color(red: 0.90, green: 0.25, blue: 0.35)),
        ("Ice", Color(red: 0.70, green: 0.90, blue: 1.00), Color(red: 0.85, green: 0.97, blue: 1.00)),
        ("Copper", Color(red: 0.60, green: 0.35, blue: 0.20), Color(red: 0.85, green: 0.55, blue: 0.30)),
        ("Tropical", Color(red: 0.00, green: 0.65, blue: 0.55), Color(red: 0.10, green: 0.85, blue: 0.75)),
        ("Amethyst", Color(red: 0.45, green: 0.25, blue: 0.70), Color(red: 0.70, green: 0.50, blue: 0.95)),
        ("Slate", Color(red: 0.22, green: 0.25, blue: 0.30), Color(red: 0.45, green: 0.48, blue: 0.55))
        
        
    ]

    var body: some View {
        ZStack {

            LinearGradient(
                colors: [
                    Color(hex: color1Hex) ?? defaultBackColor1,
                    Color(hex: color2Hex) ?? defaultBackColor2
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Form {

                Section("Presets") {

                    let columns = [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ]

                    LazyVGrid(columns: columns, spacing: 10) {

                        ForEach(Array(presets.enumerated()), id: \.offset) { item in

                            let preset = item.element
                            let localizedName = localizedPresetName(preset.0)

                            Button {
                                color1Hex = preset.1.toHex() ?? color1Hex
                                color2Hex = preset.2.toHex() ?? color2Hex
                            } label: {

                                VStack(spacing: 4) {

                                    ZStack {

                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [preset.1, preset.2],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )

                                        VStack {
                                            Capsule()
                                                .fill(.black.opacity(0.25))
                                                .frame(width: 12, height: 3)

                                            Spacer()
                                        }
                                        .padding(.top, 4)
                                    }
                                    .frame(width: 34, height: 64)

                                    Text(localizedName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Customize colors") {

                    ColorPicker("Top color", selection: color1)


                    ColorPicker("Bottom color", selection: color2)
                }


                Section {

                    Text("Changes are applied immediately throughout the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }
            .contentMargins(.bottom, 70, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func localizedPresetName(_ key: String) -> String {

        switch key {

        case "Default": return String(localized: "Default")
        case "Ocean": return String(localized: "Ocean")
        case "Aurora": return String(localized: "Aurora")
        case "Night": return String(localized: "Night")
        case "Emerald": return String(localized: "Emerald")
        case "Lavender": return String(localized: "Lavender")
        case "Fire": return String(localized: "Fire")
        case "Rose": return String(localized: "Rose")
        case "Midnight": return String(localized: "Midnight")
        case "Arctic": return String(localized: "Arctic")
        case "Galaxy": return String(localized: "Galaxy")
        case "Carbon": return String(localized: "Carbon")
        case "Sky": return String(localized: "Sky")
        case "Sand": return String(localized: "Sand")
        case "Sunset": return String(localized: "Sunset")
        case "Mint": return String(localized: "Mint")
        case "Pearl": return String(localized: "Pearl")
        case "Lavender Light": return String(localized: "Lavender Light")
        case "Ruby": return String(localized: "Ruby")
        case "Ice": return String(localized: "Ice")
        case "Copper": return String(localized: "Copper")
        case "Tropical": return String(localized: "Tropical")
        case "Amethyst": return String(localized: "Amethyst")
        case "Slate": return String(localized: "Slate")

        default:
            return key
        }
    }
}
