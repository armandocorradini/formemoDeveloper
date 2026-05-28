import SwiftUI
import UIKit

struct LoyaltyCardDetailView: View {

    let card: LoyaltyCard
    @State private var zoomScale: CGFloat = 1
    @State private var lastZoomScale: CGFloat = 1
    
    private var cardBackgroundColor: Color {
        Color(
            hex: card.colorHex ?? "#3B82F6"
        ) ?? .blue
    }

    private var prefersDarkText: Bool {
        UIColor(cardBackgroundColor).isLightColor
    }

    private var primaryTextColor: Color {
        prefersDarkText ? .black.opacity(0.88) : .white
    }

    private var secondaryTextColor: Color {
        prefersDarkText
            ? .black.opacity(0.68)
            : .white.opacity(0.92)
    }

    private var textShadowColor: Color {
        prefersDarkText
            ? .white.opacity(0.18)
            : .black.opacity(0.45)
    }

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
                
                Spacer(minLength: 18)

                VStack(spacing: 18) {

                    VStack(spacing: 0) {

                        HStack(alignment: .top, spacing: 14) {

                            if let data = LoyaltyCardLogoStore.load(
                                relativePath: "\(card.id.uuidString).jpg"
                            ),
                               let uiImage = UIImage(data: data) {

                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 54, height: 54)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                    )

                            } else {

                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(
                                        prefersDarkText
                                        ? Color.black.opacity(0.82)
                                        : Color.white.opacity(0.92)
                                    )
                                    .frame(width: 54, height: 54)
                                    .background(
                                        prefersDarkText
                                        ? Color.black.opacity(0.08)
                                        : Color.white.opacity(0.12)
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {

                                Text(card.storeName)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)
                                    .shadow(color: textShadowColor, radius: 2, y: 1)

                                if let holder = card.cardHolder,
                                   !holder.isEmpty {

                                    Text(holder)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(secondaryTextColor)
                                        .lineLimit(1)
                                        .shadow(color: textShadowColor.opacity(0.8), radius: 1.5, y: 1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.10))
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )

                            Spacer(minLength: 0)
                        }

                        Spacer(minLength: 12)

                        HStack {

                            Spacer(minLength: 0)

                            GeneratedBarcodeView(
                                value: card.barcodeValue,
                                format: card.barcodeFormat
                            )
                            .frame(maxWidth: 320)
                            .frame(height: 92)
                            .scaleEffect(x: 1, y: 1.22, anchor: .center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(.white)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 18,
                                    style: .continuous
                                )
                            )

                            Spacer(minLength: 0)
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(20)
                    .frame(maxWidth: 410)
                    .frame(height: 318)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 30,
                            style: .continuous
                        )
                        .fill(cardBackgroundColor)
                        .shadow(
                            color: .black.opacity(0.14),
                            radius: 18,
                            y: 8
                        )
                    )
                    .padding(.horizontal, 10)

                    Text(card.barcodeValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let notes = card.notes,
                   !notes.isEmpty {

                    VStack(alignment: .leading, spacing: 10) {

                        Text("Notes")
                            .font(.headline)

                        Text(notes)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .scaleEffect(zoomScale)
            .animation(.smooth(duration: 0.16), value: zoomScale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in

                        let delta = value / lastZoomScale

                        lastZoomScale = value

                        zoomScale *= delta

                        zoomScale = min(max(zoomScale, 1), 4)
                    }
                    .onEnded { _ in

                        lastZoomScale = 1
                    }
            )
            .onTapGesture(count: 2) {

                withAnimation(.spring(duration: 0.28)) {

                    zoomScale = zoomScale > 1.2 ? 1 : 2
                }
            }
            .padding(.bottom, 40)
        }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
    }
}

#Preview {

    LoyaltyCardDetailView(
        card: LoyaltyCard(
            storeName: "Coop",
            cardHolder: "Armando",
            barcodeValue: "8001234567890",
            barcodeFormat: "EAN13",
            notes: "Main family card", colorHex: "#00A86B"
        )
    )
}



private extension UIColor {

    var isLightColor: Bool {

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        )

        let brightness = (
            (red * 299) +
            (green * 587) +
            (blue * 114)
        ) / 1000

        return brightness > 0.68
    }
}
