import Foundation
import SwiftData

@Model
final class DocumentItem {

    var id: UUID = UUID()

    var name: String = ""

    var documentTypeRaw: String = DocumentType.other.rawValue

    var documentNumber: String = ""

    var issueDate: Date?

    var expiryDate: Date?

    var notes: String = ""
    var storageLocation: String = ""

    var notificationEnabled: Bool = false

    // Days before expiry (0 = same day)
    var notificationDaysBefore: Int = 30

    var sortOrder: Int = 0

    var createdAt: Date = Date()

    var updatedAt: Date = Date()

    var lastOpenedAt: Date?

    init(
        name: String,
        documentType: DocumentType = .other,
        documentNumber: String = "",
        issueDate: Date? = nil,
        expiryDate: Date? = nil,
        notes: String = "",
        storageLocation: String = "",
        notificationEnabled: Bool = false,
        notificationDaysBefore: Int = 30,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.documentTypeRaw = documentType.rawValue
        self.documentNumber = documentNumber
        self.issueDate = issueDate
        self.expiryDate = expiryDate
        self.notes = notes
        self.storageLocation = storageLocation
        self.notificationEnabled = notificationEnabled
        self.notificationDaysBefore = notificationDaysBefore
        self.sortOrder = sortOrder
    }

    var documentType: DocumentType {
        get {
            DocumentType(rawValue: documentTypeRaw) ?? .other
        }
        set {
            documentTypeRaw = newValue.rawValue
        }
    }

    var daysRemaining: Int? {

        guard let expiryDate else {
            return nil
        }

        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: expiryDate)
        ).day
    }

    var isExpired: Bool {
        guard let daysRemaining else {
            return false
        }

        return daysRemaining < 0
    }

    var expiryStatus: ExpiryStatus {

        guard let daysRemaining else {
            return .valid
        }

        if daysRemaining < 0 {
            return .expired
        }

        if daysRemaining <= 30 {
            return .warning
        }

        if daysRemaining <= 90 {
            return .upcoming
        }

        return .valid
    }
}

extension DocumentItem {

    @MainActor
    static func createDeletedDocumentRecord(
        from document: DocumentItem,
        in context: ModelContext
    ) {

        let item = DeletedItem(type: "document")

        item.documentID = document.id

        item.documentName = document.name
        item.documentTypeRaw = document.documentTypeRaw
        item.documentNumber = document.documentNumber

        item.documentIssueDate = document.issueDate
        item.documentExpiryDate = document.expiryDate

        item.documentNotes = document.notes
        item.documentStorageLocation = document.storageLocation

        item.documentNotificationEnabled = document.notificationEnabled
        item.documentNotificationDaysBefore = document.notificationDaysBefore

        item.documentCreatedAt = document.createdAt

        context.insert(item)
    }
}

enum ExpiryStatus {
    case expired
    case warning
    case upcoming
    case valid
}

enum DocumentType: String, CaseIterable, Codable {

    case idCard
    case drivingLicence
    case passport
    case healthCard
    case paymentCard

    case carRegistration
    case carInsurance
    case carInspection
    case carTax

    case motorbikeRegistration
    case motorbikeInsurance

    case boatLicence

    case homeInsurance
    case lifeInsurance

    case voterCard
    case disabilityCard
    case disabilityPermit
    case residencePermit

    case medicalCertificate
    case vaccinationCertificate

    case metroPass
    case busTramPass
    case trainPass
    case parkingPass

    case gymCard
    case libraryCard
    case studentCard

    case theatreSubscription
    case cinemaSubscription
    case culturalAssociation
    case sportsAssociation
    case privateClub

    case workBadge
    case professionalLicense

    case other

    static var localizedSortedCases: [DocumentType] {

        let sorted = allCases
            .filter { $0 != .other }
            .sorted {
                String(localized: $0.localizedTitle)
                    .localizedCaseInsensitiveCompare(
                        String(localized: $1.localizedTitle)
                    ) == .orderedAscending
            }

        return [.other] + sorted
    }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .idCard: return "ID Card"
        case .drivingLicence: return "Driving Licence"
        case .passport: return "Passport"
        case .healthCard: return "Health Card"
        case .paymentCard: return "Payment Card"
        case .carRegistration: return "Car Registration"
        case .carInsurance: return "Car Insurance"
        case .carInspection: return "Car Inspection"
        case .carTax: return "Car Tax"
        case .motorbikeRegistration: return "Motorbike Registration"
        case .motorbikeInsurance: return "Motorbike Insurance"
        case .boatLicence: return "Boat Licence"
        case .homeInsurance: return "Home Insurance"
        case .lifeInsurance: return "Life Insurance"
        case .voterCard: return "Voter Card"
        case .disabilityCard: return "Disability Card"
        case .disabilityPermit: return "Disability Permit"
        case .residencePermit: return "Residence Permit"
        case .medicalCertificate: return "Medical Certificate"
        case .vaccinationCertificate: return "Vaccination Certificate"
        case .metroPass: return "Metro Pass"
        case .busTramPass: return "Bus/Tram Pass"
        case .trainPass: return "Train Pass"
        case .parkingPass: return "Parking Pass"
        case .gymCard: return "Gym Card"
        case .libraryCard: return "Library Card"
        case .studentCard: return "Student Card"
        case .theatreSubscription: return "Theatre Subscription"
        case .cinemaSubscription: return "Cinema Subscription"
        case .culturalAssociation: return "Cultural Association"
        case .sportsAssociation: return "Sports Association"
        case .privateClub: return "Private Club"
        case .workBadge: return "Work Badge"
        case .professionalLicense: return "Professional License"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .idCard: return "person.text.rectangle"
        case .drivingLicence: return "car"
        case .passport: return "globe"
        case .healthCard: return "cross.case"
        case .paymentCard: return "creditcard.rewards"
        case .carRegistration: return "car.rear"
        case .carInsurance: return "shield"
        case .carInspection: return "wrench.and.screwdriver"
        case .carTax: return "car.circle"
        case .motorbikeRegistration, .motorbikeInsurance: return "motorcycle"
        case .boatLicence: return "sailboat"
        case .homeInsurance: return "house"
        case .lifeInsurance: return "heart.text.square"
        case .voterCard: return "checkmark.seal"
        case .disabilityCard: return "accessibility"
        case .disabilityPermit: return "figure.roll"
        case .residencePermit: return "person.badge.shield.checkmark"
        case .medicalCertificate: return "stethoscope"
        case .vaccinationCertificate: return "cross.vial"
        case .metroPass: return "tram"
        case .busTramPass: return "bus"
        case .trainPass: return "train.side.front.car"
        case .parkingPass: return "parkingsign.circle"
        case .gymCard: return "figure.strengthtraining.traditional"
        case .libraryCard: return "books.vertical"
        case .studentCard: return "graduationcap"
        case .theatreSubscription: return "theatermasks"
        case .cinemaSubscription: return "film"
        case .culturalAssociation: return "building.columns"
        case .sportsAssociation: return "sportscourt"
        case .privateClub: return "person.3"
        case .workBadge: return "briefcase"
        case .professionalLicense: return "rosette"
        case .other: return "doc.text"
        }
    }
}
