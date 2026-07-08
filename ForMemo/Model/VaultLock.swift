import Foundation
import Combine
import LocalAuthentication

enum VaultLockError: Error {
    case authenticationFailed
    case biometricsUnavailable
    case appSettingsUnavailable
}

@MainActor
final class VaultLock: ObservableObject {

    static let shared = VaultLock()
    
    static var hasBiometricAuthentication: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }
    
    private let settings = AppSettings.shared

    @Published private(set) var isUnlocked = false

    private var lockTask: Task<Void, Never>?
    private var authenticationContext: LAContext?

    private var timeout: TimeInterval {
        TimeInterval(settings.vaultAutoLockInterval)
    }

    private init() {}

    func unlock(reason: String = String(localized: "vault.unlock")) async throws {
        
//#if targetEnvironment(simulator)
//
//isUnlocked = true
//
//scheduleAutoLock()
//        print("SIMULATORE")
//return
//
//#else
        
        let context = authenticationContext ?? LAContext()
        authenticationContext = context


        var error: NSError?
        DebugLog.write("🔐 Checking authentication availability")
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw VaultLockError.biometricsUnavailable
        }

        let policy: LAPolicy = .deviceOwnerAuthentication

        do {
            DebugLog.write("🔐 Starting authentication")
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: reason
            )
            DebugLog.write("🔐 Authentication completed")
            DebugLog.write("🔐 Policy: \(policy.rawValue)")
            DebugLog.write("🔐 Authentication success: \(success)")

            guard !Task.isCancelled else {
                throw CancellationError()
            }

            guard success else {
                throw VaultLockError.authenticationFailed
            }

            isUnlocked = true
            scheduleAutoLock()

        } catch let error as LAError {

            DebugLog.write(
                "🔐 Authentication failed. LAError=\(error.code.rawValue) (\(error.localizedDescription))"
            )
            throw error

        }
//#endif
    }

    func authenticateIfRequired(
        for item: VaultItem,
        reason: String = String(localized: "Show Password")
    ) async throws {

        DebugLog.write("🔐 authenticateIfRequired called")
        DebugLog.write("🔐 requireBiometricEveryTime = \(item.requireBiometricEveryTime)")

        guard item.requireBiometricEveryTime else {
            DebugLog.write("🔐 Per-item authentication not required")
            return
        }

        DebugLog.write("🔐 Per-item authentication required")

        authenticationContext?.invalidate()
        authenticationContext = nil

        try await unlock(reason: reason)
    }
    
    
    func lock() {
        lockTask?.cancel()
        lockTask = nil
        isUnlocked = false
        authenticationContext?.invalidate()
        authenticationContext = nil
        VaultCrypto.clearCachedKey()
    }

    func userDidAccessVault() {
        guard isUnlocked else { return }
        scheduleAutoLock()
    }

    private func scheduleAutoLock() {
        lockTask?.cancel()

        guard timeout > 0 else { return }

        lockTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .seconds(self.timeout))
            guard !Task.isCancelled else { return }

            guard self.isUnlocked else { return }
            self.lock()
        }
    }
}
