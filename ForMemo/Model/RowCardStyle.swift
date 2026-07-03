import SwiftUI

struct RowCardStyle: ViewModifier {

    @Environment(AppSettings.self) private var settings

    let task: TodoTask
    let style: TaskListStyle
    let position: TaskRowPosition
    let opacity: Double

    private var highlightColor: Color {
        Color(hex: settings.highlightColorHex) ?? .red
    }

    func body(content: Content) -> some View {

        content
            .padding(
                .leading,
                TaskRowMetrics.leadingPadding(for: style)
            )
            .padding(
                .trailing,
                TaskRowMetrics.trailingPadding(for: style)
            )
            .listRowInsets(
                TaskRowMetrics.insets(
                    for: style,
                    position: position
                )
            )
            .listRowBackground(
                RowBackground(
                    style: style,
                    position: position,
                    task: task,
                    highlightEnabled: settings.highlightEnabled,
                    highlightColor: highlightColor,
                    opacity: opacity
                )
            )
            .listRowSeparator(.hidden)
    }
}
