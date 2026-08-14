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
    
    
    private static func checkContainers() -> RecoveryCheckResult {
        
        var result = RecoveryCheckResult()
        
        let containers: [AssetContainer] = [
            .task,
            .wallet,
            .document
        ]
        
        for container in containers {
            
            let folders = AttachmentContainerRecovery
                .attachmentDirectories(container: container)
                .filter { directory in

                    let name = directory.lastPathComponent

                    return name != container.rawValue &&
                           name != "\(container.rawValue)_Trash"
                }
                .map(\.lastPathComponent)
                .sorted()

            guard !folders.isEmpty else {
                continue
            }

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
    
    private static func validRelativePaths(
        for container: AssetContainer,
        context: ModelContext
    ) -> Set<String> {

        switch container {

        case .task:
            let assets = (try? context.fetch(
                FetchDescriptor<TaskAttachment>()
            )) ?? []

            return Set(
                assets
                    .map(\.relativePath)
                    .filter { !$0.isEmpty }
                    .map {
                        URL(fileURLWithPath: $0).lastPathComponent
                    }
            )

        case .wallet:
            let assets = (try? context.fetch(
                FetchDescriptor<WalletAsset>()
            )) ?? []

            return Set(
                assets
                    .map(\.relativePath)
                    .filter { !$0.isEmpty }
                    .map {
                        URL(fileURLWithPath: $0).lastPathComponent
                    }
            )

        case .document:
            let assets = (try? context.fetch(
                FetchDescriptor<DocumentAsset>()
            )) ?? []

            return Set(
                assets
                    .map(\.relativePath)
                    .filter { !$0.isEmpty }
                    .map {
                        URL(fileURLWithPath: $0).lastPathComponent
                    }
            )
        }
    }
    
    private static func performRecovery(
        for result: RecoveryCheckResult,
        context: ModelContext
    ) {
        
        AppLogger.persistence.notice(
            "===== Asset Recovery EXECUTING ====="
        )
        
        if result.duplicatedContainers.contains(.task) {
            
            _ = AttachmentContainerRecovery.repairIfNeeded(
                container: .task,
                trigger: .automatic,
                validRelativePaths: validRelativePaths(
                    for: .task,
                    context: context
                )
            )
        }
        
        if result.duplicatedContainers.contains(.wallet) {
            
            _ = AttachmentContainerRecovery.repairIfNeeded(
                container: .wallet,
                trigger: .automatic,
                validRelativePaths: validRelativePaths(
                    for: .wallet,
                    context: context
                )
            )
        }
        
        if result.duplicatedContainers.contains(.document) {
            
            _ = AttachmentContainerRecovery.repairIfNeeded(
                container: .document,
                trigger: .automatic,
                validRelativePaths: validRelativePaths(
                    for: .document,
                    context: context
                )
            )
        }
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

            needsRepair: \(result.needsRepair)

            folders:
            \(result.duplicateFolders.joined(separator: "\n"))
            """
        )
        
        
        return result

    }
    
    
    
    static func repairAll(
        context: ModelContext
    ) -> AttachmentRecoveryResult {

        let taskResult = AttachmentContainerRecovery.repairIfNeeded(
            container: .task,
            trigger: .manual,
            validRelativePaths: validRelativePaths(
                for: .task,
                context: context
            )
        )

        _ = AttachmentContainerRecovery.repairIfNeeded(
            container: .wallet,
            trigger: .manual,
            validRelativePaths: validRelativePaths(
                for: .wallet,
                context: context
            )
        )

        _ = AttachmentContainerRecovery.repairIfNeeded(
            container: .document,
            trigger: .manual,
            validRelativePaths: validRelativePaths(
                for: .document,
                context: context
            )
        )

        return taskResult
    }
    
}
