import EventKit

final class RemindersAccess {
    
    private let store = EKEventStore()
    
    func requestAccess() async throws {
        
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            
            if #available(iOS 17.0, *) {
                
                store.requestFullAccessToReminders { granted, error in
                    
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    
                    if granted {
                        cont.resume(returning: ())
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "Reminders",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Access denied"]
                        ))
                    }
                }
                
            } else {
                
                store.requestAccess(to: .reminder) { granted, error in
                    
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    
                    if granted {
                        cont.resume(returning: ())
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "Reminders",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Access denied"]
                        ))
                    }
                }
            }
        }
    }
    
    func getStore() -> EKEventStore {
        store
    }
}
