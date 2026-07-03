import SwiftUI

struct RowBackground: View {

    @Environment(AppSettings.self)
    private var settings

    @Environment(\.colorScheme)
    private var colorScheme
    
    
    let style: TaskListStyle
    let position: TaskRowPosition
    let task: TodoTask

    let highlightEnabled: Bool
    let highlightColor: Color

    var opacity: Double = 1.0
    var showSeparator: Bool = true

    private var shape: TaskRowShape {
        TaskRowShape(
            position: position,
            cornerRadius: CGFloat(settings.surfaceCornerRadius)
        )
    }

    var body: some View {
        let isToday = task.deadLine.map(Calendar.current.isDateInToday) ?? false
        let isOverdue = (task.deadLine ?? .distantFuture) < Date()
        let isCritical = task.priority.systemImage == "flame"

        let isHighlighted =
            highlightEnabled &&
            isCritical &&
            (isToday || isOverdue)

        ZStack {
            TaskRowSurface(
                shape: style == .plain
                    ? AnyInsettableShape(
                        RoundedRectangle(
                            cornerRadius: 0,
                            style: .continuous
                        )
                    )
                    : AnyInsettableShape(shape),
                isToday: isToday,
                isGrouped: style == .grouped,
                isHighlighted: isHighlighted,
                highlightColor: highlightColor,
                showSeparator: style == .plain
                    ? true
                    : (showSeparator && position != .last && position != .single),
                materialStyle: settings.surfaceMaterial
            )
            
            
            TaskRowBorder(
                shape: style == .plain
                    ? AnyInsettableShape(
                        RoundedRectangle(
                            cornerRadius: 0,
                            style: .continuous
                        )
                    )
                    : AnyInsettableShape(shape),
                position: position,
                lineWidth: settings.surfaceBorder.lineWidth,
                cornerRadius: CGFloat(settings.surfaceCornerRadius),
                color: TaskRowTheme.separator(colorScheme: colorScheme)
            )
        }
        .opacity(opacity)
    }
}
