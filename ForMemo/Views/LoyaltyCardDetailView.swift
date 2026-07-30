import SwiftUI

import SwiftData

struct LoyaltyCardDetailView: View {

    @Environment(\.modelContext) private var modelContext

    let card: LoyaltyCard
    @State private var zoomScale: CGFloat = 1
    @State private var lastZoomScale: CGFloat = 1
    @State private var previewImage: PreviewImage?
    private var cardBackgroundColor: Color {
        Color(
            hex: card.colorHex ?? "#3B82F6"
        ) ?? .blue
    }

    private struct PreviewImage: Identifiable {
        let id = UUID()
        let image: UIImage
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
    
    private var isQRCode: Bool {
        card.barcodeFormat.lowercased().contains("qr")
    }
    
    private var isTicket: Bool {
        card.itemType == "ticket"
    }

    private var logoData: Data? {
        LoyaltyCardLogoStore.load(
            asset: card.logoAsset
        ) ?? LoyaltyCardLogoStore.load(
            relativePath: "\(card.id.uuidString).jpg"
        )
    }

    private var frontData: Data? {
        LoyaltyCardLogoStore.load(
            asset: card.frontAsset
        )
    }

    private var backData: Data? {
        LoyaltyCardLogoStore.load(
            asset: card.backAsset
        )
    }
    
    
    var body: some View {

        ZStack {

            AppGlassBackground()

        ScrollView {

            VStack(spacing: 18) {
                
                Spacer(minLength: 18)

                VStack(spacing: 18) {

                    VStack(spacing: 0) {

                        HStack(alignment: .top, spacing: 14) {

                            if let data = logoData,
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
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                        .stroke(
                                            .white.opacity(0.15),
                                            lineWidth: 0.8
                                        )
                                    }
                                    .shadow(
                                        color: .black.opacity(0.12),
                                        radius: 6,
                                        y: 2
                                    )

                            } else {
                                
                                Image(
                                    systemName: isTicket
                                    ? "ticket.fill"
                                    : "creditcard.fill"
                                )
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
                                    .overlay {
                                        RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                        .stroke(
                                            .white.opacity(0.15),
                                            lineWidth: 0.8
                                        )
                                    }
                                    .shadow(
                                        color: .black.opacity(0.12),
                                        radius: 6,
                                        y: 2
                                    )
                            }
                            VStack(alignment: .leading, spacing: 4) {

                                if isTicket {
                                    Text("Event")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(secondaryTextColor)
                                }

                                Text(card.storeName)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)
                                    .shadow(color: textShadowColor, radius: 2, y: 1)

                                if let holder = card.cardHolder,
                                   !holder.isEmpty {

                                    Text(
                                        isTicket
                                        ? String(localized: "Ticket Holder")
                                        : String(localized: "Card Holder")
                                    )
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(secondaryTextColor)

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
                            .frame(
                                maxWidth: isQRCode ? 220 : 320
                            )
                            .frame(
                                width: isQRCode ? 220 : nil,
                                height: isQRCode ? 220 : 92
                            )
                            .scaleEffect(
                                x: 1,
                                y: isQRCode ? 1 : 1.22,
                                anchor: .center
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(.white)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 22,
                                    style: .continuous
                                )
                            )

                            Spacer(minLength: 0)
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(20)
                    .frame(maxWidth: 410)
                    .frame(height: isQRCode ? 450 : 318)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 30,
                            style: .continuous
                        )
                        .fill(cardBackgroundColor)
                        .shadow(
                            color: .black.opacity(0.14),
                            radius: 22,
                            y: 8
                        )
                    )
                    .padding(.horizontal, 10)

                    Text(
                        isTicket
                        ? String(localized: "Ticket Code")
                        : String(localized: "Barcode Value")
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Text(card.barcodeValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                HStack{
                    if let frontData,
                       let uiImage = UIImage(data: frontData) {
                        
                        VStack( spacing: 10) {
                            
                            Text("Front")
                                .font(.headline)
                            
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 95)
                                .clipped()
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    previewImage = PreviewImage(image: uiImage)
                                 }
                            
                        }
                        .padding(.horizontal)
                    }
                    
                    if let backData,
                       let uiImage = UIImage(data: backData) {
                        
                        VStack( spacing: 10) {
                            
                            Text("Back")
                                .font(.headline)
                            
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 95)
                                .clipped()
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    previewImage = PreviewImage(image: uiImage)
                                 }
                            
                        }
                        .frame(width: 150)
                        .padding(.horizontal)
                    }
    
                }
                if let notes = card.notes,
                   !notes.isEmpty {

                    VStack(alignment: .leading, spacing: 10) {

                        Text(
                            isTicket
                            ? String(localized: "Ticket Notes")
                            : String(localized: "Notes")
                        )
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
                    .frame(width: 150)
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
        .onAppear {

            var needsSave = false

            if WalletAsset.createLegacyLogoReference(
                for: card,
                in: modelContext
            ) != nil {

                needsSave = true
            }

            card.lastOpenedAt = .now
            needsSave = true

            if needsSave {
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to update LoyaltyCard: \(error)")
                }
            }
        }
        .navigationTitle(
            isTicket
            ? String(localized: "Ticket")
            : String(localized: "Card")
        )
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)

        .fullScreenCover(item: $previewImage) { preview in
            ImagePreviewView(image: preview.image)
        }

    }
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
