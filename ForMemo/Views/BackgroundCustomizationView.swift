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
        ("Custom", defaultBackColor1, defaultBackColor2),
        ("Graphite",
         Color(red: 0.11, green: 0.11, blue: 0.12),
         Color(red: 0.18, green: 0.18, blue: 0.20)),

        ("Carbon", Color(red: 0.18, green: 0.18, blue: 0.20), Color(red: 0.32, green: 0.34, blue: 0.38)),

        ("Storm", Color(red: 0.18, green: 0.22, blue: 0.32), Color(red: 0.42, green: 0.48, blue: 0.62)),

        ("Slate", Color(red: 0.22, green: 0.25, blue: 0.30), Color(red: 0.45, green: 0.48, blue: 0.55)),

        ("Titanium",
         Color(red: 0.96, green: 0.96, blue: 0.97),
         Color(red: 0.90, green: 0.91, blue: 0.93)),

        ("Pearl", Color(red: 0.96, green: 0.96, blue: 0.98), Color(red: 0.84, green: 0.86, blue: 0.90)),

        ("Night", Color(red: 0.12, green: 0.16, blue: 0.35), Color.black),

        ("Midnight", Color.black, Color(red: 0.08, green: 0.15, blue: 0.35)),

        ("Ocean", Color(red: 0.08, green: 0.18, blue: 0.38), Color(red: 0.00, green: 0.55, blue: 0.80)),

        ("Sapphire", Color(red: 0.05, green: 0.20, blue: 0.55), Color(red: 0.20, green: 0.50, blue: 0.95)),

        ("Arctic", Color(red: 0.00, green: 0.30, blue: 0.40), Color(red: 0.55, green: 0.80, blue: 0.95)),

        ("Sky", Color(red: 0.60, green: 0.82, blue: 1.00), Color(red: 0.88, green: 0.95, blue: 1.00)),

        ("Ice", Color(red: 0.70, green: 0.90, blue: 1.00), Color(red: 0.85, green: 0.97, blue: 1.00)),

        ("Galaxy", Color(red: 0.15, green: 0.10, blue: 0.40), Color(red: 0.45, green: 0.20, blue: 0.65)),

        ("Aurora", Color(red: 0.00, green: 0.45, blue: 0.50), Color(red: 0.35, green: 0.15, blue: 0.65)),

        ("Lavender", Color(red: 0.40, green: 0.22, blue: 0.60), Color(red: 0.20, green: 0.25, blue: 0.55)),

        ("Amethyst", Color(red: 0.45, green: 0.25, blue: 0.70), Color(red: 0.70, green: 0.50, blue: 0.95)),

        ("Plum", Color(red: 0.35, green: 0.10, blue: 0.45), Color(red: 0.65, green: 0.25, blue: 0.75)),

        ("Lavender Light", Color(red: 0.85, green: 0.80, blue: 0.98), Color(red: 0.78, green: 0.88, blue: 1.00)),

        ("Forest", Color(red: 0.05, green: 0.28, blue: 0.12), Color(red: 0.18, green: 0.55, blue: 0.25)),

        ("Emerald", Color(red: 0.00, green: 0.40, blue: 0.25), Color(red: 0.00, green: 0.55, blue: 0.45)),

        ("Olive", Color(red: 0.38, green: 0.42, blue: 0.12), Color(red: 0.65, green: 0.72, blue: 0.25)),
        
        ("Tropical", Color(red: 0.00, green: 0.65, blue: 0.55), Color(red: 0.10, green: 0.85, blue: 0.75)),

        ("Lagoon", Color(red: 0.00, green: 0.45, blue: 0.55), Color(red: 0.20, green: 0.85, blue: 0.80)),

        ("Mint", Color(red: 0.65, green: 0.92, blue: 0.82), Color(red: 0.80, green: 0.98, blue: 0.92)),

        ("Cherry", Color(red: 0.55, green: 0.05, blue: 0.15), Color(red: 0.95, green: 0.20, blue: 0.35)),

        ("Ruby", Color(red: 0.55, green: 0.08, blue: 0.18), Color(red: 0.90, green: 0.25, blue: 0.35)),

        ("Rose", Color(red: 0.65, green: 0.15, blue: 0.35), Color(red: 0.90, green: 0.25, blue: 0.45)),

        ("Coral", Color(red: 0.95, green: 0.45, blue: 0.40), Color(red: 1.00, green: 0.70, blue: 0.60)),

        ("Fire", Color(red: 0.70, green: 0.12, blue: 0.10), Color(red: 0.95, green: 0.45, blue: 0.10)),

        ("Copper", Color(red: 0.60, green: 0.35, blue: 0.20), Color(red: 0.85, green: 0.55, blue: 0.30)),

        ("Desert", Color(red: 0.78, green: 0.62, blue: 0.38), Color(red: 0.95, green: 0.82, blue: 0.58)),

        ("Sand", Color(red: 0.85, green: 0.76, blue: 0.60), Color(red: 0.68, green: 0.60, blue: 0.48)),

        ("Sunflower", Color(red: 0.95, green: 0.70, blue: 0.10), Color(red: 1.00, green: 0.90, blue: 0.35)),

        ("Sunset", Color(red: 1.00, green: 0.70, blue: 0.55), Color(red: 1.00, green: 0.82, blue: 0.78)),
        
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

                    ScrollView(.horizontal, showsIndicators: false) {

                        HStack(alignment: .top, spacing: 14) {

                            let selectedColor1 = Color(hex: color1Hex) ?? defaultBackColor1
                            let selectedColor2 = Color(hex: color2Hex) ?? defaultBackColor2

                            let isDefault =
                                selectedColor1.toHex() == defaultBackColor1.toHex() &&
                                selectedColor2.toHex() == defaultBackColor2.toHex()

                            let matchesPreset = presets.dropFirst(2).contains {
                                color1Hex == ($0.1.toHex() ?? "") &&
                                color2Hex == ($0.2.toHex() ?? "")
                            }

                            let shouldShowCustom = !isDefault && !matchesPreset

                            let visiblePresets = presets.filter {
                                shouldShowCustom || $0.0 != "Custom"
                            }

                            ForEach(Array(visiblePresets.enumerated()), id: \.offset) { item in

                                let preset = item.element
                                let localizedName = localizedPresetName(preset.0)

                                let isSelected: Bool = {

                                    if preset.0 == "Default" {
                                        return isDefault
                                    }

                                    if preset.0 == "Custom" {
                                        return shouldShowCustom
                                    }

                                    return color1Hex == (preset.1.toHex() ?? "") &&
                                           color2Hex == (preset.2.toHex() ?? "")
                                }()

                                Button {

                                    color1Hex = preset.1.toHex() ?? color1Hex
                                    color2Hex = preset.2.toHex() ?? color2Hex

                                } label: {

                                    VStack(spacing: 6) {

                                        ZStack {

                                            RoundedRectangle(
                                                cornerRadius: 18,
                                                style: .continuous
                                            )
                                            .fill(
                                                LinearGradient(
                                                    colors: preset.0 == "Custom"
                                                        ? [selectedColor1, selectedColor2]
                                                        : [preset.1, preset.2],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )

                                            VStack {

                                                Capsule()
                                                    .fill(.black.opacity(0.25))
                                                    .frame(width: 18, height: 4)

                                                Spacer()
                                            }
                                            .padding(.top, 6)
                                        }
                                        .frame(width: 52, height: 100)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(
                                                    isSelected ? Color.accentColor : Color.clear,
                                                    lineWidth: 3
                                                )
                                        }

                                        Text(localizedName)
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
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
        case "Forest": return String(localized: "Forest")
        case "Sapphire": return String(localized: "Sapphire")
        case "Cherry": return String(localized: "Cherry")
        case "Desert": return String(localized: "Desert")
        case "Lagoon": return String(localized: "Lagoon")
        case "Plum": return String(localized: "Plum")
        case "Sunflower": return String(localized: "Sunflower")
        case "Storm": return String(localized: "Storm")
        case "Coral": return String(localized: "Coral")
        case "Olive": return String(localized: "Olive")
        case "Custom": return String(localized: "Custom")
        case "Titanium": return String(localized: "Titanium")
        case "Graphite": return String(localized: "Graphite")
        default:
            return key
        }
    }
}
