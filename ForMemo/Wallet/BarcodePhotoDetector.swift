import Foundation
import UIKit
import ZXingCpp
import Vision

enum BarcodeSupport {

    static let supportedSymbologies: [VNBarcodeSymbology] = [
        .aztec,
        .codabar,
        .code128,
        .code39,
        .code39Checksum,
        .code39FullASCII,
        .code39FullASCIIChecksum,
        .code93,
        .code93i,
        .dataMatrix,
        .ean13,
        .ean8,
        .gs1DataBar,
        .gs1DataBarExpanded,
        .gs1DataBarLimited,
        .i2of5,
        .i2of5Checksum,
        .itf14,
        .microPDF417,
        .microQR,
        .msiPlessey,
        .pdf417,
        .qr,
        .upce
    ]

    static func isSupported(
        _ symbology: VNBarcodeSymbology
    ) -> Bool {
        supportedSymbologies.contains(symbology)
    }
}

struct BarcodePhotoDetector {

    enum DetectionError: Error {
        case noSupportedBarcode
    }

    static func detect(
        in data: Data
    ) throws -> (value: String, format: String) {

        guard let image = UIImage(data: data) else {
            throw DetectionError.noSupportedBarcode
        }

        let normalizedImage = UIGraphicsImageRenderer(
            size: image.size
        ).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        guard let cgImage = normalizedImage.cgImage else {
            throw DetectionError.noSupportedBarcode
        }

        let options = ZXIReaderOptions()

        // ZXing searches all supported formats when no specific
        // format list is supplied.
        options.tryHarder = true
        options.tryRotate = true
        options.tryInvert = true
        options.tryDownscale = true
        options.maxNumberOfSymbols = 1

        let reader = ZXIBarcodeReader(options: options)

       

        let results: [ZXIResult]

        do {
            results = try reader.read(cgImage)
        } catch {
            throw DetectionError.noSupportedBarcode
        }

        guard let result = results.first else {
            throw DetectionError.noSupportedBarcode
        }

        let value = result.text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )

        guard !value.isEmpty else {
            throw DetectionError.noSupportedBarcode
        }

        return (
            value,
            formatName(for: result.format)
        )
    }

    private static func formatName(
        for format: ZXIFormat
    ) -> String {

        switch format.rawValue {
        case 1:
            return "aztec"
        case 2:
            return "codabar"
        case 3:
            return "code39"
        case 4:
            return "code93"
        case 5:
            return "code128"
        case 6:
            return "gs1DataBar"
        case 7:
            return "gs1DataBarExpanded"
        case 8:
            return "gs1DataBarStacked"
        case 9:
            return "gs1DataBarExpandedStacked"
        case 10:
            return "gs1DataBarLimited"
        case 11:
            return "dataMatrix"
        case 12:
            return "dxFilmEdge"
        case 13:
            return "telepen"
        case 14:
            return "ean8"
        case 15:
            return "ean13"
        case 16:
            return "itf"
        case 17:
            return "maxicode"
        case 18:
            return "pdf417"
        case 19:
            return "qr"
        case 20:
            return "microQR"
        case 21:
            return "rmQR"
        case 22:
            return "upca"
        case 23:
            return "upce"
        default:
            return "unknown"
        }
    }
}
