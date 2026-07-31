

import SwiftUI

struct DocumentAssetThumbnail: View {

    let asset: DocumentAsset

    var body: some View {

        Group {

            if asset.isImage,
               let image = DocumentAssetStore.loadImage(
                    relativePath: asset.relativePath
               ) {

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()

            } else if asset.isPDF,
                      let url = DocumentAssetStore.fileURL(
                          relativePath: asset.relativePath
                      ) {

                  PDFThumbnail(url: url)

              } else {

                ZStack {

                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)

                    Image(systemName: "questionmark")
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
    }
}
