import SwiftUI

enum TaskIconStyle: String, CaseIterable, Codable {
    case polychrome
    case monochrome
}

enum BadgeColorStyle: String, CaseIterable, Codable {
    
    case `default`
    case blue
    case red
    case green
    case gray
    case yellow
    case orange
    case pink
    case purple
    case teal
    case indigo
    case mint
    case cyan
    
    var color: Color {
        switch self {
        case .default: .clear   // gestito come status color
        case .blue: .blue
        case .red: .red
        case .green: .green
        case .gray: .gray
        case .yellow: .yellow
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .teal: .teal
        case .indigo: .indigo
        case .mint: .mint
        case .cyan: .cyan
        }
    }
    
    
    var localizedTitle: String {
        
        switch self {
        case .default:
            return String(localized: "Match Icon")
        case .blue:
            return String(localized: "Blue")
        case .red:
            return String(localized: "Red")
        case .green:
            return String(localized: "Green")
        case .gray:
            return String(localized: "Gray")
        case .yellow:
            return String(localized: "Yellow")
        case .orange:
            return String(localized: "Orange")
        case .pink:
            return String(localized: "Pink")
        case .purple:
            return String(localized: "Purple")
        case .teal:
            return String(localized: "Teal")
        case .indigo:
            return String(localized: "Indigo")
        case .mint:
            return String(localized: "Mint")
        case .cyan:
            return String(localized: "Cyan")
        }
    }
    
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
    
    @AppStorage("TaskListStyle")
    private var listStyleChoice: TaskListStyle = .cards
    @AppStorage(TaskListAppearanceKeys.showBadgeOnlyWithPriority)
    private var showBadgeOnlyWithPriority = true
    
    @AppStorage(TaskListAppearanceKeys.highlightCriticalOverdue)
    private var highlightCriticalOverdue = true
    
    @AppStorage(TaskListAppearanceKeys.showTodayExpiredLabel)
    private var showTodayExpiredLabel = true
    
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage(TaskListAppearanceKeys.iconStyle)
    private var iconStyle: TaskIconStyle = .polychrome
    
    @AppStorage(TaskListAppearanceKeys.badgeColor)
    private var badgeColorRaw: String = BadgeColorStyle.yellow.rawValue
    
    @AppStorage(TaskListAppearanceKeys.showBadge)
    private var showBadge = true
    
    @AppStorage(TaskListAppearanceKeys.showAttachments)
    private var showAttachments = true
    
    @AppStorage(TaskListAppearanceKeys.showLocation)
    private var showLocation = true
    
    @AppStorage(TaskListAppearanceKeys.showPriority)
    private var showPriority = true
    
    @AppStorage("dueIconEffect")
    private var dueIconEffectRaw: String = DueIconEffect.blink.rawValue
    private var selectedDueEffect: DueIconEffect {
        DueIconEffect(rawValue: dueIconEffectRaw) ?? .blink
    }
    
    @AppStorage("selectedTaskRowStyle") private var selectedRowStyle: Int = 0
    
    private var badgeStyle: BadgeColorStyle {
        BadgeColorStyle(rawValue: badgeColorRaw) ?? .default
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
            // 1. IL GRADIENTE (Sotto a tutto)
            LinearGradient(colors: [backColor1, backColor2],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // 2. IL MATERIAL (Effetto vetro)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            
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
            .navigationTitle("List")
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
            .onChange(of: dueIconEffectRaw) { _, _ in
                refreshID = UUID()
            }
            .onChange(of: highlightCriticalOverdue) { _, _ in
                refreshID = UUID()
            }
            .onChange(of: showTodayExpiredLabel) { _, _ in
                refreshID = UUID()
            }
        }
        
        
    }
    
    private var previewTask: TodoTask {
        let task = TodoTask()
        task.title = String(localized: "Preview")
        task.taskDescription = "Meeting with the medical team"
        task.priority = .critical
        task.deadLine = Date().addingTimeInterval(3600)
        task.reminderOffsetMinutes = 60
        task.isCompleted = false
        return task
    }
    
    
    @ViewBuilder
    private var previewRow: some View {

        List {
            TaskRow(task: previewTask)
                .modifier(TodoSectionView.RowCardStyle(
                    task: previewTask,
                    style: listStyleChoice
                ))
                .padding(.horizontal, listStyleChoice == .plain ? 12 : 0)
                .listRowInsets(
                    listStyleChoice == .cards
                    ? EdgeInsets(top: 20, leading: 8, bottom: 20, trailing: 8)
                    : EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)
                )
                .listRowSeparator(.hidden)
        }
        .scrollDisabled(true)
        .contentMargins(.top, 18, for: .scrollContent)
        .contentMargins(.horizontal, 8, for: .scrollContent)
        .frame(height: 140)
        .modifier(ListStyleModifier(style: listStyleChoice))
    }
    
    private var appearanceSection: some View {
        
        Section("Appearance") {
            
            Picker("Main icon style", selection: $iconStyle) {
                Text("Polychrome").tag(TaskIconStyle.polychrome)
                Text("Monochrome").tag(TaskIconStyle.monochrome)
            }
            
            Picker("Row Style", selection: $selectedRowStyle) {
                ForEach(0..<rowOptions.count, id: \.self) { index in
                    Text(rowOptions[index]).tag(index)
                }
                
                .pickerStyle(.inline)
            }
            Picker("Animation", selection: $dueIconEffectRaw) {
                
                ForEach(DueIconEffect.allCases) { effect in
                    Text(effect.title)
                        .tag(effect.rawValue)
                }
            }
            
            Picker("Days badge color", selection: $badgeColorRaw) {
                ForEach(BadgeColorStyle.allCases, id: \.rawValue) {
                    Text($0.localizedTitle)
                        .tag($0.rawValue)
                }
            }
        }
    }
    
    private var visibleElementsSection: some View {
        
        Section("Visible elements") {
            
            Toggle(
                "Highlight overdue & today (critical priority)",
                isOn: $highlightCriticalOverdue
            )
            Toggle(
                "Show “Today/Expired”",
                isOn: $showTodayExpiredLabel
            )
            Toggle("Show days badge", isOn: $showBadge)
            Toggle("Show badge only when priority is set", isOn: $showBadgeOnlyWithPriority)
            Toggle("Show attachments icon", isOn: $showAttachments)
            Toggle("Show location icon", isOn: $showLocation)
            Toggle("Show priority icon", isOn: $showPriority)

        }
    }
    
    
    private func reset() {
        
        iconStyle = .polychrome
        dueIconEffectRaw = DueIconEffect.blink.rawValue
        badgeColorRaw = BadgeColorStyle.yellow.rawValue
        showBadge = true
        showAttachments = true
        showLocation = true
        showPriority = true
        showBadgeOnlyWithPriority = true
        highlightCriticalOverdue = true
        showTodayExpiredLabel = true
        selectedRowStyle = 0
    }
}

private struct ListStyleModifier: ViewModifier {
    let style: TaskListStyle

    func body(content: Content) -> some View {
        if style == .cards {
            content.listStyle(.insetGrouped)
        } else {
            content.listStyle(.plain)
        }
    }
}
