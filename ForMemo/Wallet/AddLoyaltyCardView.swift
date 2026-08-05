import SwiftUI
import SwiftData
import VisionKit
import Vision
import PhotosUI
import UIKit
import AVFoundation

struct AddLoyaltyCardView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var storeName = ""
    @State private var cardHolder = ""
    @State private var barcodeValue = ""
    @State private var barcodeFormat = "code128"
    @State private var itemType = "loyaltyCard"
    @State private var notes = ""
    @State private var showScanner = false
    @State private var showCamera = false
    @State private var cameraSession = UUID()
    
    @State private var logoData: Data?
    @State private var selectedColor: Color = .blue
    @State private var isLoadingLogo = false
    @State private var capturedImage: UIImage?
    @State private var showNoCodeFoundAlert = false
    
    @State private var galleryImages: [Data] = []
    
    @State private var selectedTicketImageItem: PhotosPickerItem?
    


    @State private var viewingImage: UIImage?
    @State private var showImageViewer = false

    @State private var cameraTarget: WalletAssetKind?


    @State private var selectedPhotoItem: PhotosPickerItem?
    
    
    @State private var showGalleryPhotoPicker = false
    @State private var showingGalleryMenu = false
    @State private var galleryPickerItems: [PhotosPickerItem] = []
    

    
    var body: some View {

        NavigationStack {

            ZStack {
                AppGlassBackground()

                Form {

                    Section {
                        
                        HStack(spacing: 20) {
                            
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
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 22,
                                    style: .continuous
                                )
                                .fill(selectedColor)
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 22,
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
                                    presentCamera(target: .logo)
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
                            }
                        }
                        
                        if logoData != nil {

                            Button(role: .destructive) {
                                logoData = nil
                            } label: {
                                Label("Remove Logo", systemImage: "xmark.circle")
                            }
                        }
                    }
                    Section("Images") {

                        ScrollView(.horizontal, showsIndicators: false) {

                            LazyHStack(spacing: 12) {

                                ForEach(0..<galleryImages.count, id: \.self) { index in

                                    Button {

                                        if let image = UIImage(data: galleryImages[index]) {
                                            viewingImage = image
                                            showImageViewer = true
                                        }

                                    } label: {

                                        ImagePlaceholder(
                                            imageData: galleryImages[index]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                
                                }

                                Button {

                                    showingGalleryMenu = true

                                } label: {

                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.gray.opacity(0.15))
                                        .frame(width: 140, height: 90)
                                        .overlay {

                                            Image(systemName: "plus")
                                                .font(.title2)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                        .confirmationDialog(
                            "Add Image",
                            isPresented: $showingGalleryMenu
                        ) {

                            Button("Take Photo") {
                                presentCamera(target: .gallery)
                            }

                            Button("Choose Photo") {
                                showGalleryPhotoPicker = true
                            }

                            Button("Cancel", role: .cancel) { }
                        }
                        .photosPicker(
                            isPresented: $showGalleryPhotoPicker,
                            selection: $galleryPickerItems,
                            maxSelectionCount: nil,
                            matching: .images
                        )
                    }
     

                    Section {

                        ColorPicker(
                            itemType == "ticket"
                            ? String(localized: "Ticket Color")
                            : String(localized: "Card Color"),
                            selection: $selectedColor,
                            supportsOpacity: false
                        )
                    }

                    Section {

                        Picker("Type", selection: $itemType) {
                            Text("Loyalty Card")
                                .tag("loyaltyCard")

                            Text("Ticket")
                                .tag("ticket")
                        }

                        TextField(
                            itemType == "ticket"
                            ? String(localized: "Event Name")
                            : String(localized: "Store Name"),
                            text: $storeName
                        )
                        .textInputAutocapitalization(.words)

                        TextField(
                            itemType == "ticket"
                            ? String(localized: "Ticket Holder")
                            : String(localized: "Card Holder"),
                            text: $cardHolder
                        )
                        .textInputAutocapitalization(.words)
                    }

                    Section("Code") {

                        TextField(
                            itemType == "ticket"
                            ? String(localized: "Ticket Code")
                            : String(localized: "Barcode Value"),
                            text: $barcodeValue
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                        LabeledContent(
                            itemType == "ticket"
                            ? String(localized: "Code Format")
                            : String(localized: "Format")
                        ) {
                            Text(barcodeFormat)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan Barcode, QR Code or Ticket", systemImage: "qrcode.viewfinder")
                        }

                        if itemType == "ticket" {

                            PhotosPicker(
                                selection: $selectedTicketImageItem,
                                matching: .images
                            ) {
                                Label(
                                    "Import Ticket from Photo",
                                    systemImage: "photo.badge.magnifyingglass"
                                )
                            }
                        }
                    }

                    Section(
                        itemType == "ticket"
                        ? String(localized: "Ticket Notes")
                        : String(localized: "Notes")
                    ) {
                        TextField(
                            itemType == "ticket"
                            ? String(localized: "Ticket Notes")
                            : String(localized: "Optional Notes"),
                            text: $notes,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    }
                }
                .navigationTitle(
                    itemType == "ticket"
                    ? String(localized: "Add Ticket")
                    : String(localized: "Add Card")
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
                            saveCard()
                        }
                        .disabled(
                            storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isLoadingLogo
                        )
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet(
                    barcodeValue: $barcodeValue,
                    barcodeFormat: $barcodeFormat
                )
            }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(allowsEditing: true) { image in
                capturedImage = image
            }
            .id(cameraSession)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in

            guard let newItem else {
                return
            }

            Task {

                guard let data = try? await newItem.loadTransferable(type: Data.self)
                else {
                    return
                }

                await MainActor.run {
                    logoData = data
                }

            }
        }
        .onChange(of: galleryPickerItems) { _, newItems in

            Task {

                var images: [Data] = []

                for item in newItems {

                    guard
                        let data = try? await item.loadTransferable(type: Data.self)
                       
                    else {
                        continue
                    }

                    images.append(data)
                }

                await MainActor.run {

                    galleryImages.append(contentsOf: images)
                    galleryPickerItems.removeAll()
                }
            }
        }
        .onChange(of: selectedTicketImageItem) { _, newItem in

            guard let newItem else {
                return
            }

            Task {

                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    return
                }

                let request = VNDetectBarcodesRequest()
                request.revision = VNDetectBarcodesRequestRevision3
                request.symbologies = [
                    .qr,
                    .ean13,
                    .code128,
                    .pdf417,
                    .aztec
                ]
                request.preferBackgroundProcessing = true

                guard let cgImage = uiImage.cgImage else {
                    print("❌ Unable to create CGImage")
                    return
                }

                let handler = VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(uiImage.imageOrientation),
                    options: [:]
                )

                do {
                    try handler.perform([request])
                } catch {

                    print("📷 Ticket scan error:", error)

                    let detector = CIDetector(
                        ofType: CIDetectorTypeQRCode,
                        context: nil,
                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
                    )

                    if let ciImage = CIImage(image: uiImage),
                       let features = detector?.features(in: ciImage) as? [CIQRCodeFeature],
                       let message = features.first?.messageString {

                        await MainActor.run {
                            barcodeValue = message
                            barcodeFormat = "qr"
                        }
                    }

                    return
                }

                guard let observation = request.results?.first else {

                    print("❌ No barcode detected")

                    await MainActor.run {
                        selectedTicketImageItem = nil
                    }

                    try? await Task.sleep(for: .milliseconds(700))

                    await MainActor.run {
                        showNoCodeFoundAlert = true
                    }

                    return
                }

                print("✅ Found:", observation.symbology.rawValue)
                print("✅ Payload:", observation.payloadStringValue ?? "nil")

                guard let payload = observation.payloadStringValue,
                      !payload.isEmpty else {

                    print("❌ Barcode detected but payload is empty")

                    return
                }

                await MainActor.run {
                    barcodeValue = payload
                    barcodeFormat = observation.symbology.rawValue
                }
            }
        }
        .onChange(of: capturedImage) { _, newImage in

            guard let newImage else {
                return
            }

            guard let originalData = newImage.jpegData(
                compressionQuality: 1.0
            ) else {
                return
            }

            switch cameraTarget {

            case .logo:
                logoData = newImage.jpegData(compressionQuality: 1.0)

            case .gallery:
                galleryImages.append(originalData)

            case nil:
                break
            }

            capturedImage = nil
            cameraTarget = nil
        }
        .alert(
            "No Code Found",
            isPresented: $showNoCodeFoundAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(
                "The selected image does not contain a readable barcode or QR code."
            )
        }
    }

    private func presentCamera(
        target: WalletAssetKind
    ) {

        cameraTarget = target
        cameraSession = UUID()

        DispatchQueue.main.async {
            showCamera = true
        }
    }
    
    
    // MARK: - Save

    private func saveCard() {
        print("======== SAVE CARD START ========")
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
            itemType: itemType,
            notes: cleanedNotes.isEmpty ? nil : cleanedNotes,
            colorHex: colorHex
        )
        modelContext.insert(card)

        var createdAssets: [WalletAsset] = []

        if let logoData {

            try! WalletImportService.importLogo(
                logoData,
                into: card,
                in: modelContext
            )
        }

        try! WalletImportService.importImages(
            galleryImages,
            kind: .gallery,
            into: card,
            in: modelContext
        )

        createdAssets = card.assets ?? []

        modelContext.safeSave(
            operation: "CreateLoyaltyCard"
        )

        modelContext.processPendingChanges()

        let cardID = card.id

        let savedCards = try! modelContext.fetch(
            FetchDescriptor<LoyaltyCard>(
                predicate: #Predicate<LoyaltyCard> { loyalty in
                    loyalty.id == cardID
                }
            )
        )
        precondition(savedCards.count == 1, "LoyaltyCard was discarded by the local save")

        let savedAssets = try! modelContext.fetch(FetchDescriptor<WalletAsset>())
        let savedAssetIDs = Set(savedAssets.map(\.id))
        precondition(
            createdAssets.allSatisfy { asset in
                savedAssetIDs.contains(asset.id)
                    && savedAssets.first(where: { $0.id == asset.id })?.card?.id == card.id
            },
            "WalletAsset was discarded by the local save"
        )

        dismiss()
    }
}



private struct ImagePlaceholder: View {

    let imageData: Data?

    var body: some View {

        Group {

            if let imageData,
               let image = UIImage(data: imageData) {

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()

            } else {

                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.15))
                    .overlay {

                        VStack(spacing: 8) {

                            Image(systemName: "photo")

                            Text("Add Image")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 140, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                
                print(barcode.observation.symbology.rawValue)
                
                
                self.parent.barcodeFormat = barcode.observation.symbology.rawValue

                self.parent.dismiss()
            }
        }
    }
}


private extension CGImagePropertyOrientation {

    init(_ orientation: UIImage.Orientation) {

        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
