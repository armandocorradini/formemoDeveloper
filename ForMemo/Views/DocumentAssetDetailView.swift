import SwiftUI
import SwiftData

struct DocumentAssetDetailView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    let document: DocumentItem
    let asset: DocumentAsset

    @State
    private var showingDeleteConfirmation = false

    var body: some View {

        NavigationStack {

            DocumentViewerView(
                asset: asset
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .topBarLeading) {

                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {

                    ShareLink(
                        item: asset.fileURL ?? URL(fileURLWithPath: "")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {

                        showingDeleteConfirmation = true

                    } label: {

                        Image(systemName: "trash")
                    }
                }
            }
        }
        .confirmationDialog(
            String(localized: "Delete Page"),
            isPresented: $showingDeleteConfirmation
        ) {

            Button(
                String(localized: "Delete"),
                role: .destructive
            ) {

                DocumentImportService.delete(
                    asset,
                    from: document,
                    in: modelContext
                )

                dismiss()
            }

            Button(
                String(localized: "Cancel"),
                role: .cancel
            ) { }
        }
    }
}
