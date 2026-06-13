import SwiftUI

enum TaskIconStyle: String, CaseIterable, Codable {
    case polychrome
    case monochrome
}
enum TaskListAppearanceKeys {
    static let iconStyle = "tasklist.iconStyle"
    static let badgeColor = "tasklist.badgeColor"
    static let showBadge = "tasklist.showBadge"
    static let showAttachments = "tasklist.showAttachments"
    static let showLocation = "tasklist.showLocation"
    static let showPriority = "tasklist.showPriority"
    static let showBadgeOnlyWithPriority = "tasklist.showBadgeOnlyWithPriority"
    static let highlightCriticalOverdue = "tasklist.highlightCriticalOverdue"
    static let showTodayExpiredLabel = "tasklist.showTodayExpiredLabel"
}

struct TaskListAppearanceView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    
    private var listStyleChoice: TaskListStyle {
        settings.taskListStyle
    }
    
    // Etichette dei vari stili disponibili
    private let rowOptions = [
        String(localized: "Default"),
        String(localized: "Style 1"),
        String(localized: "Style 2"),
        String(localized: "Style 3"),
        String(localized: "Style 4"),
        String(localized: "Style 5"),
        String(localized: "Style 6"),
        String(localized: "Style 7"),
        String(localized: "Style 8"),
        String(localized: "Style 9"),
        String(localized: "Style 10")
    ]
    
    @State private var refreshID = UUID()
    
    var body: some View {
        
        ZStack {
            AppGlassBackground()
            
            VStack(spacing: 0) {
                
                previewRow
                    .padding(.top, -20)
                
                Form {
                    
                    appearanceSection
                    visibleElementsSection
                }
                .padding(.top, 10)
                
            }
            .id(refreshID)
            .listRowInsets(
                .init(top: 2, leading: 2, bottom: 2, trailing: 2)
            )
            .scrollContentBackground(.hidden)
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        withAnimation(.snappy) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Default") {
                        reset()
                    }
                }
            }
            .onChange(of: settings.dueIconEffect) { _, _ in
                refreshID = UUID()
            }
            .onChange(of: settings.showTodayExpiredLabel) { _, _ in
                refreshID = UUID()
            }
        }
        
        
    }
    
    private var previewTask: TodoTask {
        let task = TodoTask()
        task.title = String(localized: "Preview")
        task.priority = .critical
        task.deadLine = Date().addingTimeInterval(60)
        task.reminderOffsetMinutes = 60
        task.isCompleted = false
        task.locationName = "Office"
        task.mainTag = .freetime
        task.attachments = [TaskAttachment.previewMock]
        
        return task
    }
    
    @ViewBuilder
    private var previewRow: some View {

        List {
            TaskRow(
                task: previewTask,
                showDateColumn: true,
                appearance: TaskRowAppearance(
                    iconStyle: settings.iconStyle,
                    showBadge: settings.showBadge,
                    showAttachments: settings.showAttachments,
                    showLocation: settings.showLocation,
                    showPriority: settings.showPriority,
                    showBadgeOnlyWithPriority: settings.showBadgeOnlyWithPriority,
                    highlightEnabled: settings.highlightEnabled,
                    showTodayExpiredLabel: settings.showTodayExpiredLabel,
                    selectedRowStyle: settings.selectedRowStyle,
                    dueIconEffect: settings.dueIconEffect
                )
            )
                .modifier(
                    TodoSectionView.RowCardStyle(
                        task: previewTask,
                        style: listStyleChoice,
                        position: .single,
                        showBottomSeparator: false
                    )
                )
                .padding(.horizontal, listStyleChoice == .plain ? 12 : 0)
                .listRowInsets(
                    listStyleChoice == .grouped
                    ? EdgeInsets(top: 20, leading: 8, bottom: 20, trailing: 8)
                    : EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
                )
                .listRowSeparator(.hidden)
        }
        .scrollDisabled(true)
        .contentMargins(.top, 18, for: .scrollContent)
        .contentMargins(.horizontal, 8, for: .scrollContent)
        .frame(height: 120)
        .modifier(ListStyleModifier(style: listStyleChoice))
    }
    
    private var appearanceSection: some View {
        
        Section("Appearance") {
            
            Picker("Main icon style", selection: Bindable(settings).iconStyle) {
                Text("Polychrome").tag(TaskIconStyle.polychrome)
                Text("Monochrome").tag(TaskIconStyle.monochrome)
            }
            
            Picker("Row Style", selection: Bindable(settings).selectedRowStyle) {
                ForEach(0..<rowOptions.count, id: \.self) { index in
                    Text(rowOptions[index]).tag(index)
                }
            }
            .pickerStyle(.menu)
            .tint(.secondary)
            Picker("Animation", selection: Bindable(settings).dueIconEffect) {
                ForEach(DueIconEffect.allCases) { effect in
                    Text(effect.title)
                        .tag(effect as DueIconEffect)
                }
            }
            .pickerStyle(.menu)
            .tint(.secondary)
            
        }
    }
    
    private var visibleElementsSection: some View {
        
        Section("Visible elements") {
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text("Highlight overdue & today (critical priority)")

                    Spacer()

                    Toggle("", isOn: Bindable(settings).highlightEnabled)
                        .labelsHidden()
                }

                let palette: [Color] = [
                    .red, .orange, .yellow, .green,
                     .cyan, .blue, .indigo,
                    .purple, .brown
                ]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(palette, id: \.self) { color in
                            let hex = color.toHex() ?? ""
                            let isSelected = settings.highlightColorHex == hex

                            Circle()
                                .fill(color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 2)
                                        .opacity(isSelected ? 1 : 0)
                                )
                                .shadow(color: isSelected ? .black.opacity(0.2) : .clear, radius: 3)
                                .scaleEffect(isSelected ? 1.15 : 1.0)
                                .onTapGesture {
                                    settings.highlightColorHex = hex
                                }
                                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 3)
                }
                .frame(minHeight: 36)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .disabled(!settings.highlightEnabled)
                .opacity(!settings.highlightEnabled ? 0.4 : 1)
            }
            Toggle(
                "Underline overdue tasks",
                isOn: Bindable(settings).showTodayExpiredLabel
            )
            Toggle("Show days badge", isOn: Bindable(settings).showBadge)
            Toggle("Show badge only when priority is set", isOn: Bindable(settings).showBadgeOnlyWithPriority)
            Toggle("Show attachments icon", isOn: Bindable(settings).showAttachments)
            Toggle("Show location icon", isOn: Bindable(settings).showLocation)
            Toggle("Show priority icon", isOn: Bindable(settings).showPriority)

        }
    }
    
    
    private func reset() {
        
        settings.iconStyle = .polychrome
        settings.showBadge = true
        settings.showAttachments = true
        settings.showLocation = true
        settings.showPriority = true
        settings.showBadgeOnlyWithPriority = true
        settings.highlightEnabled = true
        settings.highlightColorHex = Color.red.toHex() ?? ""
        settings.showTodayExpiredLabel = true
        settings.selectedRowStyle = 0
        settings.dueIconEffect = .blink
    }
}

private struct ListStyleModifier: ViewModifier {
    let style: TaskListStyle

    func body(content: Content) -> some View {
        if style == .grouped {
            content.listStyle(.insetGrouped)
        } else {
            content.listStyle(.plain)
        }
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

        let r, g, b, a: UInt64

        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = (
                (int >> 8) * 17,
                (int >> 4 & 0xF) * 17,
                (int & 0xF) * 17,
                255
            )
        case 6: // RGB (24-bit)
            (r, g, b, a) = (
                int >> 16,
                int >> 8 & 0xFF,
                int & 0xFF,
                255
            )
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (
                int >> 24,
                int >> 16 & 0xFF,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String? {
        let uiColor = UIColor(self)
        guard let components = uiColor.cgColor.components else { return nil }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        let a = components.count >= 4 ? Float(components[3]) : 1.0

        return String(format: "#%02lX%02lX%02lX%02lX",
                      Int(a * 255),
                      Int(r * 255),
                      Int(g * 255),
                      Int(b * 255))
    }
}
