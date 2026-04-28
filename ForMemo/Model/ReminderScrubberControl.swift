import SwiftUI

struct ReminderScrubberControl: View {
    
    enum Mode: Int, CaseIterable {
        case none, minutes, hours, days
    }
    
    @Binding var reminderOffsetMinutes: Int?
    @State private var localOffset: Int? = nil
    let notificationLeadTimeDays: Int
    
    // Computed mode e value calcolati direttamente dal binding
    private var mode: Mode {
        let offsetValue = localOffset ?? reminderOffsetMinutes
        guard let offset = offsetValue else { return .none }
        if offset <= 59 { return .minutes }
        if offset <= 1439 { return .hours }
        return .days
    }
    
    private var value: Int {
        let offsetValue = localOffset ?? reminderOffsetMinutes
        guard let offset = offsetValue else { return 1 }
        switch mode {
        case .minutes: return offset
        case .hours: return offset / 60
        case .days: return offset / 1440
        default: return 1
        }
    }
    
    private var maxValue: Int {
        switch mode {
        case .minutes: return 60
        case .hours: return 23
        case .days: return 7
        default: return 1
        }
    }
    
    private var stepperLabel: String {
        switch mode {
        case .minutes: return String(localized:"\(value) minutes before")
        case .hours: return String(localized:"\(value) hours before")
        case .days: return String(localized:"\(value) days before")
        default: return ""
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Reminder", selection: Binding(
                get: { mode },
                set: { newMode in applyMode(newMode) }
            )) {
                Text("None").tag(Mode.none)
                Text("Minutes before").tag(Mode.minutes)
                Text("Hours before").tag(Mode.hours)
                Text("Days before").tag(Mode.days)
            }
            .pickerStyle(.menu)
            .padding(.bottom, 10)
            .onAppear {
                localOffset = reminderOffsetMinutes
            }
            
            if mode == .minutes || mode == .hours || mode == .days {
                Stepper(value: Binding(
                    get: { value },
                    set: { applyValue($0) }
                ), in: 1...maxValue, step: 1) {
                    Text(stepperLabel)
                }
            }
        }
        .onChange(of: localOffset) { _, newValue in
            // Debounce-like behavior: commit after small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if localOffset == newValue {
                    reminderOffsetMinutes = newValue
                }
            }
        }
    }
    
    private func applyMode(_ newMode: Mode) {
        switch newMode {
        case .none: localOffset = nil
        case .minutes: localOffset = 1
        case .hours: localOffset = 60
        case .days: localOffset = 1440
        }
    }
    
    private func applyValue(_ newValue: Int) {
        switch mode {
        case .minutes:
            if newValue == 60 { applyMode(.hours); return }
            localOffset = newValue
        case .hours:
            if newValue == 24 { applyMode(.days); return }
            localOffset = newValue * 60
        case .days:
            localOffset = newValue * 1440
        default: break
        }
    }
}
