
import Foundation

enum LoyaltyCardLogoStore {

    private static let folderName = "LoyaltyCardLogos"

    static var directoryURL: URL? {

        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    @discardableResult
    static func save(
        imageData: Data,
        for cardID: UUID
    ) -> String? {

        guard let directoryURL else {
            return nil
        }

        do {

            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let fileName = "\(cardID.uuidString).jpg"

            let fileURL = directoryURL.appendingPathComponent(fileName)

            try imageData.write(
                to: fileURL,
                options: .atomic
            )

            return fileName

        } catch {

            return nil
        }
    }

    static func load(relativePath: String?) -> Data? {

        guard let relativePath,
              let directoryURL else {
            return nil
        }

        let fileURL = directoryURL.appendingPathComponent(relativePath)

        return try? Data(contentsOf: fileURL)
    }

    static func delete(relativePath: String?) {

        guard let relativePath,
              let directoryURL else {
            return
        }

        let fileURL = directoryURL.appendingPathComponent(relativePath)

        try? FileManager.default.removeItem(at: fileURL)
    }
}
