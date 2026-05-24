import SwiftUI

struct TaskRowSurface<S: InsettableShape>: View {

    @Environment(\.colorScheme)
    private var colorScheme

    let shape: S
    let isToday: Bool
    let isGrouped: Bool
    let isHighlighted: Bool
    let highlightColor: Color
    let showSeparator: Bool

    private var shadowColor: Color {
        TaskRowTheme.shadow(colorScheme: colorScheme)
    }

    private var separatorColor: Color {
        TaskRowTheme.separator(colorScheme: colorScheme)
    }

    var body: some View {

        ZStack {

            shadowLayer

            if isGrouped && !isToday {
                groupedBackgroundLayer
            }

            baseFillLayer
        }
        .compositingGroup()
        .overlay(alignment: .leading) {

            if isHighlighted {

                RoundedRectangle(
                    cornerRadius: TaskRowTheme.highlightCornerRadius,
                    style: .continuous
                )
                .fill(highlightColor)
                .frame(
                    width: TaskRowMetrics.highlightBarWidth,
                    height: TaskRowMetrics.highlightBarHeight
                )
                .frame(maxHeight: .infinity)
                .padding(.leading, TaskRowTheme.highlightLeadingPadding)
            }
        }
        .overlay(alignment: .bottomLeading) {

            if showSeparator {
                Capsule(style: .continuous)
                    .fill(separatorColor)
                    .frame(height: TaskRowMetrics.separatorHeight)
                    .padding(.leading, TaskRowMetrics.separatorLeadingInset)
                    .padding(.trailing, TaskRowMetrics.separatorTrailingInset)
            }
        }
        .shadow(
            color: shadowColor,
            radius: TaskRowMetrics.shadowRadius,
            x: 0,
            y: TaskRowMetrics.shadowYOffset
        )
    }

    private var shadowLayer: some View {
        shape
            .fill(shadowColor.opacity(
                colorScheme == .dark
                ? TaskRowRendering.shadowOpacityDark
                : TaskRowRendering.shadowOpacityLight
            ))
            .blur(
                radius: TaskRowMetrics.shadowRadius * TaskRowRendering.shadowBlurFactor
            )
            .offset(x: 0, y: TaskRowRendering.shadowLayerYOffset)
    }

    private var groupedBackgroundLayer: some View {
        shape
            .fill(
                TaskRowTheme.groupedBackgroundLayer(
                    colorScheme: colorScheme
                )
            )
            .compositingGroup()
    }

    private var baseFillLayer: some View {
        shape
            .fill(
                TaskRowTheme.cardFill(
                    isToday: isToday,
                    colorScheme: colorScheme
                )
            )
    }
}



struct AnyInsettableShape: InsettableShape, @unchecked Sendable {

    private let pathBuilder: (CGRect) -> Path
    private let insetBuilder: (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {

        pathBuilder = { rect in
            shape.path(in: rect)
        }

        insetBuilder = { amount in
            AnyInsettableShape(shape.inset(by: amount))
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        insetBuilder(amount)
    }
}
