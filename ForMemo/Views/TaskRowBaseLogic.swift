import SwiftUI

protocol TaskRowBaseLogic { }

extension TaskRowBaseLogic {
    
    var urgentThreshold: TimeInterval {
        24 * 60 * 60
    }
    
    func isUrgent(model: TaskRowDisplayModel) -> Bool {
        
        guard let deadline = model.deadLine, !model.isCompleted else { return false }
        
        let remaining = deadline.timeIntervalSinceNow
        return remaining <= urgentThreshold && deadline > .now
    }
    
    func deadlineColor(
        model: TaskRowDisplayModel,
        deadline: Date
    ) -> Color {
        
        guard model.isCompleted == false else { return .secondary }
        
        if deadline < .now { return .red }
        
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= urgentThreshold { return .primary }
        
        return .secondary
    }
    
    func formattedOffset(model: TaskRowDisplayModel) -> String {
        
        guard let offset = model.reminderOffsetMinutes else {
            return ""
        }
        
        if offset == 0 {
            return String(localized: "At time of event")
        }
        
        if offset < 60 {
            return String(localized: "\(offset) minutes before")
        }
        
        if offset < 1440 {
            let hours = offset / 60
            return String(localized: "\(hours) hours before")
        }
        
        let days = offset / 1440
        let hours = (offset % 1440) / 60
        
        if hours > 0 {
            return String(localized: "\(days) days and \(hours) hours before")
        }
        
        return String(localized: "\(days) days before")
    }
    
}



extension View {
    func pulseEffect(active: Bool) -> some View {
        modifier(PulseModifier(active: active))
    }
}

struct PulseModifier: ViewModifier {
    
    let active: Bool
    @State private var animate = false
    
    func body(content: Content) -> some View {
        
        content
            .opacity(active ? (animate ? 0.35 : 1.0) : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(
                    .easeInOut(duration: 2)
                    .repeatForever(autoreverses: true)
                ) {
                    animate = true
                }
            }
            .onChange(of: active) { _, newValue in
                if !newValue {
                    animate = false
                }
            }
    }
}
