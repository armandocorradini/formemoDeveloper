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
    @State private var frontImageData: Data?
    @State private var backImageData: Data?
    @State private var showBackPhotoPicker = false
    @State private var showingFrontMenu = false
    @State private var showingBackMenu = false

    @State private var viewingImage: UIImage?
    @State private var showImageViewer = false
    
    @State private var showFrontPhotoPicker = false
    @State private var cameraTarget: WalletAssetKind?
    
    
    @State private var frontPickerItem: PhotosPickerItem?
    @State private var backPickerItem: PhotosPickerItem?
    
    private var currentLogoData: Data? {

        if let previewLogoData {
            return previewLogoData
        }

        if let data = LoyaltyCardLogoStore.load(
            asset: card.logoAsset
        ) {
            return data
        }

        if let relativePath = card.loyaltyLogoRelativePath {
            return LoyaltyCardLogoStore.load(
                relativePath: relativePath
            )
        }

        return nil
    }

    private var currentFrontData: Data? {
        if let frontImageData {
            return frontImageData
        }

        return LoyaltyCardLogoStore.load(
            asset: card.frontAsset
        )
    }

    private var currentBackData: Data? {
        if let backImageData {
            return backImageData
        }

        return LoyaltyCardLogoStore.load(
            asset: card.backAsset
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
                                        LoyaltyCardLogoStore.delete(asset: asset)
                                        modelContext.delete(asset)
                                    }

                                    previewLogoData = nil
                                    modelContext.safeSave(
                                        operation: "RemoveLoyaltyLogo"
                                    )
                                    modelContext.processPendingChanges()

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

                     Section("Images") {
                        
                        HStack(alignment: .top, spacing: 20) {

                            // FRONT

                            VStack(alignment: .leading, spacing: 8) {

                                Text("Front")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    showingFrontMenu = true
                                } label: {

                                    Group {

                                        if let data = currentFrontData,
                                           let image = UIImage(data: data) {

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
                                .buttonStyle(.plain)
                                .confirmationDialog(
                                    "Front Image",
                                    isPresented: $showingFrontMenu
                                ) {

                                    Button("Take Photo") {
                                        cameraTarget = .front
                                        presentCamera(target: .front)
                                    }

                                    Button("Choose Photo") {
                                        showFrontPhotoPicker = true
                                    }

                                    if currentFrontData != nil {

                                        Button("View Image") {

                                            if let data = currentFrontData,
                                               let image = UIImage(data: data) {
                                                viewingImage = image
                                                showImageViewer = true
                                            }
                                        }

                                        Button("Remove Image", role: .destructive) {

                                            frontImageData = nil

                                            if let asset = card.frontAsset {
                                                LoyaltyCardLogoStore.delete(asset: asset)
                                                modelContext.delete(asset)
                                            }

                                            modelContext.safeSave(
                                                operation: "RemoveLoyaltyFrontImage"
                                            )
                                            modelContext.processPendingChanges()
                                            
                                        }
                                    }

                                    Button("Cancel", role: .cancel) { }
                                }
                                .photosPicker(
                                    isPresented: $showFrontPhotoPicker,
                                    selection: $frontPickerItem,
                                    matching: .images
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // BACK

                            VStack(alignment: .leading, spacing: 8) {

                                Text("Back")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    showingBackMenu = true
                                } label: {

                                    Group {

                                        if let data = currentBackData,
                                           let image = UIImage(data: data) {

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
                                .buttonStyle(.plain)
                                .confirmationDialog(
                                    "Back Image",
                                    isPresented: $showingBackMenu
                                ) {

                                    Button("Take Photo") {
                                        cameraTarget = .back
                                        presentCamera(target: .front)
                                    }

                                    Button("Choose Photo") {
                                        showBackPhotoPicker = true
                                    }

                                    if currentBackData != nil {

                                        Button("View Image") {

                                            if let data = currentBackData,
                                               let image = UIImage(data: data) {
                                                viewingImage = image
                                                showImageViewer = true
                                            }
                                        }

                                        Button("Remove Image", role: .destructive) {

                                            backImageData = nil

                                            if let asset = card.backAsset {
                                                LoyaltyCardLogoStore.delete(asset: asset)
                                                modelContext.delete(asset)
                                            }

                                            modelContext.safeSave(
                                                operation: "RemoveLoyaltyBackImage"
                                            )
                                            modelContext.processPendingChanges()
                                        }
                                    }

                                    Button("Cancel", role: .cancel) { }
                                }
                                .photosPicker(
                                    isPresented: $showBackPhotoPicker,
                                    selection: $backPickerItem,
                                    matching: .images
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                if card.logoAsset == nil {
                    _ = WalletAsset.createLegacyLogoReference(
                        for: card,
                        in: modelContext
                    )
                }

                previewLogoData = LoyaltyCardLogoStore.load(
                    asset: card.logoAsset
                )

                if previewLogoData == nil,
                   let relativePath = card.loyaltyLogoRelativePath {

                    previewLogoData = LoyaltyCardLogoStore.load(
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

                        if let existing = card.logoAsset {
                            LoyaltyCardLogoStore.delete(asset: existing)
                            modelContext.delete(existing)
                        }

                        _ = WalletAsset.create(
                            kind: .logo,
                            imageData: compressed,
                            for: card,
                            in: modelContext
                        )
                    }

                    modelContext.safeSave(
                        operation: "UpdateLoyaltyLogo"
                    )
                    modelContext.processPendingChanges()
                }
            }
                
            .onChange(of: frontPickerItem) { _, newItem in

                guard let newItem else {
                    return
                }

                Task {

                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        return
                    }

                    let resized = image.resizedForWalletLogo(maxDimension: 1200)

                    guard let compressed = resized.jpegData(compressionQuality: 0.80) else {
                        return
                    }

                    await MainActor.run {

                        frontImageData = compressed

                        if let existing = card.frontAsset {
                            LoyaltyCardLogoStore.delete(asset: existing)
                            modelContext.delete(existing)
                        }

                        _ = WalletAsset.create(
                            kind: .front,
                            imageData: compressed,
                            for: card,
                            in: modelContext
                        )
                    }

                    modelContext.safeSave(
                        operation: "UpdateLoyaltyFrontImage"
                    )
                    modelContext.processPendingChanges()
                }
            }
                
            .onChange(of: backPickerItem) { _, newItem in

                guard let newItem else {
                    return
                }

                Task {

                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        return
                    }

                    let resized = image.resizedForWalletLogo(maxDimension: 1200)

                    guard let compressed = resized.jpegData(compressionQuality: 0.80) else {
                        return
                    }

                    await MainActor.run {

                        backImageData = compressed

                        if let existing = card.backAsset {
                            LoyaltyCardLogoStore.delete(asset: existing)
                            modelContext.delete(existing)
                        }

                        _ = WalletAsset.create(
                            kind: .back,
                            imageData: compressed,
                            for: card,
                            in: modelContext
                        )
                    }

                    modelContext.safeSave(
                        operation: "UpdateLoyaltyBackImage"
                    )
                    modelContext.processPendingChanges()
                }
            }
                
                
            .onChange(of: capturedImage) { _, newImage in

                guard let newImage else {
                    return
                }

                switch cameraTarget {

                case .front:

                    let resized = newImage.resizedForWalletLogo(maxDimension: 1200)

                    guard let compressed = resized.jpegData(compressionQuality: 0.80) else {
                        return
                    }

                    frontImageData = compressed

                    if let existing = card.frontAsset {
                        LoyaltyCardLogoStore.delete(asset: existing)
                        modelContext.delete(existing)
                    }

                    _ = WalletAsset.create(
                        kind: .front,
                        imageData: compressed,
                        for: card,
                        in: modelContext
                    )

                case .back:

                    let resized = newImage.resizedForWalletLogo(maxDimension: 1200)

                    guard let compressed = resized.jpegData(compressionQuality: 0.80) else {
                        return
                    }

                    backImageData = compressed

                    if let existing = card.backAsset {
                        LoyaltyCardLogoStore.delete(asset: existing)
                        modelContext.delete(existing)
                    }

                    _ = WalletAsset.create(
                        kind: .back,
                        imageData: compressed,
                        for: card,
                        in: modelContext
                    )

                default:

                    let resized = newImage.resizedForWalletLogo(maxDimension: 300)

                    guard let compressed = resized.jpegData(compressionQuality: 0.65) else {
                        return
                    }

                    previewLogoData = compressed

                    if let existing = card.logoAsset {
                        LoyaltyCardLogoStore.delete(asset: existing)
                        modelContext.delete(existing)
                    }

                    _ = WalletAsset.create(
                        kind: .logo,
                        imageData: compressed,
                        for: card,
                        in: modelContext
                    )
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
