import Foundation

enum LegacyLoyaltyCardLogoStore {

    private static let folderName = "LoyaltyCardLogos"

    static func loadLegacy(
        relativePath: String
    ) -> Data? {

        guard
            let localDirectory = FileManager.default
                .urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )
                .first?
                .appendingPathComponent(
                    folderName,
                    isDirectory: true
                )
        else {
            return nil
        }

        let fileURL = localDirectory
            .appendingPathComponent(relativePath)

        return try? Data(contentsOf: fileURL)
    }
}
