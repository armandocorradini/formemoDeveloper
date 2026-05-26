import SwiftUI
import UIKit

struct LoyaltyCardDetailView: View {

    let card: LoyaltyCard

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

                            if let data = card.logoData,
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

                                Image(systemName: "wallet.pass.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .frame(width: 54, height: 54)
                                    .background(.white.opacity(0.12))
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
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if let holder = card.cardHolder,
                                   !holder.isEmpty {

                                    Text(holder)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.72))
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 0)
                        }

                        Spacer(minLength: 0)

                        VStack {

                            GeneratedBarcodeView(
                                value: card.barcodeValue,
                                format: card.barcodeFormat
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .scaleEffect(x: 1, y: 1.18, anchor: .center)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .padding(20)
                    .frame(maxWidth: 390)
                    .frame(height: 246)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 30,
                            style: .continuous
                        )
                        .fill(
                            Color(
                                hex: card.colorHex ?? "#3B82F6"
                            ) ?? .blue
                        )
                        .shadow(
                            color: .black.opacity(0.14),
                            radius: 18,
                            y: 8
                        )
                    )
                    .padding(.horizontal, 14)

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
