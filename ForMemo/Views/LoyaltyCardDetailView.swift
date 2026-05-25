

import SwiftUI

struct LoyaltyCardDetailView: View {

    let card: LoyaltyCard

    var body: some View {

        ScrollView {

            VStack(spacing: 28) {

                VStack(spacing: 8) {

                    Text(card.storeName)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    if let holder = card.cardHolder,
                       !holder.isEmpty {

                        Text(holder)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)

                VStack(spacing: 18) {

                    GeneratedBarcodeView(
                        value: card.barcodeValue,
                        format: card.barcodeFormat
                    )
                    .frame(height: 280)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        )

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
            notes: "Main family card"
        )
    )
}
