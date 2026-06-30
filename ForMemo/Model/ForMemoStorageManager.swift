import Foundation

enum ForMemoStorageManager {

    // MARK: - Public

    static func usedStorage() -> Int64 {

        totalSize(
            of:
                TaskAttachment.attachmentsDirectory,
                LoyaltyCardLogoStore.directoryURL
        )
    }

    static func usedStorageString() -> String {

        ByteCountFormatter.string(
            fromByteCount: usedStorage(),
            countStyle: .file
        )
    }

    // MARK: - Private

    private static func totalSize(
        of directories: URL?...
    ) -> Int64 {

        directories.reduce(Int64.zero) {
            $0 + directorySize(of: $1)
        }
    }

    private static func directorySize(
        of directory: URL?
    ) -> Int64 {

        guard let directory else {
            return 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ],
            options: [
                .skipsHiddenFiles
            ]
        ) else {
            return 0
        }

        var total: Int64 = 0

        for case let fileURL as URL in enumerator {

            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .fileSizeKey
                    ]
                ),
                values.isRegularFile == true,
                let size = values.fileSize
            else {
                continue
            }

            total += Int64(size)
        }

        return total
    }
}



//Quando implementerai gli allegati dei documenti (PDF, immagini, ecc.), basterà aggiungere una sola riga:
//DocumentAttachmentStore.directoryURL
