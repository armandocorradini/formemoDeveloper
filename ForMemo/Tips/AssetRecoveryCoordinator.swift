import Foundation
import SwiftData
import os

enum AssetRecoveryCoordinator {
    
    struct RecoveryCheckResult: Identifiable {

        let id = UUID()
        
        var duplicatedContainers: [AssetContainer] = []
        var duplicateFolders: [String] = []
        
        var needsRepair: Bool {
            
            !duplicatedContainers.isEmpty
            
        }
        
    }
    
    
    private static func validRelativePaths(
        for container: AssetContainer,
        context: ModelContext
    ) throws -> Set<String> {

        switch container {
        case .task:
            let assets = try context.fetch(FetchDescriptor<TaskAttachment>())
            return Set(assets.map(\.relativePath).filter { !$0.isEmpty }.map {
                URL(fileURLWithPath: $0).lastPathComponent
            })

        case .wallet:
            let assets = try context.fetch(FetchDescriptor<WalletAsset>())
            return Set(assets.map(\.relativePath).filter { !$0.isEmpty }.map {
                URL(fileURLWithPath: $0).lastPathComponent
            })

        case .document:
            let assets = try context.fetch(FetchDescriptor<DocumentAsset>())
            return Set(assets.map(\.relativePath).filter { !$0.isEmpty }.map {
                URL(fileURLWithPath: $0).lastPathComponent
            })
        }
    }

    /// Fetches every whitelist before allowing any container repair to begin.
    /// A single failed fetch aborts the entire recovery pass (fail-closed).
    static func executeRecoveryPlan(
        for containers: [AssetContainer],
        fetchOperation: (AssetContainer) throws -> Set<String>,
        repairOperation: (AssetContainer, Set<String>) -> Void
    ) throws {
        var whitelists: [AssetContainer: Set<String>] = [:]

        for container in containers {
            whitelists[container] = try fetchOperation(container)
        }

        // No repair is invoked until all fetches have succeeded.
        for container in containers {
            guard let validPaths = whitelists[container] else {
                throw NSError(
                    domain: "AssetRecoveryCoordinator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing asset whitelist for \(container.rawValue)."]
                )
            }
            repairOperation(container, validPaths)
        }
    }

    private static func performRecovery(
        for result: RecoveryCheckResult,
        context: ModelContext
    ) {
        do {
            try executeRecoveryPlan(
                for: result.duplicatedContainers,
                fetchOperation: { container in
                    try validRelativePaths(for: container, context: context)
                },
                repairOperation: { container, validPaths in
                    _ = AttachmentContainerRecovery.repairIfNeeded(
                        container: container,
                        trigger: .automatic,
                        validRelativePaths: validPaths
                    )
                }
            )
        } catch {
            AppLogger.persistence.error(
                "Asset Recovery aborted before file changes because an asset-reference fetch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func checkContainers() -> RecoveryCheckResult {
        var result = RecoveryCheckResult()
        let containers: [AssetContainer] = [.task, .wallet, .document]

        for container in containers {
            let directories: [URL]
            do {
                directories = try AttachmentContainerRecovery.attachmentDirectories(container: container)
            } catch {
                // An unavailable/unreadable iCloud directory is not evidence that
                // no duplicate folders exist. Returning without repair is fail-closed.
                AppLogger.persistence.error(
                    "Asset Recovery check aborted for \(container.rawValue): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }

            let folders = directories
                .filter { directory in
                    let name = directory.lastPathComponent
                    return name != container.rawValue && name != "\(container.rawValue)_Trash"
                }
                .map(\.lastPathComponent)
                .sorted()

            guard !folders.isEmpty else { continue }
            result.duplicatedContainers.append(container)
            result.duplicateFolders.append(contentsOf: folders)

            SystemEventHistory.add(
                SystemEvent(
                    id: UUID(),
                    sessionID: DebugLog.sessionID,
                    date: Date(),
                    category: .assetRecovery,
                    event: .detected,
                    result: .warning,
                    details: "\(container.rawValue): \(folders.count) duplicate folder(s)"
                )
            )
        }
        return result
    }

    static func checkIfNeeded() -> RecoveryCheckResult {
        
        let result = checkContainers()
        
        guard result.needsRepair else {
            
            return result
            
        }
        
        AppLogger.persistence.notice(
            """
            Asset Recovery needed
            
            Containers:
            \(result.duplicatedContainers.map(\.rawValue).joined(separator: "\n"))
            """
        )
        
        return result
        
    }
    
    static func recoverIfNeeded(
        diagnosticsEnabled: Bool,
        context: ModelContext
    ) -> RecoveryCheckResult {
        
        let result = checkIfNeeded()
        
        guard result.needsRepair else {
            return result
        }
        
        if diagnosticsEnabled {
            return result
        }
        
        performRecovery(
            for: result,
            context: context
        )
        
        return result
    }
    
    static func recoverAutomaticallyIfNeeded(
        context: ModelContext
    ) {
        
        _ = recoverIfNeeded(
            diagnosticsEnabled: false,
            context: context
        )
    }
    
    
    static func launchRecoveryCheck() -> RecoveryCheckResult {
        
        AppLogger.persistence.notice(
            "===== Asset Recovery Check START ====="
        )
        let result = checkIfNeeded()

        AppLogger.persistence.notice(
            """
            Asset Recovery

            needsRepair: ♦️ \(result.needsRepair)

            folders:
            \(result.duplicateFolders.joined(separator: "\n"))
            """
        )
        
        
        return result

    }
    
    
    
    static func repairAll(
        context: ModelContext
    ) -> AttachmentRecoveryResult {

        var taskResult = AttachmentRecoveryResult()
        do {
            try executeRecoveryPlan(
                for: [.task, .wallet, .document],
                fetchOperation: { container in
                    try validRelativePaths(for: container, context: context)
                },
                repairOperation: { container, validPaths in
                    let result = AttachmentContainerRecovery.repairIfNeeded(
                        container: container,
                        trigger: .manual,
                        validRelativePaths: validPaths
                    )
                    if container == .task {
                        taskResult = result
                    }
                }
            )
        } catch {
            taskResult.errors = 1
            taskResult.failedFiles = ["Recovery aborted before file changes: \(error.localizedDescription)"]
            AppLogger.persistence.error(
                "Manual Asset Recovery aborted before file changes: \(error.localizedDescription, privacy: .public)"
            )
        }
        return taskResult
    }
    
}
