import SwiftUI

struct TaskIconDescriptor {
    
    let mainIcon: String
    let color: Color
    let priorityIcon: String?
    
    init(task: TodoTask) {
        self.mainIcon = task.status.icon
        self.color = task.status.color
        self.priorityIcon = task.priority.systemImage
    }
}
