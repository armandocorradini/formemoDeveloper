import Foundation
import CoreData
import SwiftData
import os

@MainActor
final class PersistenceOperationCoordinator {

    static let shared = PersistenceOperationCoordinator()

    enum Operation: String {
        case reset
        case restore
    }

    enum CoordinatorError: LocalizedError {
        case operationAlreadyRunning
        case noOperation
        case cloudKitTimeout(Operation)
        case cloudKitFailure(String)
        case fileSystemNotSettled

        var errorDescription: String? {
            switch self {
            case .operationAlreadyRunning:
                return "Another persistence operation is already in progress."
            case .noOperation:
                return "No persistence operation is active."
            case .cloudKitTimeout(let operation):
                return "\(operation.rawValue.capitalized) could not be completed because CloudKit synchronization did not settle within the allowed time."
            case .cloudKitFailure(let message):
                return "CloudKit synchronization failed: \(message)"
            case .fileSystemNotSettled:
                return "iCloud file storage did not reach a stable state."
            }
        }
    }

    private let quietInterval: TimeInterval = 2
    private let timeout: TimeInterval = 120

    private var cloudKitObserver: NSObjectProtocol?
    private var remoteChangeObserver: NSObjectProtocol?

    private var currentOperation: Operation?
    private var operationStartedAt: Date?

    private var activeCloudKitEvents: Set<UUID> = []
    private var exportCompletedAfterStart = false

    private var lastCloudKitEventAt = Date.distantPast
    private var lastRemoteChangeAt = Date.distantPast
    private var cloudKitFailure: String?

    private struct CloudKitEventSnapshot: Sendable {
        let identifier: UUID
        let isExport: Bool
        let startDate: Date
        let endDate: Date?
        let succeeded: Bool
        let errorMessage: String?
    }

    private init() {}

    func begin(_ operation: Operation) throws {
        guard currentOperation == nil else {
            throw CoordinatorError.operationAlreadyRunning
        }

        installObservers()

        currentOperation = operation
        operationStartedAt = Date()
        activeCloudKitEvents.removeAll()
        exportCompletedAfterStart = false
        cloudKitFailure = nil
        let now = Date()
        lastCloudKitEventAt = now
        lastRemoteChangeAt = now
    }

    func finish() {
        currentOperation = nil
        operationStartedAt = nil
        activeCloudKitEvents.removeAll()
        exportCompletedAfterStart = false
        cloudKitFailure = nil
    }

    func waitForSettlement(
        requireExport: Bool,
        expectedFiles: [URL] = [],
        directoriesThatMustBeEmpty: [URL] = []
    ) async throws {

        guard let operation = currentOperation,
              let startedAt = operationStartedAt else {
            throw CoordinatorError.noOperation
        }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {

            try Task.checkCancellation()

            if let cloudKitFailure {
                throw CoordinatorError.cloudKitFailure(cloudKitFailure)
            }

            let cloudKitQuiet =
                activeCloudKitEvents.isEmpty &&
                Date().timeIntervalSince(lastCloudKitEventAt) >= quietInterval &&
                Date().timeIntervalSince(lastRemoteChangeAt) >= quietInterval

            let exportReady =
                !requireExport || exportCompletedAfterStart

            let filesReady = fileSystemIsSettled(
                expectedFiles: expectedFiles,
                directoriesThatMustBeEmpty: directoriesThatMustBeEmpty
            )

            if exportReady && cloudKitQuiet && filesReady {
                AppLogger.persistence.notice(
                    "Persistence operation \(operation.rawValue) settled after \(Date().timeIntervalSince(startedAt))s"
                )
                return
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        if !fileSystemIsSettled(
            expectedFiles: expectedFiles,
            directoriesThatMustBeEmpty: directoriesThatMustBeEmpty
        ) {
            throw CoordinatorError.fileSystemNotSettled
        }

        throw CoordinatorError.cloudKitTimeout(operation)
    }

    private func installObservers() {

        guard cloudKitObserver == nil,
              remoteChangeObserver == nil else {
            return
        }

        cloudKitObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in

            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event
            else {
                return
            }

            let snapshot = CloudKitEventSnapshot(
                identifier: event.identifier,
                isExport: event.type == .export,
                startDate: event.startDate,
                endDate: event.endDate,
                succeeded: event.succeeded,
                errorMessage: event.error?.localizedDescription
            )

            Task { @MainActor in
                PersistenceOperationCoordinator.shared.consumeCloudKitEvent(snapshot)
            }
        }

        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PersistenceOperationCoordinator.shared.recordRemoteChange()
            }
        }
    }

    private func recordRemoteChange() {
        guard currentOperation != nil else {
            return
        }

        lastRemoteChangeAt = Date()
    }

    private func consumeCloudKitEvent(
        _ event: CloudKitEventSnapshot
    ) {

        guard let operationStartedAt,
              currentOperation != nil else {
            return
        }

        lastCloudKitEventAt = Date()

        // Event started during the current operation.
        if event.startDate >= operationStartedAt {

            guard let endDate = event.endDate else {
                activeCloudKitEvents.insert(event.identifier)
                return
            }

            activeCloudKitEvents.remove(event.identifier)

            if event.isExport,
               event.succeeded {
                exportCompletedAfterStart = true
            }

            if !event.succeeded {
                cloudKitFailure =
                    event.errorMessage
                    ?? "CloudKit event \(event.identifier) failed."
            }

            // endDate is intentionally read so the event is treated as
            // completed only after Core Data reports its end.
            _ = endDate
            return
        }

        // Event started before the operation but completed after it began.
        if let endDate = event.endDate,
           endDate >= operationStartedAt {

            activeCloudKitEvents.remove(event.identifier)

            if event.isExport,
               event.succeeded {
                exportCompletedAfterStart = true
            }

            if !event.succeeded {
                cloudKitFailure =
                    event.errorMessage
                    ?? "CloudKit event \(event.identifier) failed."
            }
        }
    }

    private func fileSystemIsSettled(
        expectedFiles: [URL],
        directoriesThatMustBeEmpty: [URL]
    ) -> Bool {

        let fileManager = FileManager.default

        for directory in directoriesThatMustBeEmpty {

            guard fileManager.fileExists(atPath: directory.path) else {
                continue
            }

            guard
                let contents = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            else {
                return false
            }

            if !contents.isEmpty {
                return false
            }
        }

        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey
        ]

        for url in expectedFiles {

            guard fileManager.fileExists(atPath: url.path) else {
                return false
            }

            guard let values = try? url.resourceValues(forKeys: keys) else {
                return false
            }

            guard values.ubiquitousItemIsUploading != true,
                  values.ubiquitousItemIsDownloading != true,
                  values.ubiquitousItemHasUnresolvedConflicts != true
            else {
                return false
            }

            if values.isUbiquitousItem == true,
               values.ubiquitousItemIsUploaded != true {
                return false
            }
        }

        return true
    }

}
