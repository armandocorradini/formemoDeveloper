
import AuthenticationServices
import UIKit
import OSLog

private let autofillLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ForMemoCredentialProvider", category: "autofill")

class CredentialProviderViewController: ASCredentialProviderViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ForMemo Vault"
        autofillLogger.debug("Credential Provider started")
    }

    /*
     Prepare your UI to list available credentials for the user to choose from. The items in
     'serviceIdentifiers' describe the service the user is logging in to, so your extension can
     prioritize the most relevant credentials in the list.
    */
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // TODO: Load and display matching Vault credentials.
        CredentialAutoFillManager.shared.refreshCredentialIdentities()
        let domains = serviceIdentifiers.map(\.identifier)
        autofillLogger.debug("AutoFill requested for domains: \(String(describing: domains))")
        ASCredentialIdentityStore.shared.getState { state in
            autofillLogger.debug("AutoFill enabled: \(state.isEnabled)")
            autofillLogger.debug("Supports incremental updates: \(state.supportsIncrementalUpdates)")
        }
        // TODO: Filter Vault credentials using serviceIdentifiers.
    }

    /*
     Implement this method if your extension supports showing credentials in the QuickType bar.
     When the user selects a credential from your app, this method will be called with the
     ASPasswordCredentialIdentity your app has previously saved to the ASCredentialIdentityStore.
     Provide the password by completing the extension request with the associated ASPasswordCredential.
     If using the credential would require showing custom UI for authenticating the user, cancel
     the request with error code ASExtensionError.userInteractionRequired.

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        let databaseIsUnlocked = true
        if (databaseIsUnlocked) {
            let passwordCredential = ASPasswordCredential(user: "j_appleseed", password: "apple1234")
            self.extensionContext.completeRequest(withSelectedCredential: passwordCredential, completionHandler: nil)
        } else {
            self.extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code:ASExtensionError.userInteractionRequired.rawValue))
        }
    }
    */

    /*
     Implement this method if provideCredentialWithoutUserInteraction(for:) can fail with
     ASExtensionError.userInteractionRequired. In this case, the system may present your extension's
     UI and call this method. Show appropriate UI for authenticating the user then provide the password
     by completing the extension request with the associated ASPasswordCredential.

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
    }
    */

    @IBAction func cancel(_ sender: AnyObject?) {
        self.extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
    }

    @IBAction func passwordSelected(_ sender: AnyObject?) {
        self.extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.failed.rawValue))
    }

}
