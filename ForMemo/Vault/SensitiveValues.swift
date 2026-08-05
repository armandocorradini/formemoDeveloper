import Foundation

struct SensitiveValues {
    var password = ""
    var pin = ""
    var passwordExpiresAt: Date?
    var secrets: [SecretValue] = []
}
