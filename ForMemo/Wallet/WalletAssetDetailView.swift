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

    var body: some View {

        NavigationStack {

            Group {

                if let data = WalletAssetStore.loadData(
                    relativePath: asset.relativePath
                ),
                let image = UIImage(data: data) {

                    ZoomableImageView(image: image)
                        .background(.black)

                } else {

                    ContentUnavailableView(
                        "Unable to Open",
                        systemImage: "exclamationmark.triangle"
                    )
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
