import SwiftUI
import PDFKit

struct DocumentViewerView: View {

    let asset: DocumentAsset

    @Environment(\.dismiss)
    private var dismiss

    @State private var pdfData: Data?

    var body: some View {

        NavigationStack {

            Group {

                if asset.isImage,
                   let image = DocumentAssetStore.loadImage(
                        relativePath: asset.relativePath
                   ) {

                    ZoomableImageView(image: image)
                        .background(.black)

                } else if asset.isPDF,
                          let pdfData {

                    PDFKitView(data: pdfData)

                } else {

                    ContentUnavailableView(
                        "Unable to Open",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .topBarTrailing) {

                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                guard asset.isPDF else { return }

                pdfData = DocumentAssetStore.loadData(
                    relativePath: asset.relativePath
                )
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

    func updateUIView(
        _ uiView: PDFView,
        context: Context
    ) {

    }
}
