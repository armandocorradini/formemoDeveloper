import SwiftUI
import SwiftData
import VisionKit
import Vision
import PhotosUI
import UIKit

struct AddLoyaltyCardView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var storeName = ""
    @State private var cardHolder = ""
    @State private var barcodeValue = ""
    @State private var barcodeFormat = "code128"
    @State private var notes = ""
    @State private var showScanner = false
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var logoData: Data?
    @State private var selectedColor: Color = .blue
    @State private var isLoadingLogo = false

    var body: some View {

        NavigationStack {

            Form {

                Section {

                    HStack(spacing: 16) {

                        Group {
                            if let logoData,
                               let uiImage = UIImage(data: logoData) {

                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipped()

                            } else {

                                Image(systemName: "photo")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(18)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .background(.ultraThinMaterial)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                        )

                        PhotosPicker(
                            selection: $selectedLogoItem,
                            matching: .images
                        ) {
                            Label(
                                "Choose Logo",
                                systemImage: "photo.badge.plus"
                            )
                        }
                    }
                }

                Section {

                    ColorPicker(
                        "Card Color",
                        selection: $selectedColor,
                        supportsOpacity: false
                    )
                }

                Section {

                    TextField("Store Name", text: $storeName)
                        .textInputAutocapitalization(.words)

                    TextField("Card Holder", text: $cardHolder)
                        .textInputAutocapitalization(.words)
                }

                Section("Barcode") {

                    TextField("Barcode Value", text: $barcodeValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    LabeledContent("Format") {
                        Text(barcodeFormat)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                }

                Section("Notes") {

                    TextField("Optional Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCard()
                    }
                    .disabled(
                        storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isLoadingLogo
                    )
                }
            }
        }
        .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet(
                    barcodeValue: $barcodeValue,
                    barcodeFormat: $barcodeFormat
                )
            }
            .onChange(of: selectedLogoItem) { _, newItem in

                guard let newItem else {
                    return
                }

                isLoadingLogo = true

                Task {
                    defer {
                        DispatchQueue.main.async {
                            isLoadingLogo = false
                        }
                    }

                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {

                        let compressed = image.jpegData(compressionQuality: 0.7)

                        await MainActor.run {
                            logoData = compressed
                        }
                    }
                }
            }
    }

    // MARK: - Save

    private func saveCard() {

        let cleanedStore = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedHolder = cardHolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBarcode = barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let colorHex = selectedColor.toHex()

        let card = LoyaltyCard(
            storeName: cleanedStore,
            cardHolder: cleanedHolder.isEmpty ? nil : cleanedHolder,
            barcodeValue: cleanedBarcode,
            barcodeFormat: barcodeFormat,
            notes: cleanedNotes.isEmpty ? nil : cleanedNotes,
            colorHex: colorHex,
            logoData: logoData
        )

        modelContext.insert(card)

        try? modelContext.save()

        dismiss()
    }
}
// MARK: - Barcode Scanner

private struct BarcodeScannerSheet: UIViewControllerRepresentable {

    @Environment(\.dismiss)
    private var dismiss

    @Binding var barcodeValue: String
    @Binding var barcodeFormat: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(
        context: Context
    ) -> DataScannerViewController {

        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        controller.delegate = context.coordinator

        try? controller.startScanning()

        return controller
    }

    func updateUIViewController(
        _ uiViewController: DataScannerViewController,
        context: Context
    ) {

    }

    final class Coordinator:
        NSObject,
        DataScannerViewControllerDelegate {

        let parent: BarcodeScannerSheet

        init(_ parent: BarcodeScannerSheet) {
            self.parent = parent
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {

            guard let first = addedItems.first else {
                return
            }

            handle(first)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {

            handle(item)
        }

        private func handle(_ item: RecognizedItem) {

            guard case .barcode(let barcode) = item else {
                return
            }

            guard let payload = barcode.payloadStringValue,
                  !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            DispatchQueue.main.async {

                self.parent.barcodeValue = payload

                self.parent.barcodeFormat = barcode.observation.symbology.rawValue

                self.parent.dismiss()
            }
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

#Preview {
    AddLoyaltyCardView()
}
