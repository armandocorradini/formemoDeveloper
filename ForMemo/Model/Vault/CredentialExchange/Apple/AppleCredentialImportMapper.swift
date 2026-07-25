import Foundation
import AuthenticationServices

struct AppleCredentialImportMapper {

    func map(
        _ exportedData: ASExportedCredentialData
    ) throws -> [VaultImportRecord] {

        var records: [VaultImportRecord] = []

        for account in exportedData.accounts {

            for item in account.items {

                records.append(try map(item))
            }
        }

        return records
    }
}



private extension AppleCredentialImportMapper {
    
    func map(
        _ item: ASImportableItem
    ) throws -> VaultImportRecord {
        
        VaultImportRecord(
            title: item.title,
            subtitle: item.subtitle,
            favorite: item.favorite,
            tags: item.tags,
            urls: item.scope?.urls ?? [],
            createdAt: item.created,
            modifiedAt: item.lastModified,
            credentials: try item.credentials.map(map)
        )
    }
    
    
    
    func map(
        _ credential: ASImportableCredential
    ) throws -> VaultImportCredential {

        switch credential {

        case .basicAuthentication(let credential):

            return VaultImportCredential(
                kind: .usernamePassword,
                label: nil,
                values: [
                    "username": credential.userName?.value ?? "",
                    "password": credential.password?.value ?? ""
                ]
            )

        case .note(let note):

            return VaultImportCredential(
                kind: .note,
                label: note.content.label,
                values: [
                    "content": note.content.value
                ]
            )

        case .apiKey(let api):

            return VaultImportCredential(
                kind: .apiKey,
                label: api.keyType?.value,
                values: [
                    "key": api.key?.value ?? "",
                    "username": api.userName?.value ?? "",
                    "url": api.url?.value ?? ""
                ]
            )

        case .sshKey(let ssh):

            return VaultImportCredential(
                kind: .sshKey,
                label: ssh.keyComment,
                values: [
                    "type": ssh.keyType
                ]
            )
            
        case .totp(let totp):

            return VaultImportCredential(
                kind: .totp,
                label: totp.issuer,
                values: [
                    "secret": totp.secret.base64EncodedString(),
                    "issuer": totp.issuer ?? "",
                    "username": totp.userName ?? "",
                    "algorithm": totp.algorithm.rawValue,
                    "digits": String(totp.digits),
                    "period": String(totp.period)
                ]
            )
            
        case .passkey(let passkey):

            return VaultImportCredential(
                kind: .passkey,
                label: passkey.relyingPartyIdentifier,
                values: [
                    "rpId": passkey.relyingPartyIdentifier,
                    "username": passkey.userName,
                    "displayName": passkey.userDisplayName,
                    "credentialID": passkey.credentialID.base64EncodedString(),
                    "userHandle": passkey.userHandle.base64EncodedString(),
                    "key": passkey.key.base64EncodedString()
                ]
            )
            
            
        default:

            return VaultImportCredential(
                kind: .customField,
                label: String(describing: credential),
                values: [:]
            )
        }
    }
    
    
}
