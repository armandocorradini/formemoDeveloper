import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import QuickLook

struct WalletViewerView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Bindable var card: LoyaltyCard
    let showsAddButton: Bool

    let onCameraRequested: (WalletAssetKind) -> Void

    @State private var showingGalleryMenu = false
    @State private var showGalleryPhotoPicker = false
    @State private var galleryPickerItems: [PhotosPickerItem] = []
    @State private var importedDocumentURL: URL?
    @State private var selectedAsset: WalletAsset?

  

    
    init(
        card: LoyaltyCard,
        showsAddButton: Bool = true,
        onCameraRequested: @escaping (WalletAssetKind) -> Void
    ) {
        self._card = Bindable(card)
        self.showsAddButton = showsAddButton
        self.onCameraRequested = onCameraRequested
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            ScrollView(.horizontal) {

                LazyHStack(
                    spacing: 12
                ) {

                    ForEach(card.galleryAssets) { asset in

                        WalletAssetThumbnail(
                            asset: asset
                        )
                        .onTapGesture {

                            selectedAsset = asset
                        }
                     
                    }

                    if showsAddButton {
                        addButton
                    }
                    
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 130)
        } 
        .confirmationDialog(
            String(localized: "Add"),
            isPresented: $showingGalleryMenu
        ) {

            Button(String(localized: "Take Photo")) {
                onCameraRequested(.gallery)
            }

            Button(String(localized: "Choose Photo")) {
                showGalleryPhotoPicker = true
            }


            Button(
                String(localized: "Cancel"),
                role: .cancel
            ) { }

        }
        .photosPicker(
            isPresented: $showGalleryPhotoPicker,
            selection: $galleryPickerItems,
            maxSelectionCount: nil,
            matching: .images
        )
        .onChange(of: galleryPickerItems) { _, items in

            Task {

                var images: [Data] = []

                for item in items {

                        guard
                            let data = try? await item.loadTransferable(type: Data.self)
                        else {
                            continue
                        }

                        images.append(data)
                }

                guard !images.isEmpty else {
                    return
                }

                do {

                    try WalletImportService.importImages(
                        images,
                        into: card,
                        in: modelContext
                    )

                    modelContext.safeSave(
                        operation: "ImportGalleryImages"
                    )

                    modelContext.processPendingChanges()

                } catch {

                    assertionFailure(
                        "Gallery import failed: \(error)"
                    )
                }

                galleryPickerItems.removeAll()
            }
        }

        .fullScreenCover(item: $selectedAsset) { asset in

            NavigationStack {

                WalletAssetDetailView(
                    card: card,
                    asset: asset
                )
            }
        }
    
    }
    
    private var addButton: some View {

        Button {

            showingGalleryMenu = true

        } label: {

            RoundedRectangle(
                cornerRadius: 12
            )
            .fill(.secondary.opacity(0.15))
            .frame(width: 90, height: 120)
            .overlay {

                Image(systemName: "plus")
                    .font(.title2)
            }
        }
        .buttonStyle(.plain)
    }
    
    
}
