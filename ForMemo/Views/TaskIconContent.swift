import SwiftUI

struct TaskIconContent: View {
    
    let model: TaskRowDisplayModel
    let iconStyle: TaskIconStyle
    let showAttachments: Bool
    let showLocation: Bool

    
    @AppStorage("dueIconEffect")
    private var dueIconEffectRaw: String = DueIconEffect.blink.rawValue
    
    private var selectedEffect: DueIconEffect {
        DueIconEffect(rawValue: dueIconEffectRaw) ?? .blink
    }
    
    private var shouldShowBadge: Bool {
        model.shouldShowBadge
    }
    
    let size : CGFloat = 48
    
    var body: some View {
        
        ZStack {
            // Icon layer (with palette)
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    //                    Circle()
                    RoundedRectangle(cornerRadius: model.statusColor == .red ? 30 : 12, style: .continuous)
                        .stroke(model.statusColor.opacity(1).gradient,     lineWidth: model.statusColor == .red ? 2 : (model.statusColor == .orange ? 2 : 0.5))
                        .shadow(color: .black.opacity(0.5), radius: 0.5, x: 0.5, y: 0.5)
                    //                        .fill(model.statusColor.opacity(1).gradient)//0.15))
                    
                    if iconStyle == .monochrome {
                        
                        Image(systemName: model.mainIcon)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .foregroundStyle(model.mainTag?.color ?? model.statusColor)
                            .font(.title)
                            .shadow(color: .black.opacity(0.5), radius: 0.5, x: 0.5, y: 0.5)
                            .shadow(color: .black.opacity(0.5), radius: 0.5, x: -0.5, y: -0.5)
                            .dueIconEffect(
                                deadline: model.deadLine,
                                effect: selectedEffect
                            )
                    } else {
                        
                        Image(systemName: model.mainIcon)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                        //                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(model.mainTag?.color ?? model.statusColor, .primary)
                            .font(.title)
                            .dueIconEffect(
                                deadline: model.deadLine,
                                effect: selectedEffect
                            )
                        
                    }
                }
                .frame(width: size, height: size)
                
                
            }
        }
        .overlay(alignment: .topTrailing) {
            if shouldShowBadge,
               let deadline = model.deadLine,
               let badge = model.badgeText {

                let count = badge.count

                TaskBadgeView(
                    deadline: deadline,
                    badgeText: badge,
                    statusColor: model.statusColor
                )
                .offset(x: count == 1 ? 6 : (count == 2 ? 14 : (count == 3 ? 17 : 18)), y: -9)
            }
        }
    }
}

import UIKit

private extension Color {
    
    var isLight: Bool {
        
        let uiColor = UIColor(self)
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return false
        }
        
        // luminanza percepita
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.7
    }
    
    func isVisuallyEqual(to other: Color) -> Bool {
        
        let lhs = UIColor(self)
        let rhs = UIColor(other)
        
        return lhs.isEqual(rhs)
    }
}
