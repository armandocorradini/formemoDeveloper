import SwiftUI
import PDFKit

struct PDFThumbnail: View {

    let url: URL

    var body: some View {

        Group {

            if let image = thumbnail {

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()

            } else {

                ZStack {

                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)

                    Image(systemName: "doc.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var thumbnail: UIImage? {

        guard
            let document = PDFDocument(url: url),
            let page = document.page(at: 0)
        else {
            return nil
        }

        let targetSize = CGSize(width: 180, height: 240)

        return page.thumbnail(
            of: targetSize,
            for: .cropBox
        )
    }
}
