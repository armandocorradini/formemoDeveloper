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

    var sortOrder: Int = 0

    var createdAt: Date = Date()

    var updatedAt: Date = Date()

    init(
        name: String,
        documentType: DocumentType = .other,
        documentNumber: String = "",
        issueDate: Date? = nil,
        expiryDate: Date? = nil,
        notes: String = "",
        sortOrder: Int = 0
    ) {
        self.name = name
        self.documentTypeRaw = documentType.rawValue
        self.documentNumber = documentNumber
        self.issueDate = issueDate
        self.expiryDate = expiryDate
        self.notes = notes
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

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .idCard: return "ID Card"
        case .drivingLicence: return "Driving Licence"
        case .passport: return "Passport"
        case .healthCard: return "Health Card"
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
        case .drivingLicence: return "car.fill"
        case .passport: return "globe"
        case .healthCard: return "cross.case.fill"
        case .carRegistration: return "car.rear.fill"
        case .carInsurance: return "shield.fill"
        case .carInspection: return "wrench.and.screwdriver.fill"
        case .carTax: return "car.circle.fill"
        case .motorbikeRegistration, .motorbikeInsurance: return "motorcycle"
        case .boatLicence: return "sailboat.fill"
        case .homeInsurance: return "house.fill"
        case .lifeInsurance: return "heart.text.square.fill"
        case .voterCard: return "checkmark.seal.fill"
        case .disabilityCard: return "accessibility"
        case .disabilityPermit: return "figure.roll"
        case .residencePermit: return "person.badge.shield.checkmark"
        case .medicalCertificate: return "stethoscope"
        case .vaccinationCertificate: return "cross.vial.fill"
        case .metroPass: return "tram.fill"
        case .busTramPass: return "bus.fill"
        case .trainPass: return "train.side.front.car"
        case .parkingPass: return "parkingsign.circle.fill"
        case .gymCard: return "figure.strengthtraining.traditional"
        case .libraryCard: return "books.vertical.fill"
        case .studentCard: return "graduationcap.fill"
        case .theatreSubscription: return "theatermasks.fill"
        case .cinemaSubscription: return "film.fill"
        case .culturalAssociation: return "building.columns.fill"
        case .sportsAssociation: return "sportscourt.fill"
        case .privateClub: return "person.3.fill"
        case .workBadge: return "briefcase.fill"
        case .professionalLicense: return "rosette"
        case .other: return "doc.text.fill"
        }
    }
}
