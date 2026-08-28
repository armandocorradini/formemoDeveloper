import UIKit
import UniformTypeIdentifiers
import os


final class ShareViewController: UIViewController {

    private let appGroupIdentifier =
        "group.corradini.armando.NewTask"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        importNote()
    }

    private func importNote() {
        guard let item =
            extensionContext?.inputItems.first
                as? NSExtensionItem
        else {
            finish()
            return
        }

        let providers = item.attachments ?? []

        Task {
            do {
                let payload =
                    try await readNote(from: providers)

                try writePayload(payload)

                await MainActor.run {
                    openForMemo()
                }

            } catch {
                await MainActor.run {
                    finish()
                }
            }
        }
    }

    private func readNote(
        from providers: [NSItemProvider]
    ) async throws -> ImportedNotePayload {
        
        print("FORMEMO_SHARE_EXTENSION_READNOTE")
        
        print("========== FORMEMO SHARE EXTENSION ==========")

        for (index, provider) in providers.enumerated() {
            print("PROVIDER \(index)")
            print("TYPES:")
            
            for type in provider.registeredTypeIdentifiers {
                print("  \(type)")
            }
        }

        print("=============================================")

        // Preferiamo RTF: è la rappresentazione più utile
        // per conservare la formattazione di Apple Notes.
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(
                UTType.rtf.identifier
            ) {
                let data =
                    try await loadData(
                        provider,
                        typeIdentifier:
                            UTType.rtf.identifier
                    )

                if let attributed =
                    try? NSAttributedString(
                        data: data,
                        options: [
                            .documentType:
                                NSAttributedString.DocumentType.rtf
                        ],
                        documentAttributes: nil
                    ) {
                    return makePayload(
                        from: attributed
                    )
                }
            }
        }

        // Fallback HTML.
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(
                UTType.html.identifier
            ) {
                let data =
                    try await loadData(
                        provider,
                        typeIdentifier:
                            UTType.html.identifier
                    )

                if let attributed =
                    try? NSAttributedString(
                        data: data,
                        options: [
                            .documentType:
                                NSAttributedString.DocumentType.html
                        ],
                        documentAttributes: nil
                    ) {
                    return makePayload(
                        from: attributed
                    )
                }
            }
        }

        // Ultimo fallback: testo semplice.
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(
                UTType.plainText.identifier
            ) {
                let text =
                    try await loadString(
                        provider,
                        typeIdentifier:
                            UTType.plainText.identifier
                    )

                return makePayload(
                    from: NSAttributedString(
                        string: text
                    )
                )
            }
        }

        throw ImportError.unsupportedContent
    }

    private func makePayload(
        from attributed:
            NSAttributedString
    ) -> ImportedNotePayload {

        let text = attributed.string
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let title =
            text.components(
                separatedBy: .newlines
            )
            .first {
                !$0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            } ?? "Note"

        let data =
            (try? NSKeyedArchiver.archivedData(
                withRootObject: attributed,
                requiringSecureCoding: false
            )) ?? Data()

        return ImportedNotePayload(
            title: title,
            attributedTextData: data
        )
    }

    private func writePayload(
        _ payload: ImportedNotePayload
    ) throws {

        guard let container =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
            )
        else {
            throw ImportError.appGroupUnavailable
        }

        let url =
            container.appendingPathComponent(
                "ForMemo-PendingNoteImport.json"
            )

        let data =
            try JSONEncoder().encode(payload)

        try data.write(
            to: url,
            options: .atomic
        )
    }

    private func openForMemo() {

        guard let url =
            URL(string: "formemo://import-note")
        else {
            finish()
            return
        }

        extensionContext?.open(
            url
        ) { [weak self] _ in
            self?.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(
            returningItems: nil
        )
    }

    private func loadData(
        _ provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {

        try await withCheckedThrowingContinuation {
            continuation in

            provider.loadDataRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { data, error in

                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else if let data {
                    continuation.resume(
                        returning: data
                    )
                } else {
                    continuation.resume(
                        throwing:
                            ImportError.missingData
                    )
                }
            }
        }
    }

    private func loadString(
        _ provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> String {

        try await withCheckedThrowingContinuation {
            continuation in

            provider.loadItem(
                forTypeIdentifier: typeIdentifier,
                options: nil
            ) { item, error in

                if let error {
                    continuation.resume(
                        throwing: error
                    )
                    return
                }

                if let string = item as? String {
                    continuation.resume(
                        returning: string
                    )
                    return
                }

                if let data = item as? Data,
                   let string = String(
                       data: data,
                       encoding: .utf8
                   ) {
                    continuation.resume(
                        returning: string
                    )
                    return
                }

                continuation.resume(
                    throwing:
                        ImportError.missingData
                )
            }
        }
    }

    private enum ImportError: Error {
        case unsupportedContent
        case missingData
        case appGroupUnavailable
    }
}

struct ImportedNotePayload: Codable {
    let title: String
    let attributedTextData: Data
}
