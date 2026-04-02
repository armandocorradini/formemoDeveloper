import SwiftUI

struct TaskIconContent: View {
    
    let model: TaskRowDisplayModel
    
    let iconStyle: TaskIconStyle
    let badgeStyle: BadgeColorStyle
    
    let showBadge: Bool
    let showAttachments: Bool
    let showLocation: Bool
    let showBadgeOnlyWithPriority: Bool
    
    @AppStorage("dueIconEffect")
    private var dueIconEffectRaw: String = DueIconEffect.blink.rawValue
    
    private var selectedEffect: DueIconEffect {
        DueIconEffect(rawValue: dueIconEffectRaw) ?? .blink
    }
    
    private var shouldShowBadge: Bool {
        
        guard showBadge else { return false }
        
        if showBadgeOnlyWithPriority {
            return model.prioritySystemImage != nil
        }
        
        return true
    }
    
    let size : CGFloat = 48
    
    var body: some View {
        
        ZStack(alignment: .topTrailing) {
            
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    //                    Circle()
                    RoundedRectangle(cornerRadius: model.statusColor == .red ? 30 : 12, style: .continuous)
                        .stroke(model.statusColor.opacity(1).gradient,     lineWidth: model.statusColor == .red ? 4 : (model.statusColor == .orange ? 4 : 0.5))
                        .shadow(color: .black.opacity(0.5), radius: 0.5, x: 0.5, y: 0.5)
                    //                        .fill(model.statusColor.opacity(1).gradient)//0.15))
                    
                    if iconStyle == .monochrome {
                        
                        Image(systemName: model.mainIcon)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .foregroundStyle(model.statusColor)//.black, .white)
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
                            .foregroundStyle(.primary ,model.statusColor)
                            .font(.title)
                            .dueIconEffect(
                                deadline: model.deadLine,
                                effect: selectedEffect
                            )
                        
                    }
                }
                .frame(width: size, height: size)
                
                
            }
            
            if shouldShowBadge,
               let text = model.badgeText {
                
                let resolvedBadgeColor: Color =
                badgeStyle == .default
                ? model.statusColor
                : badgeStyle.color
                
                let badgeSize: CGFloat = 21
                
                let needsBorder =
                resolvedBadgeColor.isVisuallyEqual(to: model.statusColor)
                
                ZStack {
                    
                    Circle()
                        .fill(resolvedBadgeColor)
                    
                    if needsBorder {
                        Circle()
                            .stroke(.black, lineWidth: 1)
                    }
                    
                    Text(text)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.black)
                        .padding(3)
                }
                .frame(width: badgeSize, height: badgeSize)
                .offset(x: size / 6, y: -size / 6)
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
