import Foundation

struct PasswordOptions: Sendable, Codable {

    var length: Int = 20

    var includeUppercase = true
    var includeLowercase = true
    var includeNumbers = true
    var includeSymbols = true

    /// Excludes characters that are easily confused:
    /// O, 0, I, l, 1, |, etc.
    var excludeAmbiguousCharacters = true

    static let `default` = PasswordOptions()
}

enum PasswordStrength: Int, Sendable {

    case veryWeak
    case weak
    case fair
    case good
    case strong

    var localizedKey: String {
        switch self {
        case .veryWeak: return "password.strength.veryWeak"
        case .weak:     return "password.strength.weak"
        case .fair:     return "password.strength.fair"
        case .good:     return "password.strength.good"
        case .strong:   return "password.strength.strong"
        }
    }
}

enum PasswordGenerator {

    private static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    private static let numbers = Array("0123456789")
    private static let symbols = Array("!@#$%^&*()-_=+[]{}<>?/.,:;")

    private static let ambiguous: Set<Character> = [
        "O","0","I","l","1","|"
    ]

    static func generate(
        options: PasswordOptions = .default
    ) -> GeneratedPassword {

        var pool: [Character] = []

        if options.includeUppercase {
            pool += uppercase
        }

        if options.includeLowercase {
            pool += lowercase
        }

        if options.includeNumbers {
            pool += numbers
        }

        if options.includeSymbols {
            pool += symbols
        }

        if options.excludeAmbiguousCharacters {
            pool.removeAll {
                ambiguous.contains($0)
            }
        }

        guard !pool.isEmpty else {
            return GeneratedPassword(
                value: "",
                strength: .veryWeak,
                entropy: 0
            )
        }
        
        let requiredCount =
            (options.includeUppercase ? 1 : 0) +
            (options.includeLowercase ? 1 : 0) +
            (options.includeNumbers ? 1 : 0) +
            (options.includeSymbols ? 1 : 0)

        let targetLength = max(options.length, requiredCount)
        var password: [Character] = []

        if options.includeUppercase {
            password.append(random(from: uppercase, excludingAmbiguous: options.excludeAmbiguousCharacters))
        }

        if options.includeLowercase {
            password.append(random(from: lowercase, excludingAmbiguous: options.excludeAmbiguousCharacters))
        }

        if options.includeNumbers {
            password.append(random(from: numbers, excludingAmbiguous: options.excludeAmbiguousCharacters))
        }

        if options.includeSymbols {
            password.append(random(from: symbols, excludingAmbiguous: false))
        }

        while password.count < targetLength {
            password.append(pool.randomElement()!)
        }

        password.shuffle()

        let value = String(password)
        let strength = strength(of: value)
        let entropy = entropy(length: value.count, alphabetSize: pool.count)

        return GeneratedPassword(
            value: value,
            strength: strength,
            entropy: entropy
        )
    }

    static func strength(
        of password: String
    ) -> PasswordStrength {

        let length = password.count

        var score = 0

        if length >= 12 { score += 1 }
        if length >= 16 { score += 1 }
        if length >= 20 { score += 1 }

        if password.rangeOfCharacter(from: .uppercaseLetters) != nil {
            score += 1
        }

        if password.rangeOfCharacter(from: .lowercaseLetters) != nil {
            score += 1
        }

        if password.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 1
        }

        let punctuation = CharacterSet.punctuationCharacters
            .union(.symbols)

        if password.rangeOfCharacter(from: punctuation) != nil {
            score += 1
        }

        switch score {
        case 0...2:
            return .veryWeak
        case 3:
            return .weak
        case 4:
            return .fair
        case 5...6:
            return .good
        default:
            return .strong
        }
    }

    static func evaluate(_ password: String) -> GeneratedPassword {

        GeneratedPassword(
            value: password,
            strength: strength(of: password),
            entropy: entropy(of: password)
        )
    }

    private static func random(
        from source: [Character],
        excludingAmbiguous: Bool
    ) -> Character {

        let filtered: [Character]

        if excludingAmbiguous {
            filtered = source.filter {
                !ambiguous.contains($0)
            }
        } else {
            filtered = source
        }

        var generator = SystemRandomNumberGenerator()
        return filtered.randomElement(using: &generator)!
    }

    private static func entropy(length: Int, alphabetSize: Int) -> Double {
        guard length > 0, alphabetSize > 1 else { return 0 }
        return Double(length) * log2(Double(alphabetSize))
    }

    private static func entropy(of password: String) -> Double {
        guard !password.isEmpty else {
            return 0
        }

        let alphabetSize = max(Set(password).count, 1)
        return entropy(length: password.count, alphabetSize: alphabetSize)
    }
}


struct GeneratedPassword: Sendable {

    let value: String

    let strength: PasswordStrength

    let entropy: Double

}
