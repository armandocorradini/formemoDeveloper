import Foundation
import SwiftData
import SwiftUI

enum VaultCategory: String, Codable, CaseIterable, Sendable {
    case website
    case email
    case banking
    case social
    case shopping
    case streaming
    case wifi
    case server
    case work
    case software
    case document
    case other
}
extension VaultCategory {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .website: return "Website"
        case .email: return "Email"
        case .banking: return "Banking"
        case .social: return "Social"
        case .shopping: return "Shopping"
        case .streaming: return "Streaming"
        case .wifi: return "Wi-Fi"
        case .server: return "Server"
        case .work: return "Work"
        case .software: return "Software"
        case .document: return "Document"
        case .other: return "Other"
        }
    }
}
enum VaultIcon: String, Codable, CaseIterable, Sendable {
    case lockShield = "lock.shield.fill"
    case globe = "globe"
    case envelope = "envelope"
    case person = "person.fill"
    case creditCard = "creditcard.fill"
    case wifi = "wifi"
    case server = "server.rack"
    case briefcase = "briefcase.fill"
    case key = "key.fill"
    case doc = "doc.fill"
}

enum VaultColor: String, Codable, CaseIterable, Sendable {
    case blue
    case green
    case orange
    case red
    case pink
    case purple
    case teal
    case indigo
    case gray
}
extension VaultColor {
    var swiftUIColor: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .teal: return .teal
        case .indigo: return .indigo
        case .gray: return .gray
        }
    }
}
@Model
final class VaultItem {

    // MARK: - Identity

    var id = UUID()
    var syncIdentifier = UUID()
    var version = 1

    // MARK: - Organization

    var title: String = ""
    var category: VaultCategory = VaultCategory.website

    var favorite = false

    var tags: [String] = []
    var sortOrder = 0

    // MARK: - Appearance

    var icon: VaultIcon = VaultIcon.lockShield
    var color: VaultColor = VaultColor.blue

    // MARK: - Searchable fields

    var username = ""
    var email = ""
    var website = ""
    var notes = ""

    // MARK: - Encrypted fields

    var encryptedPassword: Data?
    var encryptedPIN: Data?
    var encryptedOTPSecret: Data?
    var encryptedSecurityQuestion: Data?
    var encryptedSecurityAnswer: Data?
    var encryptedCustomerNumber: Data?
    var encryptedRecoveryCode: Data?

    // MARK: - Dates

    var createdAt = Date()
    var modifiedAt = Date()

    var passwordUpdatedAt: Date?
    var passwordExpiresAt: Date?

    var lastViewedAt: Date?
    var lastCopiedAt: Date?

    var deletedAt: Date?

    // MARK: - Security

    var requireBiometricEveryTime = false

    init(
        title: String,
        category: VaultCategory = .website
    ) {
        self.id = UUID()
        self.syncIdentifier = UUID()
        self.version = 1

        self.title = title
        self.category = category

        self.favorite = false

        self.tags = []
        self.sortOrder = 0

        self.icon = .lockShield
        self.color = .blue

        self.username = ""
        self.email = ""
        self.website = ""
        self.notes = ""

        self.encryptedPassword = nil
        self.encryptedPIN = nil
        self.encryptedOTPSecret = nil
        self.encryptedSecurityQuestion = nil
        self.encryptedSecurityAnswer = nil
        self.encryptedCustomerNumber = nil
        self.encryptedRecoveryCode = nil

        let now = Date()

        self.createdAt = now
        self.modifiedAt = now

        self.passwordUpdatedAt = nil
        self.passwordExpiresAt = nil

        self.lastViewedAt = nil
        self.lastCopiedAt = nil

        self.deletedAt = nil

        self.requireBiometricEveryTime = false
    }
}
