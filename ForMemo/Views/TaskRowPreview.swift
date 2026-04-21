import SwiftUI

struct TaskRowPreview: View {
    
    @AppStorage("TaskListStyle")
    private var listStyleChoice: TaskListStyle = .cards
    
    @AppStorage("selectedTaskRowStyle")
    private var selectedRowStyle: Int = 0

    @AppStorage("tasklist.highlightCriticalOverdue")
    private var highlightCriticalOverdue: Bool = true

    @AppStorage("tasklist.showTodayExpiredLabel")
    private var showTodayExpiredLabel: Bool = true
    
    
    let iconStyle: TaskIconStyle
    let badgeStyle: BadgeColorStyle
    let showBadge: Bool
    let showAttachments: Bool
    let showLocation: Bool
    let showPriority: Bool
    let showBadgeOnlyWithPriority: Bool
    
    // MARK: - Computed Style (più pulito)
    private var rowStyle: TaskRowStyle {
        TaskRowStyle(rawValue: selectedRowStyle) ?? .style0
    }
    
    // MARK: - Preview Model (più realistico)
    private var model: TaskRowDisplayModel {
        
        let hasPriority = true
        
        let shouldDisplayBadge =
        showBadge && (!showBadgeOnlyWithPriority || hasPriority)
        
        return TaskRowDisplayModel(
            id: UUID(),
            title: String(localized: "Preview"),
            subtitle: "Meeting with the medical team",
            mainIcon: "bubbles.and.sparkles",
            statusColor: .orange,
            hasValidAttachments: showAttachments,
            hasLocation: showLocation,
            badgeText: "3",
            prioritySystemImage: showPriority ? "flame" : nil,
            deadLine: .now.addingTimeInterval(60 * 60),
            reminderOffsetMinutes: 60,
            shouldShowBadge: shouldDisplayBadge,
            isCompleted: false
        )
    }
    
    var body: some View {
        
        List {
            Section {
                
                TaskRowContent(
                    model: model,
                    iconStyle: iconStyle,
                    badgeStyle: badgeStyle,
                    showBadge: model.shouldShowBadge,
                    showAttachments: showAttachments,
                    showLocation: showLocation,
                    showPriority: showPriority,
                    showBadgeOnlyWithPriority: showBadgeOnlyWithPriority,
                    rowStyle: rowStyle,
                    highlightCriticalOverdue: highlightCriticalOverdue,
                    showTodayExpiredLabel: showTodayExpiredLabel
                )
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets)              // ✅ fondamentale
                .listRowBackground(rowBackground)      // ✅ fondamentale
            }
        }
        .TaskListStyle(listStyleChoice)
        .scrollDisabled(true)
    }
}

// MARK: - LIST STYLE HELPERS

private extension TaskRowPreview {
    
    var rowInsets: EdgeInsets {
        switch listStyleChoice {
        case .cards:
            return EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        case .plain:
            return EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
        }
    }
    
    @ViewBuilder
    var rowBackground: some View {
        switch listStyleChoice {
        case .cards:
            let deadline = model.deadLine ?? .distantFuture
            let isToday = Calendar.current.isDateInToday(deadline) && deadline >= Date()
            let isOverdue = deadline < Date()
            let isCritical = model.prioritySystemImage == "flame"

            let shouldHighlight = highlightCriticalOverdue && isCritical && (isToday || isOverdue)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    shouldHighlight
                    ? AnyShapeStyle(Color.red.opacity(0.12))
                    : AnyShapeStyle(.ultraThinMaterial)
                )
        case .plain:
            Color.clear
        }
    }
}

// MARK: - LIST STYLE EXTENSION

private extension View {
    
    @ViewBuilder
    func TaskListStyle(_ style: TaskListStyle) -> some View {
        switch style {
        case .cards:
            self.listStyle(.insetGrouped)
        case .plain:
            self.listStyle(.plain)
        }
    }
}
