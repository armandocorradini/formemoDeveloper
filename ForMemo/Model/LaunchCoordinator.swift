
import Foundation

@MainActor
final class LaunchCoordinator {

    static let shared = LaunchCoordinator()

    private init() {}

    var launchDate = Date()

    var isInLaunchGracePeriod: Bool {

        Date().timeIntervalSince(launchDate) < 8
    }
}
