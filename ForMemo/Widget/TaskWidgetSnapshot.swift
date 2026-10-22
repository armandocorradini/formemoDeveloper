import Foundation

struct TaskWidgetItem: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let deadline: Date?
    let isCompleted: Bool
    let priorityRaw: Int
}

struct TaskWidgetSnapshot: Codable {
    let generatedAt: Date
    /// Attività aperte con scadenza, incluse quelle future, per calcolare la vista
    /// corretta in base alla data di ciascuna entry della timeline.
    let tasks: [TaskWidgetItem]
    /// Conteggio calcolato al momento dello snapshot; mantenuto per compatibilità.
    let overduePreviousDaysCount: Int
    /// Dati meteo opzionali, condivisi con l'estensione tramite App Group.
    let weatherSymbolName: String?
    let weatherMinTemperature: Int?
    let weatherMaxTemperature: Int?
}

enum TaskWidgetSnapshotStore {
    static let appGroupID = "group.corradini.armando.NewTask"

    @MainActor
    static var scheduledRefreshTask: Task<Void, Never>?

    @MainActor
    static var scheduledRefreshDeadline: ContinuousClock.Instant?

    static func load() -> TaskWidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: "todayTasksSnapshot")
        else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(TaskWidgetSnapshot.self, from: data)
            return snapshot
        } catch {
            #if DEBUG
            print("ForMemo widget snapshot read failed: \(error)")
            #endif
            return nil
        }
    }
}
