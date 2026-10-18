import SwiftUI
import SwiftData

struct WalletAssetDetailView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    let card: LoyaltyCard
    let asset: WalletAsset

    @State
    private var showingDeleteConfirmation = false
    @State
    private var image: UIImage?
    @State
    private var loadFinished = false

    var body: some View {

        NavigationStack {

            Group {

                if let image {
                    ZoomableImageView(image: image)
                        .background(.black)
                } else if loadFinished {
                    ContentUnavailableView(
                        "Unable to Open",
                        systemImage: "exclamationmark.triangle"
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItemGroup(placement: .topBarTrailing) {

                    if let url = WalletAssetStore.fileURL(
                        relativePath: asset.relativePath
                    ) {

                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Button(role: .destructive) {

                        showingDeleteConfirmation = true

                    } label: {

                        Image(systemName: "trash")
                    }
                    
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: asset.relativePath) {
            image = nil
            loadFinished = false
            if let data = await WalletAssetStore.loadDataAsync(
                relativePath: asset.relativePath
            ), let loadedImage = UIImage(data: data) {
                guard !Task.isCancelled else { return }
                image = loadedImage
            }
            guard !Task.isCancelled else { return }
            loadFinished = true
        }
        .confirmationDialog(
            "Delete Image",
            isPresented: $showingDeleteConfirmation
        ) {

            Button(
                "Delete",
                role: .destructive
            ) {

                WalletImportService.delete(
                    asset,
                    from: modelContext
                )

                dismiss()
            }

            Button(
                "Cancel",
                role: .cancel
            ) { }
        }
    }
}
