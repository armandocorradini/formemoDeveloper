import SwiftUI


struct ImagePreviewView: View {

    let image: UIImage?

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {

        NavigationStack {

            ZStack {

                Color.black
                    .ignoresSafeArea()

                if let image {

                    ZoomableImageView(
                        image: image
                    )
                    .ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {

                ToolbarItem(
                    placement: .topBarLeading
                ) {

                    Button {

                        dismiss()

                    } label: {

                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                    }
                }
            }
        }
    }
}

struct ZoomableImageView: View {

    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {

        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .scaleEffect(scale)
            .offset(offset)
            .gesture(

                MagnifyGesture()

                    .onChanged { value in

                        scale = max(
                            1,
                            min(5, lastScale * value.magnification)
                        )
                    }

                    .onEnded { _ in

                        if scale < 1 {

                            withAnimation(.spring()) {

                                scale = 1
                                offset = .zero
                            }
                        }

                        lastScale = scale
                        lastOffset = offset
                    }
            )
        
            .simultaneousGesture(

                DragGesture()

                    .onChanged { value in

                        guard scale > 1 else { return }

                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }

                    .onEnded { _ in

                        lastOffset = offset
                    }
            )
        
            .onTapGesture(count: 2) {

                withAnimation(.spring(duration: 0.28)) {

                    if scale > 1 {

                        scale = 1
                        lastScale = 1

                        offset = .zero
                        lastOffset = .zero

                    } else {

                        scale = 2
                        lastScale = 2
                    }
                }
            }
    }
}
