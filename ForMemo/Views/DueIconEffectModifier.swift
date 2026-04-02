import SwiftUI

struct DueIconEffectModifier: ViewModifier {
    
    let deadline: Date?
    let effect: DueIconEffect
    
    @State private var now = Date()
    @State private var trigger = false
    
    // MARK: - Computed
    
    private var isDueSoon: Bool {
        guard let deadline else { return false }
        return deadline > now &&
        deadline <= now.addingTimeInterval(24 * 60 * 60)
    }
    
    // MARK: - Body
    
    func body(content: Content) -> some View {
        
        content
            .opacity(opacityValue)
            .rotationEffect(.degrees(rotationValue))
            .scaleEffect(scaleValue)
        
            .animation(animation, value: trigger)
            .animation(animation, value: isDueSoon)
        
            .onAppear {
                startClock()
                startTrigger()
            }
            .onChange(of: effect) { _, _ in
                reset()
                startTrigger()
            }
            .onChange(of: isDueSoon) { _, newValue in
                if newValue {
                    startTrigger()
                } else {
                    reset()
                }
            }
    }
    
    // MARK: - Visual
    
    private var opacityValue: Double {
        guard isDueSoon else { return 1 }
        
        switch effect {
        case .blink, .blinkIntermittent:
            return trigger ? 1 : 0.2
        default:
            return 1
        }
    }
    
    private var rotationValue: Double {
        guard isDueSoon else { return 0 }
        
        switch effect {
        case .rotateIntermittent:
            return trigger ? 360 : 0
        default:
            return 0
        }
    }
    
    private var scaleValue: CGFloat {
        guard isDueSoon else { return 1 }
        
        switch effect {
        case .pulse:
            return trigger ? 1.15 : 1
        default:
            return 1
        }
    }
    
    private var animation: Animation? {
        guard isDueSoon else { return nil }
        
        switch effect {
        case .blink:
            return .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
            
        case .pulse:
            return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            
        case .blinkIntermittent:
            return .easeInOut(duration: 0.8)
            
        case .rotateIntermittent:
            return .easeInOut(duration: 0.8)
            
        case .none:
            return nil
        }
    }
    
    // MARK: - Trigger Logic
    
    private func startTrigger() {
        
        guard isDueSoon else { return }
        
        switch effect {
            
        case .blink, .pulse:
            trigger = true
            
        case .blinkIntermittent, .rotateIntermittent:
            scheduleIntermittent()
            
        case .none:
            break
        }
    }
    
    private func scheduleIntermittent() {
        
        trigger = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            trigger = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if isDueSoon {
                startTrigger()
            }
        }
    }
    
    private func reset() {
        trigger = false
    }
    
    // MARK: - Clock
    
    private func startClock() {
        
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            now = Date()
        }
    }
}

extension View {
    
    func dueIconEffect(
        deadline: Date?,
        effect: DueIconEffect
    ) -> some View {
        
        modifier(
            DueIconEffectModifier(
                deadline: deadline,
                effect: effect
            )
        )
    }
}
