import Foundation
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
    
    private static func performRecovery(
        for result: RecoveryCheckResult
    ) {
        
        AppLogger.persistence.notice(
            "===== Asset Recovery EXECUTING ====="
        )
        
        if result.duplicatedContainers.contains(.task) {
            
            _ = AttachmentContainerRecovery.repairIfNeeded(
                container: .task,
                trigger: .automatic
            )
            
        }
        
        if result.duplicatedContainers.contains(.wallet) {
            
            _ = AttachmentContainerRecovery.repairIfNeeded(
                container: .wallet,
                trigger: .automatic
            )
            
        }
        
        if result.duplicatedContainers.contains(.document) {
            
            _ = AttachmentContainerRecovery.repairIfNeeded(
                container: .document,
                trigger: .automatic
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
        diagnosticsEnabled: Bool
    ) -> RecoveryCheckResult {
        
        let result = checkIfNeeded()
        
        guard result.needsRepair else {
            
            return result
            
        }
        
        if diagnosticsEnabled {
            
            return result
            
        }
        
        performRecovery(for: result)
        
        return result
    }
    
    static func recoverAutomaticallyIfNeeded() {
        
        _ = recoverIfNeeded(
            diagnosticsEnabled: false
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
        
        
        guard result.needsRepair else {

            return result

        }

        if DiagnosticsOptions.assetRecoveryDiagnostics {

            AppLogger.persistence.notice(
                "Asset Recovery paused (diagnostics enabled)"
            )

            return result

        }

        performRecovery(for: result)

        return result

    }
    
    
    
    static func repairAll() -> AttachmentRecoveryResult {

        let taskResult = AttachmentContainerRecovery.repairIfNeeded(
            container: .task,
            trigger: .manual
        )

        _ = AttachmentContainerRecovery.repairIfNeeded(
            container: .wallet,
            trigger: .manual
        )

        _ = AttachmentContainerRecovery.repairIfNeeded(
            container: .document,
            trigger: .manual
        )

        return taskResult

    }
    
}
