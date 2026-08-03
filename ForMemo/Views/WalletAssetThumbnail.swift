import SwiftUI

struct WalletAssetThumbnail: View {

    let asset: WalletAsset

    var body: some View {

        Group {

            if let data = WalletAssetStore.loadData(
                relativePath: asset.relativePath
            ),
            let image = UIImage(data: data) {

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
        .clipShape(
            RoundedRectangle(cornerRadius: 12)
        )
        .overlay {

            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary)
        }
    }
}
