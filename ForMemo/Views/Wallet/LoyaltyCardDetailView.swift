import SwiftUI
import UIKit

struct LoyaltyCardDetailView: View {

    let card: LoyaltyCard

    var body: some View {

        ScrollView {

            VStack(spacing: 28) {

                VStack(spacing: 12) {

                    VStack(spacing: 12) {

                        HStack(spacing: 12) {

                            if let data = card.logoData,
                               let uiImage = UIImage(data: data) {

                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                    )

                            } else {

                                Image(systemName: "wallet.pass.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .frame(width: 58, height: 58)
                                    .background(.white.opacity(0.12))
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {

                                Text(card.storeName)
                                    .font(.title.bold())
                                    .foregroundStyle(.white)

                                if let holder = card.cardHolder,
                                   !holder.isEmpty {

                                    Text(holder)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }

                            Spacer(minLength: 0)
                        }

                        GeneratedBarcodeView(
                            value: card.barcodeValue,
                            format: card.barcodeFormat
                        )
                        .frame(height: 220)
                        .scaleEffect(x: 1, y: 2.1, anchor: .center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 22,
                                style: .continuous
                            )
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 26,
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
                    .padding(.horizontal, 20)

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
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
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
