import SwiftUI
import PDFKit

struct DocumentViewerView: View {

    let asset: DocumentAsset

    @Environment(\.dismiss)
    private var dismiss

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
                          let url = DocumentAssetStore.fileURL(
                            relativePath: asset.relativePath
                          ) {

                    PDFKitView(url: url)

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
        }
    }
}

import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {

    let url: URL

    func makeUIView(context: Context) -> PDFView {

        let pdfView = PDFView()

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(true)

        pdfView.document = PDFDocument(url: url)

        return pdfView
    }

    func updateUIView(
        _ uiView: PDFView,
        context: Context
    ) {

    }
}
