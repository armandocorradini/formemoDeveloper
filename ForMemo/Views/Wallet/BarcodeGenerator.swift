import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct BarcodeGenerator {

    private let context = CIContext()

    func generate(
        from value: String,
        format: String = "Code128"
    ) -> UIImage? {

        let data = Data(value.utf8)

        let normalizedFormat = format.lowercased()

        let image: CIImage?
        let scale: CGFloat

        if normalizedFormat == "qr" ||
            normalizedFormat.contains("qr") {

            let filter = CIFilter.qrCodeGenerator()
            filter.message = data
            image = filter.outputImage
            scale = 12

        } else if normalizedFormat.contains("pdf417") {

            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = data
            image = filter.outputImage
            scale = 3

        } else if normalizedFormat.contains("aztec") {

            let filter = CIFilter.aztecCodeGenerator()
            filter.message = data
            image = filter.outputImage
            scale = 8

        } else {

            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = data
            filter.quietSpace = 7
            image = filter.outputImage
            scale = 4
        }

        guard let image else {
            return nil
        }

        let transformed = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        guard let cgImage = context.createCGImage(
            transformed,
            from: transformed.extent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Barcode Image View

struct GeneratedBarcodeView: View {

    let value: String
    let format: String

    private let generator = BarcodeGenerator()

    var body: some View {

        Group {

            if let image = generator.generate(
                from: value,
                format: format
            ) {

                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()

            } else {

                ContentUnavailableView(
                    "Barcode Unavailable",
                    systemImage: "barcode"
                )
            }
        }
    }
}
