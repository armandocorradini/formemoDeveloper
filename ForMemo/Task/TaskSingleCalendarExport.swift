
import SwiftUI
import EventKit
import UIKit
import os

@MainActor
final class TaskSingleCalendarExport {

    static let shared = TaskSingleCalendarExport()

    private let engine = CalendarExportEngine()

    private init() {}

    func present(for task: TodoTask) {
        guard task.deadLine != nil else { return }

        Task {
            do {
                try await engine.requestAccess()

                let calendars = engine.availableCalendars()

                guard !calendars.isEmpty else {
                    return
                }

                presentCalendarPicker(
                    calendars: calendars,
                    task: task
                )

            } catch {
                AppLogger.persistence.error(
                    "Single task calendar export failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func presentCalendarPicker(
        calendars: [EKCalendar],
        task: TodoTask
    ) {
        let picker = CalendarPickerView(
            calendars: calendars
        ) { [weak self] calendar in

            guard let self else { return }

            self.export(
                task: task,
                to: calendar
            )
        }

        let controller = UIHostingController(rootView: picker)

        controller.modalPresentationStyle = .pageSheet

        guard let presenter = topViewController() else {
            return
        }

        presenter.present(
            controller,
            animated: true
        )
    }

    private func export(
        task: TodoTask,
        to calendar: EKCalendar
    ) {
        let item = TaskTransferObject(task: task)

        do {
            let count = try engine.export(
                items: [item],
                to: calendar
            )

            if count == 0 {
                AppLogger.persistence.debug(
                    "Task already exists in calendar: \(task.title)"
                )
            } else {
                AppLogger.persistence.debug(
                    "Task added to calendar: \(task.title)"
                )
            }

        } catch {
            AppLogger.persistence.error(
                "Failed to add task to calendar: \(error.localizedDescription)"
            )
        }
    }

    private func topViewController(
        from root: UIViewController? = nil
    ) -> UIViewController? {

        let rootViewController: UIViewController?

        if let root {
            rootViewController = root
        } else {
            rootViewController =
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .filter {
                        $0.activationState == .foregroundActive
                    }
                    .flatMap { $0.windows }
                    .first(where: { $0.isKeyWindow })?
                    .rootViewController
        }

        guard let rootViewController else {
            return nil
        }

        if let presented = rootViewController.presentedViewController {
            return topViewController(from: presented)
        }

        if let navigation = rootViewController as? UINavigationController {
            return topViewController(
                from: navigation.visibleViewController
            )
        }

        if let tab = rootViewController as? UITabBarController {
            return topViewController(
                from: tab.selectedViewController
            )
        }

        return rootViewController
    }
}
