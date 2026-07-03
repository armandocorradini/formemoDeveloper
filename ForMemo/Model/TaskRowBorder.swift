import SwiftUI

struct TaskRowBorder: View {

    let shape: AnyInsettableShape

    let position: TaskRowPosition

    let lineWidth: CGFloat
    let cornerRadius: CGFloat
    
    let color: Color

    var body: some View {
        
        switch position {
        case .single:
            if lineWidth > 0 {
                shape
                    .strokeBorder(
                        color,
                        lineWidth: lineWidth
                    )
            } else {
                EmptyView()
            }
        case .first:
            if lineWidth > 0 {
                GeometryReader { geometry in
                    let rect = geometry.frame(in: .local)
                    let inset = lineWidth / 2
                    let radius = cornerRadius

                    Path { path in
                        // lato sinistro
                        path.move(to: CGPoint(x: inset, y: rect.maxY))
                        path.addLine(to: CGPoint(x: inset, y: radius))

                        // angolo alto sinistro
                        path.addArc(
                            center: CGPoint(x: radius, y: radius),
                            radius: radius - inset,
                            startAngle: .degrees(180),
                            endAngle: .degrees(270),
                            clockwise: false
                        )

                        // lato superiore
                        path.addLine(to: CGPoint(x: rect.maxX - radius, y: inset))

                        // angolo alto destro
                        path.addArc(
                            center: CGPoint(x: rect.maxX - radius, y: radius),
                            radius: radius - inset,
                            startAngle: .degrees(270),
                            endAngle: .degrees(0),
                            clockwise: false
                        )

                        // lato destro
                        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
                    }
                    .stroke(color, lineWidth: lineWidth)
                }
            } else {
                EmptyView()
            }

        case .middle:
            if lineWidth > 0 {
                GeometryReader { geometry in
                    let rect = geometry.frame(in: .local)
                    let inset = lineWidth / 2

                    Path { path in
                        // lato sinistro
                        path.move(to: CGPoint(x: inset, y: 0))
                        path.addLine(to: CGPoint(x: inset, y: rect.maxY))

                        // lato destro
                        path.move(to: CGPoint(x: rect.maxX - inset, y: 0))
                        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
                    }
                    .stroke(color, lineWidth: lineWidth)
                }
            } else {
                EmptyView()
            }

        case .last:
            if lineWidth > 0 {
                GeometryReader { geometry in
                    let rect = geometry.frame(in: .local)
                    let inset = lineWidth / 2
                    let radius = cornerRadius

                    Path { path in
                        // lato sinistro
                        path.move(to: CGPoint(x: inset, y: 0))
                        path.addLine(to: CGPoint(x: inset, y: rect.maxY - radius))

                        // angolo basso sinistro
                        path.addArc(
                            center: CGPoint(x: radius, y: rect.maxY - radius),
                            radius: radius - inset,
                            startAngle: .degrees(180),
                            endAngle: .degrees(90),
                            clockwise: true
                        )

                        // lato inferiore
                        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - inset))

                        // angolo basso destro
                        path.addArc(
                            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                            radius: radius - inset,
                            startAngle: .degrees(90),
                            endAngle: .degrees(0),
                            clockwise: true
                        )

                        // lato destro
                        path.addLine(to: CGPoint(x: rect.maxX - inset, y: 0))
                    }
                    .stroke(color, lineWidth: lineWidth)
                }
            } else {
                EmptyView()
            }

        }
    }
}
