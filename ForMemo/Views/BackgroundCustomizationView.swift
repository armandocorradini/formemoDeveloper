

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


                Section("Colors") {

                    ColorPicker("Top color", selection: color1)


                    ColorPicker("Bottom color", selection: color2)
                }


                Section {

                    Text("Changes are applied immediately throughout the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }


                Section {

                    Button(role: .destructive) {
                        color1Hex = defaultBackColor1.toHex() ?? ""
                        color2Hex = defaultBackColor2.toHex() ?? ""
                    } label: {
                        Text("Restore Default")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
    }
}
