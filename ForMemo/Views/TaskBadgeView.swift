import SwiftUI

struct TaskBadgeView: View {
    
    let deadline: Date
    let badgeText: String
    let statusColor: Color
    
    private let badgeSize: CGFloat = 21
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        
        let now = Date()
        let diff = deadline.timeIntervalSince(now)
        let isToday = Calendar.current.isDateInToday(deadline) && diff >= 0
        
        let displayText: String = {
            if diff < 0 { return "!!" }
            if isToday { return "!" }
            return badgeText
        }()
        
        let isCircle = displayText.count <= 1
        let isFilled = false
        
        ZStack {
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, isCircle ? 0 : 6)
                    .frame(height: badgeSize)
                    .frame(minWidth: badgeSize)
                    .background(
                        Group {
                            if isCircle {
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .overlay(Circle().stroke(statusColor, lineWidth: 1))
                            } else {
                                Capsule()
                                    .fill(Color(.systemBackground))
                                    .overlay(Capsule().stroke(statusColor, lineWidth: 1))
                            }
                        }
                    )
                    .foregroundColor(
                        isFilled
                        ? (colorScheme == .light ? .black : .white)
                        : statusColor
                    )
            }
        }
    }
    
    @ViewBuilder
    private func shape(_ isCircle: Bool) -> some View {
        if isCircle {
            Circle()
        } else {
            Capsule()
        }
    }
}
