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
    let materialStyle: SurfaceMaterialStyle
    
    private var separatorColor: Color {
        TaskRowTheme.separator(colorScheme: colorScheme)
    }
    private var materialLayer: some View {

        Group {

            switch materialStyle {

            case .none:

                EmptyView()

            case .soft:

                shape.fill(.ultraThinMaterial)

            case .medium:

                shape.fill(.thinMaterial)

            case .strong:

                shape.fill(.regularMaterial)

            case .extraStrong:

                shape.fill(.thickMaterial)
            }
        }
    }
    
    var body: some View {

        ZStack {

            materialLayer

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
//        .shadow(
//            color: Color.primary.opacity(shadowStyle.opacity),
//            radius: shadowStyle.radius,
//            x: 0,
//            y: shadowStyle.yOffset
//        )
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

    private var baseFillOpacity: Double {
        switch materialStyle {
        case .none:
            return 1.0
        case .soft:
            return 0.70
        case .medium:
            return 0.55
        case .strong:
            return 0.40
        case .extraStrong:
            return 0.25
        }
    }

    private var baseFillLayer: some View {
        shape
            .fill(
                TaskRowTheme.cardFill(
                    isToday: isToday,
                    colorScheme: colorScheme
                )
            )
            .opacity(baseFillOpacity)
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




