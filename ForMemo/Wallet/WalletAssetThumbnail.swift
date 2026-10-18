import SwiftUI

struct WalletAssetThumbnail: View {

    let asset: WalletAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                    Image(systemName: "photo")
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
            image = nil
            guard let data = await WalletAssetStore.loadDataAsync(
                relativePath: asset.relativePath
            ), let loadedImage = UIImage(data: data) else {
                return
            }
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}
