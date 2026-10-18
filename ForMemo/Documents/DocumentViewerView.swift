import SwiftUI
import PDFKit

struct DocumentViewerView: View {

    let asset: DocumentAsset

    @Environment(\.dismiss)
    private var dismiss

    @State private var image: UIImage?
    @State private var pdfData: Data?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if asset.isImage, let image {
                    ZoomableImageView(image: image)
                        .background(.black)
                } else if asset.isPDF, let pdfData {
                    PDFKitView(data: pdfData)
                } else {
                    ContentUnavailableView(
                        loadFailed ? "Unable to Open" : "No Preview Available",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: asset.relativePath) {
                isLoading = true
                loadFailed = false
                image = nil
                pdfData = nil

                if asset.isImage {
                    image = await DocumentAssetStore.loadImageAsync(
                        relativePath: asset.relativePath
                    )
                } else if asset.isPDF {
                    pdfData = await DocumentAssetStore.loadDataAsync(
                        relativePath: asset.relativePath
                    )
                }

                loadFailed = image == nil && pdfData == nil
                isLoading = false
            }
        }
    }
}

struct PDFKitView: UIViewRepresentable {

    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(true)
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
