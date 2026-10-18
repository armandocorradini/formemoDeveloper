import SwiftUI

struct DocumentAssetThumbnail: View {

    let asset: DocumentAsset

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if asset.isImage {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if isLoading {
                    placeholder { ProgressView() }
                } else if loadFailed {
                    placeholder {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                    }
                }
            } else if asset.isPDF,
                      let url = DocumentAssetStore.fileURL(
                          relativePath: asset.relativePath
                      ) {
                PDFThumbnail(url: url)
            } else {
                placeholder {
                    Image(systemName: "doc")
                        .font(.title2)
                }
            }
        }
        .frame(width: 90, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary)
        }
        .task(id: asset.relativePath) {
            guard asset.isImage else {
                isLoading = false
                return
            }

            image = nil
            loadFailed = false
            isLoading = true
            image = await DocumentAssetStore.loadImageAsync(
                relativePath: asset.relativePath
            )
            isLoading = false
            loadFailed = image == nil
        }
    }

    private func placeholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
            content()
        }
    }
}
