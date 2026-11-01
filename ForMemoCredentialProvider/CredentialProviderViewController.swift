import AuthenticationServices
import LocalAuthentication
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var selectedCredential: SharedVaultCredential?
    private var isExtensionVisible = false
    private var isAuthenticating = false

    @IBOutlet private weak var navigationBar: UINavigationBar!
    private var credentialsScrollView: UIScrollView?
    private var credentialsHeadingLabel: UILabel?
    private var didLogInitialLayout = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Keep the system navigation area free of a second, competing title.
        title = nil
        // Keep the AutoFill panel compact. The account list scrolls inside it.
        preferredContentSize = CGSize(width: 420, height: 200)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isExtensionVisible = true
        view.layoutIfNeeded()
        logLayoutDiagnostics("viewDidAppear")


        authenticateSelectedCredentialIfPossible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !didLogInitialLayout else { return }
        didLogInitialLayout = true
        logLayoutDiagnostics("first viewDidLayoutSubviews")
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
        // In the direct-selection flow, iOS does not necessarily call
        // prepareCredentialList. Build the selected account UI explicitly.
        showCredentials([credential])
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
        credentialsScrollView?.removeFromSuperview()
        credentialsHeadingLabel?.removeFromSuperview()

        let heading = UILabel()
        heading.text = String(localized: "Choose an account")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        heading.textColor = .label
        heading.numberOfLines = 1
        heading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heading)
        credentialsHeadingLabel = heading

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        credentialsScrollView = scrollView

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.distribution = .fill
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let cardHeight: CGFloat = 88
        if credentials.isEmpty {
            let message = UILabel()
            message.text = String(localized: "No matching credentials in ForMemo Vault")
            message.font = .systemFont(ofSize: 15)
            message.textColor = .secondaryLabel
            message.numberOfLines = 0
            contentStack.addArrangedSubview(message)
        } else {
            for credential in credentials {
                var configuration = UIButton.Configuration.tinted()
                configuration.title = credential.username
                configuration.subtitle = credential.domain
                configuration.image = UIImage(systemName: "key.horizontal")
                configuration.imagePlacement = .leading
                configuration.imagePadding = 12
                configuration.titleAlignment = .leading
                configuration.contentInsets = NSDirectionalEdgeInsets(
                    top: 10,
                    leading: 16,
                    bottom: 10,
                    trailing: 16
                )

                let button = UIButton(configuration: configuration)
                button.contentHorizontalAlignment = .leading
                button.translatesAutoresizingMaskIntoConstraints = false
                button.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    self?.selectedCredential = credential
                    self?.authenticateAndProvide(credential)
                }, for: .touchUpInside)
                contentStack.addArrangedSubview(button)
            }
        }

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            heading.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            heading.topAnchor.constraint(equalTo: navigationBar.bottomAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        // The panel stays at 210 pt. The scroll view occupies all remaining
        // vertical space, while the stack keeps its full content height so
        // additional accounts are reached by scrolling.
        scrollView.isScrollEnabled = true
        scrollView.alwaysBounceVertical = credentials.count > 1
        scrollView.showsVerticalScrollIndicator = credentials.count > 1

        view.setNeedsLayout()
        view.layoutIfNeeded()
        logLayoutDiagnostics("after showCredentials")

    }

    /// Records the extension's actual geometry without changing its layout.
    /// The system owns the presentation container; these values help distinguish
    /// a host-sized panel from excess space inside the extension's own view.
    private func logLayoutDiagnostics(_ phase: String) {
        let windowBounds = view.window.map { String(describing: $0.bounds) } ?? "nil"
        let navigationFrame = navigationBar.map { String(describing: $0.frame) } ?? "nil"
        let scrollFrame = credentialsScrollView.map { String(describing: $0.frame) } ?? "nil"
        let headingFrame = credentialsHeadingLabel.map { String(describing: $0.frame) } ?? "nil"

        print(
            "[ForMemo AutoFill Layout] \(phase) | " +
            "preferredContentSize=\(preferredContentSize) | " +
            "view.bounds=\(view.bounds) | " +
            "window.bounds=\(windowBounds) | " +
            "safeAreaInsets=\(view.safeAreaInsets) | " +
            "navigationBar.frame=\(navigationFrame) | " +
            "heading.frame=\(headingFrame) | " +
            "scrollView.frame=\(scrollFrame) | " +
            "sizeClasses=(horizontal: \(traitCollection.horizontalSizeClass.rawValue), " +
            "vertical: \(traitCollection.verticalSizeClass.rawValue))"
        )
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
                let reason = String(localized: "Authenticate to fill your ForMemo Vault credential.")
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
            message = String(localized: "The Vault key is not available to AutoFill (Keychain status \(status)). Open ForMemo once, then try again.")
        } else {
            message = String(localized: "ForMemo could not unlock this credential: \(error.localizedDescription)")
        }

        let alert = UIAlertController(
            title: String(localized: "Unable to Fill Credential"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { [weak self] _ in
            self?.extensionContext.cancelRequest(withError: self?.extensionError(.failed) ?? NSError())
        })
        present(alert, animated: true)
    }

    private func extensionError(_ code: ASExtensionError.Code) -> NSError {
        NSError(domain: ASExtensionErrorDomain, code: code.rawValue)
    }
}
