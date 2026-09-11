import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import AVFoundation
import ZXingCpp

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
                    Section("Gallery") {

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
                            : String(localized: "Code Value"),
                            text: $barcodeValue
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                        if !barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            LabeledContent(
                                itemType == "ticket"
                                ? String(localized: "Code Format")
                                : String(localized: "Code Format")
                            ) {
                                Text(barcodeFormat)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan Code", systemImage: "qrcode.viewfinder")
                        }
                            PhotosPicker(
                                selection: $selectedTicketImageItem,
                                matching: .images
                            ) {
                                Label(
                                    "Import Code from Photo",
                                    systemImage: "photo.badge.magnifyingglass"
                                )
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
                guard let data = try? await newItem.loadTransferable(type: Data.self) else {
                    return
                }

                do {
                    let result = try BarcodePhotoDetector.detect(in: data)

                    await MainActor.run {
                        barcodeValue = result.value
                        barcodeFormat = result.format
                        selectedTicketImageItem = nil
                    }

                } catch {
                    await MainActor.run {
                        selectedTicketImageItem = nil
                        showNoCodeFoundAlert = true
                    }
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
            do {
                try WalletImportService.importLogo(
                    logoData,
                    into: card,
                    in: modelContext
                )
            } catch {
                modelContext.delete(card)
                return
            }
        }

        do {
            try WalletImportService.importImages(
                galleryImages,
                kind: .gallery,
                into: card,
                in: modelContext
            )
        } catch {
            modelContext.delete(card)
            return
        }

        createdAssets = card.assets ?? []

        modelContext.safeSave(
            operation: "CreateLoyaltyCard"
        )

        modelContext.processPendingChanges()

        let cardID = card.id

        guard let savedCards = try? modelContext.fetch(
            FetchDescriptor<LoyaltyCard>(
                predicate: #Predicate<LoyaltyCard> { loyalty in
                    loyalty.id == cardID
                }
            )
        ) else {
            modelContext.delete(card)
            return
        }
        guard savedCards.count == 1 else {
            modelContext.delete(card)
            return
        }

        guard let savedAssets = try? modelContext.fetch(
            FetchDescriptor<WalletAsset>()
        ) else {
            modelContext.delete(card)
            return
        }
        let savedAssetIDs = Set(savedAssets.map(\.id))
        
        guard createdAssets.allSatisfy({ asset in
            savedAssetIDs.contains(asset.id)
                && savedAssets.first(where: { $0.id == asset.id })?.card?.id == card.id
        }) else {
            modelContext.delete(card)
            return
        }

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

// MARK: - Barcode Scanner

struct BarcodeScannerSheet: UIViewControllerRepresentable {

    @Environment(\.dismiss)
    private var dismiss

    @Binding var barcodeValue: String
    @Binding var barcodeFormat: String

    func makeUIViewController(
        context: Context
    ) -> ZXingBarcodeScannerViewController {

        let controller = ZXingBarcodeScannerViewController()

        controller.onBarcodeDetected = { value, format in
            DispatchQueue.main.async {
                barcodeValue = value
                barcodeFormat = format
                dismiss()
            }
        }

        return controller
    }

    func updateUIViewController(
        _ uiViewController: ZXingBarcodeScannerViewController,
        context: Context
    ) {
    }
}


// MARK: - ZXing Camera Scanner

final class ZXingBarcodeScannerViewController:
    UIViewController,
    AVCaptureVideoDataOutputSampleBufferDelegate {

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(
        label: "com.formemo.barcode-scanner.session"
    )
    private let videoOutputQueue = DispatchQueue(
        label: "com.formemo.barcode-scanner.video"
    )

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var reader: ZXIBarcodeReader?

    private var isProcessingFrame = false
    private var hasDetectedBarcode = false

    var onBarcodeDetected: ((String, String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        let options = ZXIReaderOptions()
        options.tryHarder = true
        options.tryRotate = true
        options.tryInvert = true
        options.tryDownscale = true
        options.maxNumberOfSymbols = 1

        reader = ZXIBarcodeReader(options: options)

        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        previewLayer?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    private func configureSession() {

        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }

        captureSession.beginConfiguration()

        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ),
        let input = try? AVCaptureDeviceInput(device: device),
        captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(
            self,
            queue: videoOutputQueue
        )

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addOutput(output)

        captureSession.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let layer = AVCaptureVideoPreviewLayer(
                session: self.captureSession
            )

            layer.videoGravity = .resizeAspectFill
            layer.frame = self.view.bounds

            self.view.layer.insertSublayer(
                layer,
                at: 0
            )

            self.previewLayer = layer
        }

        captureSession.startRunning()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard !hasDetectedBarcode,
              !isProcessingFrame,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let reader else {
            return
        }

        isProcessingFrame = true

        defer {
            isProcessingFrame = false
        }

        let results: [ZXIResult]

        do {
            results = try reader.read(pixelBuffer)
        } catch {
            return
        }

        guard let result = results.first else {
            return
        }

        let value = result.text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )

        guard !value.isEmpty else {
            return
        }

        hasDetectedBarcode = true

        let format = formatName(
            for: result.format
        )

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.onBarcodeDetected?(value, format)
        }
    }

    private func formatName(
        for format: ZXIFormat
    ) -> String {

        switch format.rawValue {
        case 1: return "aztec"
        case 2: return "codabar"
        case 3: return "code39"
        case 4: return "code93"
        case 5: return "code128"
        case 6: return "gs1DataBar"
        case 7: return "gs1DataBarExpanded"
        case 8: return "gs1DataBarStacked"
        case 9: return "gs1DataBarExpandedStacked"
        case 10: return "gs1DataBarLimited"
        case 11: return "dataMatrix"
        case 12: return "dxFilmEdge"
        case 13: return "telepen"
        case 14: return "ean8"
        case 15: return "ean13"
        case 16: return "itf"
        case 17: return "maxicode"
        case 18: return "pdf417"
        case 19: return "qr"
        case 20: return "microQR"
        case 21: return "rmQR"
        case 22: return "upca"
        case 23: return "upce"
        default: return "unknown"
        }
    }
}
