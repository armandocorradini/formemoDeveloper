

import SwiftUI
import SwiftData
import VisionKit
import Vision

struct AddLoyaltyCardView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var storeName = ""
    @State private var cardHolder = ""
    @State private var barcodeValue = ""
    @State private var barcodeFormat = "Code128"
    @State private var notes = ""
    @State private var showScanner = false

    var body: some View {

        NavigationStack {

            Form {

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
                    .disabled(storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet(
                    barcodeValue: $barcodeValue,
                    barcodeFormat: $barcodeFormat
                )
            }
    }

    // MARK: - Save

    private func saveCard() {

        let cleanedStore = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedHolder = cardHolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBarcode = barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let card = LoyaltyCard(
            storeName: cleanedStore,
            cardHolder: cleanedHolder.isEmpty ? nil : cleanedHolder,
            barcodeValue: cleanedBarcode,
            barcodeFormat: barcodeFormat,
            notes: cleanedNotes.isEmpty ? nil : cleanedNotes
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

            guard case .barcode(let barcode) = first else {
                return
            }

            guard let payload = barcode.payloadStringValue else {
                return
            }

            parent.barcodeValue = payload

            parent.barcodeFormat =
                String(describing: barcode.observation.symbology)

            parent.dismiss()
        }
    }
}

#Preview {
    AddLoyaltyCardView()
}
