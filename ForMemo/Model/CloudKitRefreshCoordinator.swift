
import Foundation

@MainActor
final class CloudKitRefreshCoordinator {

    static let shared = CloudKitRefreshCoordinator()

    private var pendingTask: Task<Void, Never>?

    private init() {}

    func scheduleRefresh(
        delay: Duration = .seconds(2),
        action: @escaping @MainActor () -> Void
    ) {

        pendingTask?.cancel()

        pendingTask = Task {

            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            action()
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
