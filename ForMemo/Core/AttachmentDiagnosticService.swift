import Foundation
import SwiftData

enum AttachmentDiagnosticService {

    @MainActor
    static func update(using context: ModelContext) {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { !$0.isCompleted }
        )

        guard let tasks = try? context.fetch(descriptor) else {
            AppSettings.shared.diagnosticAttachmentFailure = false
            return
        }

        let activeAttachments = tasks.flatMap { $0.attachments ?? [] }

        guard !activeAttachments.isEmpty else {
            AppSettings.shared.diagnosticAttachmentFailure = false
            return
        }

        let urls = activeAttachments.compactMap(\.fileURL)

        Task.detached(priority: .utility) {
            let totalBytes = urls.reduce(Int64(0)) { total, url in
                guard let size = try? url.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize else {
                    return total
                }

                return total + Int64(size)
            }

            let diagnosticFailure = totalBytes == 0

            await MainActor.run {
                AppSettings.shared.diagnosticAttachmentFailure = diagnosticFailure
            }
        }
    }
}
