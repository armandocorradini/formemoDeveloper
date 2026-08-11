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
    @State private var cameraSession = UUID()
    @State private var selectedColor: Color = .blue
    @State private var isLoadingLogo = false
    @State private var previewLogoData: Data?
    @State private var capturedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?

    @State private var viewingImage: UIImage?
    @State private var showImageViewer = false
    
    @State private var cameraTarget: WalletAssetKind?
    
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    private var currentLogoData: Data? {

        if let previewLogoData {
            return previewLogoData
        }

        if let asset = card.logoAsset,
           let data = WalletAssetStore.loadData(
               relativePath: asset.relativePath
           ) {
            return data
        }

        if let relativePath = card.loyaltyLogoRelativePath,
           let data = WalletAssetStore.loadData(
               relativePath: relativePath
           ) {
            return data
        }

        return nil
    }

    private var isTicket: Bool {
        card.itemType == "ticket"
    }
    
    private var isSaveDisabled: Bool {

        card.storeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        || isLoadingLogo
    }
    

    var body: some View {

        NavigationStack {

            ZStack {
                AppGlassBackground()

                Form {

                Section {

                    HStack(spacing: 16) {

                        Group {

                            if let data = previewLogoData,
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

                            if currentLogoData != nil {

                                Button(role: .destructive) {
                                    previewLogoData = nil

                                    if let asset = card.logoAsset {

                                        WalletImportService.delete(
                                            asset,
                                            from: modelContext
                                        )
                                    }

                                    previewLogoData = nil

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

                    Section("Gallery") {

                        WalletViewerView(
                            card: card,
                            onCameraRequested: presentCamera
                        )
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

//                ToolbarItem(placement: .confirmationAction) {
//                    Button("Done") {
//                        dismiss()
//                    }
//                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
               
                }
            }
            .onAppear {

                selectedColor = Color(
                    hex: card.colorHex ?? "#3B82F6"
                ) ?? .blue

                if card.logoAsset == nil {
                   
                }

                if let asset = card.logoAsset {

                    previewLogoData = WalletAssetStore.loadData(
                        relativePath: asset.relativePath
                    )
                }

                if previewLogoData == nil,
                   let relativePath = card.loyaltyLogoRelativePath {

                    previewLogoData = WalletAssetStore.loadData(
                        relativePath: relativePath
                    )
                }
            }
            .onChange(of: selectedColor) { _, newValue in
                card.colorHex = newValue.toHex()
            }

            .onChange(of: selectedPhotoItem) { _, newItem in

                guard let newItem else {
                    return
                }

                Task {

                    guard let data = try? await newItem.loadTransferable(type: Data.self) else {
                        return
                    }

                    await MainActor.run {

                        previewLogoData = data

                        do {

                            if let asset = card.logoAsset {

                                WalletImportService.delete(
                                    asset,
                                    from: modelContext
                                )
                            }

                            try WalletImportService.importLogo(
                                data,
                                into: card,
                                in: modelContext
                            )

                        } catch {

                            assertionFailure(
                                "Failed to replace logo: \(error)"
                            )
                        }
                    }

                    modelContext.safeSave(
                        operation: "UpdateLoyaltyLogo"
                    )
                    modelContext.processPendingChanges()
                }
            }
                
            .onChange(of: capturedImage) { _, newImage in

                guard let newImage else {
                    return
                }

                switch cameraTarget {

                case .gallery:

                    do {

                        try WalletImportService.importImages(
                            [newImage],
                            kind: .gallery,
                            into: card,
                            in: modelContext
                        )

                    } catch {

                        assertionFailure(
                            "Failed to import camera image: \(error)"
                        )
                    }

                default:

                    guard let data = newImage.jpegData(compressionQuality: 1.0) else {
                        return
                    }

                    previewLogoData = data

                    do {

                        if let asset = card.logoAsset {

                            WalletImportService.delete(
                                asset,
                                from: modelContext
                            )
                        }

                        try WalletImportService.importLogo(
                            data,
                            into: card,
                            in: modelContext
                        )

                    } catch {

                        assertionFailure(
                            "Failed to replace logo: \(error)"
                        )
                    }
                }

                modelContext.safeSave(
                    operation: "UpdateLoyaltyCapturedImage"
                )
                modelContext.processPendingChanges()

                capturedImage = nil
                showCamera = false
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
                
            .sheet(isPresented: $showImageViewer) {

                NavigationStack {

                    ZStack {

                        Color.black
                            .ignoresSafeArea()

                        if let image = viewingImage {

                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        }
                    }
                    .onTapGesture {
                        showImageViewer = false
                        viewingImage = nil
                    }                        .toolbar {


                        }
                }
            }
                
                
            }
        }
        
        
        .fullScreenCover(
            isPresented: $showCamera
        ) {
            CameraPicker(allowsEditing: true) { image in
                capturedImage = image
            }
            .id(cameraSession)
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: nil,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, newItems in

            Task {

                var images: [UIImage] = []

                for item in newItems {

                    guard
                        let data = try? await item.loadTransferable(type: Data.self),
                        let image = UIImage(data: data)
                    else {
                        continue
                    }

                    images.append(image)
                }

                guard !images.isEmpty else {
                    return
                }

                do {

                    try WalletImportService.importImages(
                        images,
                        kind: .gallery,
                        into: card,
                        in: modelContext
                    )

                    await MainActor.run {

                        modelContext.safeSave(
                            operation: "ImportGalleryImages"
                        )

                        modelContext.processPendingChanges()

                        selectedPhotos.removeAll()
                    }

                } catch {

                    assertionFailure(
                        "Failed to import gallery images: \(error)"
                    )
                }
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

        modelContext.safeSave(
            operation: "SaveLoyaltyCard"
        )

        dismiss()
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
