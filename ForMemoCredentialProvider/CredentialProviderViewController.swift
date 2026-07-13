import AuthenticationServices
import LocalAuthentication
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var selectedCredential: SharedVaultCredential?
    private var isExtensionVisible = false
    private var isAuthenticating = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ForMemo Vault"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isExtensionVisible = true
        authenticateSelectedCredentialIfPossible()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isExtensionVisible = false
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let credentials = CredentialAutoFillManager.shared.credentials(for: serviceIdentifiers)
        showCredentials(credentials)
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // The Vault is intentionally never considered unlocked in a background
        // extension process. Ask the system to present us before authenticating.
        selectedCredential = credentialIdentity.recordIdentifier.flatMap(CredentialStore.credential(for:))
        extensionContext.cancelRequest(withError: extensionError(.userInteractionRequired))
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        guard let recordIdentifier = credentialIdentity.recordIdentifier,
              let credential = CredentialStore.credential(for: recordIdentifier) else {
            extensionContext.cancelRequest(withError: extensionError(.credentialIdentityNotFound))
            return
        }
        selectedCredential = credential
        authenticateSelectedCredentialIfPossible()
    }

    @IBAction func cancel(_ sender: AnyObject?) {
        extensionContext.cancelRequest(withError: extensionError(.userCanceled))
    }

    @IBAction func passwordSelected(_ sender: AnyObject?) {
        guard let selectedCredential else {
            extensionContext.cancelRequest(withError: extensionError(.failed))
            return
        }
        authenticateAndProvide(selectedCredential)
    }

    private func showCredentials(_ credentials: [SharedVaultCredential]) {
        guard !credentials.isEmpty else {
            let label = UILabel()
            label.text = "No matching credentials in ForMemo Vault"
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            return
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        for credential in credentials {
            var configuration = UIButton.Configuration.filled()
            configuration.title = credential.username
            configuration.subtitle = credential.domain
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { [weak self] _ in
                self?.selectedCredential = credential
                self?.authenticateAndProvide(credential)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func authenticateAndProvide(_ credential: SharedVaultCredential) {
        selectedCredential = credential
        authenticateSelectedCredentialIfPossible()
    }

    private func authenticateSelectedCredentialIfPossible() {
        guard isExtensionVisible,
              !isAuthenticating,
              let credential = selectedCredential else {
            return
        }

        isAuthenticating = true
        Task { @MainActor in
            defer { isAuthenticating = false }
            let context = LAContext()
            do {
                let reason = "Authenticate to fill your ForMemo Vault credential."
                guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                    throw LAError(.authenticationFailed)
                }
                let password = try VaultCrypto.decrypt(credential.encryptedPassword)
                let result = ASPasswordCredential(user: credential.username, password: password)
                extensionContext.completeRequest(withSelectedCredential: result, completionHandler: nil)
            } catch {
                if let authenticationError = error as? LAError,
                   authenticationError.code == .userCancel || authenticationError.code == .appCancel {
                    extensionContext.cancelRequest(withError: extensionError(.userCanceled))
                    return
                }
                showFailure(error)
            }
        }
    }

    private func showFailure(_ error: Error) {
        let message: String
        if case let VaultCredentialError.keyUnavailable(status) = error {
            message = "The Vault key is not available to AutoFill (Keychain status \(status)). Open ForMemo once, then try again."
        } else {
            message = "ForMemo could not unlock this credential: \(error.localizedDescription)"
        }

        let alert = UIAlertController(title: "Unable to Fill Credential", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.extensionContext.cancelRequest(withError: self?.extensionError(.failed) ?? NSError())
        })
        present(alert, animated: true)
    }

    private func extensionError(_ code: ASExtensionError.Code) -> NSError {
        NSError(domain: ASExtensionErrorDomain, code: code.rawValue)
    }
}
