import Foundation

/// Accesso ai loghi legacy delle carte fedeltà.
enum LegacyLoyaltyCardLogoStore {

    enum LoadError: LocalizedError {
        case documentsDirectoryUnavailable
        case emptyFile(String)

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                return "The legacy loyalty logo directory is unavailable."
            case .emptyFile(let path):
                return "The legacy loyalty logo file is empty: \(path)"
            }
        }
    }

    private static let folderName = "LoyaltyCardLogos"

    /// Returns nil only when the requested file does not exist.
    /// Existing but unreadable/corrupt files throw, so migration cannot mistake
    /// an I/O failure for a card that never had a legacy logo.
    static func loadLegacy(relativePath: String) throws -> Data? {
        guard let documentsDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first else {
            throw LoadError.documentsDirectoryUnavailable
        }

        let directory = documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
        let fileURL = directory.appendingPathComponent(relativePath)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            throw LoadError.emptyFile(relativePath)
        }
        return data
    }
}
