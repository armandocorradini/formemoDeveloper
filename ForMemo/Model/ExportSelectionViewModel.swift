import Observation
import Foundation

@Observable
final class ExportSelectionState {
    
    var selectedIDs: Set<UUID> = []
    
    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }
    
    func selectAll(from tasks: [TodoTask]) {
        selectedIDs = Set(tasks.map { $0.id })
    }
    
    func deselectAll() {
        selectedIDs.removeAll()
    }
}
