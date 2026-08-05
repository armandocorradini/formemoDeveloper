import SwiftUI

struct TaskDeadlineColumn: View {
    
    let model: TaskRowDisplayModel
    let isUrgent: Bool
    
    var body: some View {
        
        if let d = model.deadLine {
            
            VStack(spacing: 0) {
                
                Text(d, format: .dateTime.day())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text(d, format: .dateTime.month(.abbreviated))
                    .font(.system(size: 10, weight: .heavy))
                    .textCase(.uppercase)
                
                Text(d, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.8)
            }
            .shadow(color: .black, radius: 0.1, x: 1, y: 1)
            .foregroundStyle(model.statusColor)
            .pulseEffect(active: isUrgent)
            
        } else {
            
            Image(systemName: "questionmark.square")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.blue)
        }
    }
}
