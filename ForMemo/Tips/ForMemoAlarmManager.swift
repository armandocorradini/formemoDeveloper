import Foundation
import SwiftUI
import AlarmKit
import ActivityKit
import os
import os
import os
import os
import os

private struct ForMemoAlarmMetadata: AlarmMetadata {}

@MainActor
final class ForMemoAlarmManager {

    static let shared = ForMemoAlarmManager()

    private let alarmManager = AlarmManager.shared

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async throws {
        _ = try await alarmManager.requestAuthorization()
    }

    func authorizationState() -> AlarmManager.AuthorizationState {
        alarmManager.authorizationState
    }

    // MARK: - Schedule

    func scheduleAlarm(
        id: UUID,
        date: Date,
        title: String
    ) async throws {

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle"
        )

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton
        )

        let attributes = AlarmAttributes<ForMemoAlarmMetadata>(
            presentation: AlarmPresentation(
                alert: alertPresentation
            ),
            metadata: nil,
            tintColor: Color.accentColor
        )

        typealias AlarmConfiguration =
            AlarmManager.AlarmConfiguration<ForMemoAlarmMetadata>

        let configuration = AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )

        _ = try await alarmManager.schedule(
            id: id,
            configuration: configuration
        )
    }

    // MARK: - Cancel

    func cancelAlarm(id: UUID) async throws {
        try alarmManager.cancel(id: id)
    }

    func cancelAlarmIfNeeded(id: UUID) {
        Task {
            try? await cancelAlarm(id: id)
        }
    }

    // MARK: - Synchronize

    func synchronize(task: TodoTask) async {

        let alarmID = task.id

        guard task.alarmEnabled,
              let deadline = task.deadLine,
              !task.isCompleted,
              deadline > .now else {

            try? await cancelAlarm(id: alarmID)
            return
        }

        do {
            try? await cancelAlarm(id: alarmID)

            try await scheduleAlarm(
                id: alarmID,
                date: deadline,
                title: task.title
            )

        } catch {
            AppLogger.notifications.error(
                "ForMemo AlarmKit synchronization failed: \(error.localizedDescription)"
            )
        }
    }

    func synchronize(tasks: [TodoTask]) async {
        for task in tasks {
            await synchronize(task: task)
        }
    }

    func cancelAlarms(ids: [UUID]) async {
        for id in ids {
            try? await cancelAlarm(id: id)
        }
    }
}
