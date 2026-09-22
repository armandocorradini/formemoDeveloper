//import Foundation
//import SwiftData
//
//enum AttachmentDiagnosticService {
//
//    @MainActor
//    static func update(using context: ModelContext) {
//
//        let descriptor = FetchDescriptor<TaskAttachment>(
//            predicate: #Predicate<TaskAttachment> {
//                $0.task?.isCompleted == false
//            }
//        )
//
//        guard let activeAttachments = try? context.fetch(descriptor) else {
//            AppSettings.shared.diagnosticAttachmentFailure = false
//            return
//        }
//
//        guard !activeAttachments.isEmpty else {
//            AppSettings.shared.diagnosticAttachmentFailure = false
//            return
//        }
//
//        let urls = activeAttachments.compactMap(\.fileURL)
//
//        Task.detached(priority: .utility) {
//            let totalBytes = urls.reduce(Int64(0)) { total, url in
//                guard let size = try? url.resourceValues(
//                    forKeys: [.fileSizeKey]
//                ).fileSize else {
//                    return total
//                }
//
//                return total + Int64(size)
//            }
//
//            let diagnosticFailure = totalBytes == 0
//
//            await MainActor.run {
//                AppSettings.shared.diagnosticAttachmentFailure = diagnosticFailure
//            }
//        }
//    }
//}
