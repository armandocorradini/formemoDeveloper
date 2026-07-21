import SwiftUI
import SwiftData
import PhotosUI

import CoreGraphics
import AVFoundation

struct EditLoyaltyCardView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var card: LoyaltyCard

    @State private var showCamera = false
    @State private var selectedColor: Color = .blue
    @State private var isLoadingLogo = false
    @State private var previewLogoData: Data?
    @State private var capturedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var currentLogoData: Data? {

        if let previewLogoData {
            return previewLogoData
        }

        return LoyaltyCardLogoStore.load(
            relativePath: "\(card.id.uuidString).jpg"
        )
    }

    private var isTicket: Bool {
        card.itemType == "ticket"
    }

    var body: some View {

        NavigationStack {

            ZStack {
                AppGlassBackground()

                Form {

                Section {

                    HStack(spacing: 16) {

                        Group {

                            if let data = currentLogoData,
                               let uiImage = UIImage(data: data) {

                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 22,
                                            style: .continuous
                                        )
                                    )
                                    .id(data)

                            } else {

                                Image(systemName: "photo")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(18)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(
                                cornerRadius: 22,
                                style: .continuous
                            )
                            .fill(selectedColor)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                        )

                        VStack(alignment: .leading, spacing: 10) {

                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images
                            ) {
                                HStack {
                                    Label(
                                        "Choose Logo",
                                        systemImage: "photo.badge.plus"
                                    )

                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                showCamera = true
                            } label: {
                                HStack {
                                    Label(
                                        "Take Photo",
                                        systemImage: "camera.fill"
                                    )

                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if currentLogoData != nil {

                                Button(role: .destructive) {
                                    previewLogoData = nil

                                    LoyaltyCardLogoStore.delete(
                                        relativePath: "\(card.id.uuidString).jpg"
                                    )
                                } label: {
                                    Label(
                                        "Remove Logo",
                                        systemImage: "xmark.circle"
                                    )
                                }
                            }
                        }
                    }
                }

                Section {

                    ColorPicker(
                        isTicket
                        ? String(localized: "Ticket Color")
                        : String(localized: "Card Color"),
                        selection: $selectedColor,
                        supportsOpacity: false
                    )
                }

                Section {

                    Picker(
                        "Type",
                        selection: $card.itemType
                    ) {
                        Text("Loyalty Card")
                            .tag("loyaltyCard")

                        Text("Ticket")
                            .tag("ticket")
                    }

                    TextField(
                        isTicket
                        ? String(localized: "Event Name")
                        : String(localized: "Store Name"),
                        text: $card.storeName
                    )

                    TextField(
                        isTicket
                        ? String(localized: "Ticket Holder")
                        : String(localized: "Card Holder"),
                        text: Binding(
                            get: { card.cardHolder ?? "" },
                            set: { card.cardHolder = $0.isEmpty ? nil : $0 }
                        )
                    )

                    TextField(
                        isTicket
                        ? String(localized: "Ticket Code")
                        : String(localized: "Barcode Value"),
                        text: $card.barcodeValue
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    TextField(
                        isTicket
                        ? String(localized: "Code Format")
                        : String(localized: "Format"),
                        text: $card.barcodeFormat
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                Section {

                    TextField(
                        isTicket
                        ? String(localized: "Ticket Notes")
                        : String(localized: "Optional Notes"),
                        text: Binding(
                            get: { card.notes ?? "" },
                            set: { card.notes = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                }
            }
            .navigationTitle(
                isTicket
                ? String(localized: "Edit Ticket")
                : String(localized: "Edit Card")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(
                        card.storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isLoadingLogo
                    )
                }
            }
            .onAppear {
                selectedColor = Color(
                    hex: card.colorHex ?? "#3B82F6"
                ) ?? .blue
                previewLogoData = LoyaltyCardLogoStore.load(
                    relativePath: "\(card.id.uuidString).jpg"
                )
            }
            .onChange(of: selectedColor) { _, newValue in
                card.colorHex = newValue.toHex()
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(allowsEditing: true) { image in
                    capturedImage = image
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in

                guard let newItem else {
                    return
                }

                Task {

                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        return
                    }

                    let resized = image.resizedForWalletLogo(maxDimension: 300)

                    guard let compressed = resized.jpegData(compressionQuality: 0.65) else {
                        return
                    }

                    await MainActor.run {

                        previewLogoData = compressed

                        _ = LoyaltyCardLogoStore.save(
                            imageData: compressed,
                            for: card.id
                        )
                    }

                    do {
                        try modelContext.save()
                        modelContext.processPendingChanges()
                    } catch {
                        print("Failed to save selected logo: \(error)")
                    }
                }
            }
            .onChange(of: capturedImage) { _, newImage in
    
                guard let newImage else {
                    return
                }
                let resized = newImage.resizedForWalletLogo(maxDimension: 300)

                guard let compressed = resized.jpegData(compressionQuality: 0.65) else {
                    return
                }

                previewLogoData = compressed

                _ = LoyaltyCardLogoStore.save(
                    imageData: compressed,
                    for: card.id
                )

                do {
                    try modelContext.save()
                    modelContext.processPendingChanges()
                } catch {
                    print("Failed to save captured logo: \(error)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            }
        }
    }

    // MARK: - Save

    private func saveChanges() {

        card.storeName = card.storeName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        card.barcodeValue = card.barcodeValue
            .trimmingCharacters(in: .whitespacesAndNewlines)

        card.barcodeFormat = card.barcodeFormat
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save loyalty card: \(error)")
        }
    }
}

private extension UIImage {

    func resizedForWalletLogo(maxDimension: CGFloat = 300) -> UIImage {

        let longestSide = max(size.width, size.height)

        guard longestSide > maxDimension else {
            return self
        }

        let scale = maxDimension / longestSide

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
