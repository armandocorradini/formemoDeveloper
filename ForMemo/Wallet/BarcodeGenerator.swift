import SwiftUI
import UIKit
import ZXingCpp

struct BarcodeGenerator {

    func generate(
        from value: String,
        format: String = "Code128"
    ) -> UIImage? {

        guard !value.isEmpty else {
            return nil
        }

        guard let zxingFormat = zxingFormat(for: format) else {
            return nil
        }

        let is2D = isTwoDimensional(zxingFormat)
        let width = is2D ? 220 : 320
        let height = is2D ? 220 : 92
        let margin = is2D ? 1 : 7

        let options = ZXIWriterOptions(
            format: zxingFormat,
            width: Int32(width),
            height: Int32(height),
            ecLevel: 0,
            margin: Int32(margin)
        )

        let writer = ZXIBarcodeWriter(options: options)

  
        do {
            let unmanagedImage = try writer.write(value)
            let cgImage = unmanagedImage.takeUnretainedValue()
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private func zxingFormat(
        for format: String
    ) -> ZXIFormat? {

        let normalized = format
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        // ZXIFormat raw values are defined by ZXing-C++ 3.1.1.
        if let rawValue = Int(normalized),
           let result = ZXIFormat(rawValue: rawValue) {
            return result
        }

        switch normalized {
        case "aztec", "vnbarcodesymbologyaztec":
            return ZXIFormat(rawValue: 1)

        case "codabar", "vnbarcodesymbologycodabar":
            return ZXIFormat(rawValue: 2)

        case "code39", "vnbarcodesymbologycode39":
            return ZXIFormat(rawValue: 3)

        case "code93", "vnbarcodesymbologycode93":
            return ZXIFormat(rawValue: 4)

        case "code128", "vnbarcodesymbologycode128":
            return ZXIFormat(rawValue: 5)

        case "databar", "gs1databar", "vnbarcodesymbologygs1databar":
            return ZXIFormat(rawValue: 6)

        case "databarexpanded", "gs1databarexpanded",
             "vnbarcodesymbologygs1databarexpanded":
            return ZXIFormat(rawValue: 7)

        case "databarstacked":
            return ZXIFormat(rawValue: 8)

        case "databarexpandedstacked":
            return ZXIFormat(rawValue: 9)

        case "databarlimited", "gs1databarlimited",
             "vnbarcodesymbologygs1databarlimited":
            return ZXIFormat(rawValue: 10)

        case "datamatrix", "vnbarcodesymbologydatamatrix":
            return ZXIFormat(rawValue: 11)

        case "dxfilmedge":
            return ZXIFormat(rawValue: 12)

        case "telepen":
            return ZXIFormat(rawValue: 13)

        case "ean8", "ean-8", "vnbarcodesymbologyean8":
            return ZXIFormat(rawValue: 14)

        case "ean13", "ean-13", "vnbarcodesymbologyean13":
            return ZXIFormat(rawValue: 15)

        case "itf", "itf14", "i2of5", "vnbarcodesymbologyitf14":
            return ZXIFormat(rawValue: 16)

        case "maxicode", "vnbarcodesymbologymaxicode":
            return ZXIFormat(rawValue: 17)

        case "pdf417", "vnbarcodesymbologypdf417":
            return ZXIFormat(rawValue: 18)

        case "qr", "qrcode", "vnbarcodesymbologyqr":
            return ZXIFormat(rawValue: 19)

        case "microqr", "microqrcode", "vnbarcodesymbologymicroqr":
            return ZXIFormat(rawValue: 20)

        case "rmqr", "rmqrcode":
            return ZXIFormat(rawValue: 21)

        case "upca", "upc-a", "vnbarcodesymbologyupca":
            return ZXIFormat(rawValue: 22)

        case "upce", "upc-e", "vnbarcodesymbologyupce":
            return ZXIFormat(rawValue: 23)

        default:
            return nil
        }
    }

    private func isTwoDimensional(
        _ format: ZXIFormat
    ) -> Bool {

        switch format.rawValue {
        case 1, 11, 17, 18, 19, 20, 21:
            return true
        default:
            return false
        }
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
