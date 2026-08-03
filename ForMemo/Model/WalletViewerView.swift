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
    @State private var galleryPickerItem: PhotosPickerItem?
    @State private var importedDocumentURL: URL?
    @State private var selectedAsset: WalletAsset?

    @State private var showingPDFImporter = false

    
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
                        .contextMenu {

                            Button(
                                role: .destructive
                            ) {
                                WalletImportService.delete(
                                    asset,
                                    from: modelContext
                                )

                            } label: {

                                Label(
                                    String(localized: "Delete"),
                                    systemImage: "trash"
                                )
                            }
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
                onCameraRequested(.front)
            }

            Button(String(localized: "Choose Photo")) {
                showGalleryPhotoPicker = true
            }

            Button(
                String(localized: "Import PDF")
            ) {
                showingPDFImporter = true
            }

            Button(
                String(localized: "Cancel"),
                role: .cancel
            ) { }

        }
        .photosPicker(
            isPresented: $showGalleryPhotoPicker,
            selection: $galleryPickerItem,
            matching: .images
        )
        .onChange(of: galleryPickerItem) { _, item in

            guard let item else {
                return
            }

            Task {

                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    return
                }

                do {

                    try WalletImportService.importImages(
                        [image],
                        into: card,
                        in: modelContext
                    )

                } catch {

                    assertionFailure(
                        "Gallery import failed: \(error)"
                    )
                }

                galleryPickerItem = nil
            }
        }
        .fileImporter(
            isPresented: $showingPDFImporter,
            allowedContentTypes: [.pdf]
        ) { result in

            do {

                let url = try result.get()

                try WalletImportService.importDocuments(
                    from: [url],
                    into: card,
                    in: modelContext
                )

            } catch {

                assertionFailure(
                    "PDF import failed: \(error)"
                )
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
