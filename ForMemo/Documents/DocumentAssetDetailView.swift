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

    @State private var shareURL: URL?
    @State private var isPreparingShare = true

    var body: some View {

        NavigationStack {

            DocumentViewerView(
                asset: asset
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

//                ToolbarItem(placement: .topBarLeading) {
//
//                    Button("Closex") {
//                        dismiss()
//                    }
//                }

                ToolbarItemGroup(placement: .topBarTrailing) {

                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    } else if isPreparingShare {
                        ProgressView()
                            .accessibilityLabel(Text("Preparing attachment"))
                    } else {
                        Button {
                            Task {
                                await prepareShareURL()
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("Retry preparing attachment"))
                    }

                    Button(role: .destructive) {

                        showingDeleteConfirmation = true

                    } label: {

                        Image(systemName: "trash")
                    }
                }
            }
        }
        .task(id: asset.relativePath) {
            await prepareShareURL()
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

    @MainActor
    private func prepareShareURL() async {
        isPreparingShare = true
        shareURL = nil
        defer { isPreparingShare = false }

        guard asset.isImage || asset.isPDF else { return }

        guard await DocumentAssetStore.loadDataAsync(
            relativePath: asset.relativePath
        ) != nil,
        let url = DocumentAssetStore.fileURL(
            relativePath: asset.relativePath
        ),
        FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        shareURL = url
    }
}
