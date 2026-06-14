import EventKit

final class RemindersAccess {
    
    private let store = EKEventStore()
    
    func requestAccess() async throws {
        
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            
            store.requestFullAccessToReminders { granted, error in

                if let error {
                    cont.resume(throwing: error)
                    return
                }

                if granted {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: AppError.remindersAccessDenied)
                }
            }
        }
    }
    
    func getStore() -> EKEventStore {
        store
    }
}
