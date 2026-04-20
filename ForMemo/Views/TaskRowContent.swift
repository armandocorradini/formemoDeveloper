

import SwiftUI

// MARK: - STYLE ENUM

enum TaskRowStyle: Int {
    case style0 = 0
    case style1 = 1
    case style2 = 2
    case style3 = 3
    case style4 = 4
    case style5 = 5
    case style6 = 6
    case style7 = 7
    case style8 = 8
    case style9 = 9
    case style10 = 10
    case today = 100
}

// MARK: - MAIN ROW

struct TaskRowContent: View, TaskRowBaseLogic {
    
    let model: TaskRowDisplayModel
    let iconStyle: TaskIconStyle
    let badgeStyle: BadgeColorStyle
    
    let showBadge: Bool
    let showAttachments: Bool
    let showLocation: Bool
    let showPriority: Bool
    let showBadgeOnlyWithPriority: Bool
    
    let rowStyle: TaskRowStyle
    
    @AppStorage("dueIconEffect") private var selectedEffectRaw: String = DueIconEffect.none.rawValue

    @AppStorage("tasklist.highlightCriticalOverdue")
    private var highlightCriticalOverdue: Bool = true
    
    private var selectedEffect: DueIconEffect {
        DueIconEffect(rawValue: selectedEffectRaw) ?? .none
    }
    
    
    var body: some View {
        content
            .padding(.vertical, rowStyle == .style0 ? 0 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

// MARK: - SWITCH

extension TaskRowContent {
    
    @ViewBuilder
    var content: some View {
        switch rowStyle {
        case .style0: layoutStyle0()
        case .style1: layoutStyle1()
        case .style2: layoutStyle2()
        case .style3: layoutStyle3()
        case .style4: layoutStyle4()
        case .style5: layoutStyle5()
        case .style6: layoutStyle6()
        case .style7: layoutStyle7()
        case .style8: layoutStyle8()
        case .style9: layoutStyle9()
        case .style10: layoutStyle10()
        case .today:  layoutToday()
        }
    }
    private func layoutStyle10() -> some View {
        HStack(spacing: 12) {
            
            // ICONA (sinistra)
            icon
                .scaleEffect(0.9)
                .frame(minWidth: 40)
                .offset(x: -4)
            
            // CONTENUTO (titolo + meta)
            VStack(alignment: .leading, spacing: 4) {
                
                // TITOLO
                Text(model.title)
                    .font(.headline)
                    .foregroundStyle(model.isCompleted ? .secondary : .primary)
                    .strikethrough(model.isCompleted)
                    .lineLimit(1)
                
                // META (remind + flags)
                HStack(spacing: 8) {
                    
                    if model.reminderOffsetMinutes != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "bell")
                            Text(formattedOffset(model: model))
                        }
                    }
                    
                    Spacer()
                    
                    flags(vertical: false)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // DATA (destra, compatta Apple style)
            if let d = model.deadLine {
                VStack(spacing: 2) {
                    
                    Text(d, format: .dateTime.day())
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    
                    Text(d, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                    
                    Text(d, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .opacity(0.8)
                }
                .frame(width: 44)
                .foregroundStyle(model.statusColor)
                .pulseEffect(active: isUrgent(model: model))
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
    }
}

// MARK: - BASE COMPONENTS

extension TaskRowContent {
    
    var icon: some View {
        TaskIconContent(
            model: model,
            iconStyle: iconStyle,
            badgeStyle: badgeStyle,
            showBadge: showBadge,
            showAttachments: false,
            showLocation: false,
            showBadgeOnlyWithPriority: showBadgeOnlyWithPriority
        )
    }
    
    @ViewBuilder
    var flagsContent: some View {
        if showPriority, let image = model.prioritySystemImage {
            Image(systemName: image)
        }
        if showAttachments, model.hasValidAttachments {
            Image(systemName: "paperclip")
        }
        if showLocation, model.hasLocation {
            Image(systemName: "location.fill")
        }
    }
    
    func flags(vertical: Bool) -> some View {
        Group {
            if vertical {
                VStack(spacing: 6) { flagsContent }
            } else {
                HStack(spacing: 6) { flagsContent }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
    
    func timeColumn(style: Int) -> some View {
        Group {
            if let d = model.deadLine {
                
                VStack(spacing: style == 1 ? 1 : 0) {
                    
                    if style == 6 {
                        Text(d, format: .dateTime.hour().minute())
                            .font(.system(size: 11, weight: .medium))
                    }
                    
                    Text(d, format: .dateTime.day())
                        .font(style == 1 ? .headline : .system(size: 22, weight: .bold, design: .rounded))
                    
                    Text(d, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                    
                    if style != 0 && style != 6 && style != 1 && style != 7  {
                        Text(d, format: .dateTime.hour().minute())
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .opacity(0.8)
                    }
                }
                .shadow(color: .black, radius: 0.1, x: 1, y: 1)
                .foregroundStyle(model.statusColor)
                .pulseEffect(active: isUrgent(model: model))
                
            } else {
                Image(systemName: "questionmark.square")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - STYLES

extension TaskRowContent {
    
    private func layoutStyle0() -> some View {
        HStack(spacing: 2) {
            
            timeColumn(style: 0)
                .frame(width: 44)
            
            icon
                .scaleEffect(0.8)
                .frame(minWidth: 40)
                .offset(x: -4)
            
            VStack(alignment: .leading, spacing: 4) {
                
                Text(model.title)
                    .font(.headline)
                    .foregroundStyle(model.isCompleted ? .secondary : .primary)
                    .strikethrough(model.isCompleted)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    
                    if let deadline = model.deadLine {
                        Image(systemName: "clock")
                            .foregroundStyle(model.statusColor)
                        Text(deadline, format: .dateTime.hour().minute())
                            .foregroundStyle(model.statusColor)
                    }
                    
                    if model.reminderOffsetMinutes != nil {
                        Image(systemName: "bell")
                        Text(formattedOffset(model: model))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            flags(vertical: true)
        }
    }
    
    private func layoutStyle1() -> some View {
        HStack(spacing: 12) {
            
            timeColumn(style: 1)
            
            VStack(alignment: .leading, spacing: 4) {
                
                HStack {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)
                    
                    Spacer()
                    
                    icon.scaleEffect(0.72)
                }
                
                HStack(spacing: 8) {
                    
                    if model.reminderOffsetMinutes != nil {
                        Image(systemName: "bell")
                        Text(formattedOffset(model: model))
                    }
                    
                    Spacer()
                    
                    flags(vertical: false)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(1)
    }
    
    private func layoutStyle2() -> some View {
        HStack(spacing: 12) {
            
            timeColumn(style: 2)
                .frame(width: 50)
            
            VStack(alignment: .leading) {
                
                HStack {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)
                    
                    Spacer()
                    
                    icon.scaleEffect(0.85)
                }
                
                HStack {
                    if model.reminderOffsetMinutes != nil {
                        Image(systemName: "bell")
                        Text(formattedOffset(model: model))
                    }
                    
                    Spacer()
                    
                    flags(vertical: false)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    private func layoutStyle3() -> some View {
        HStack(spacing: 12) {
            
            VStack(spacing: 4) {
                icon.scaleEffect(0.85)
                flags(vertical: false)
            }
            .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 6) {
                
                Text(model.title)
                    .font(.headline)
                    .strikethrough(model.isCompleted)
                    .lineLimit(1)
                
                if model.reminderOffsetMinutes != nil {
                    HStack {
                        Image(systemName: "bell")
                        Text(formattedOffset(model: model))
                    }
                    .font(.caption)
                }
            }
            
            Spacer()
            
            timeColumn(style: 3)
                .frame(width: 50)
        }
    }
    
    private func layoutStyle4() -> some View {
        HStack(spacing: 12) {
            
            icon
            
            VStack(alignment: .leading, spacing: 4) {
                
                Text(model.title)
                    .font(.headline)
                    .strikethrough(model.isCompleted)
                    .lineLimit(1)
                
                if model.reminderOffsetMinutes != nil {
                    HStack {
                        Image(systemName: "bell")
                        Text(formattedOffset(model: model))
                    }
                    .font(.caption)
                }
            }
            Spacer()
            VStack{
                flags(vertical: false)
                timeColumn(style: 4)
                    .frame(width: 50)
            }
        }
    }
    
    private func layoutStyle5() -> some View {
        HStack(spacing: 16) {
            
            icon
            
            VStack(alignment: .leading) {
                
                Text(model.title)
                    .font(.headline)
                    .strikethrough(model.isCompleted)
                
                if let deadline = model.deadLine {
                    Text(deadline, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                }
            }
            
            Spacer()
            
            flags(vertical: true)
        }
    }
    
    private func layoutStyle6() -> some View {
        HStack(spacing: 14) {
            
            timeColumn(style: 6)
                .frame(width: 50)
            
            VStack(alignment: .leading) {
                
                if let d = model.deadLine {
                    Text(d, format: .dateTime.weekday(.wide))
                        .font(.caption)
                        .foregroundStyle(model.statusColor)
                }
                
                Text(model.title)
                    .font(.headline)
                    .strikethrough(model.isCompleted)
            }
            
            Spacer()
            
            flags(vertical: true)
        }
    }
    
    private func layoutStyle7() -> some View {
        HStack(spacing: 14) {
            
            timeColumn(style: 7)
                .frame(width: 50)
            
            VStack(alignment: .leading) {
                
                if let d = model.deadLine {
                    Text(d, format: .dateTime.hour().minute())
                }
                
                Text(model.title)
                    .strikethrough(model.isCompleted)
            }
            
            Spacer()
            
            flags(vertical: true)
        }
    }
    
    private func layoutStyle8() -> some View {
        HStack(spacing: 14) {
            
            timeColumn(style: 8)
                .frame(width: 50)
            
            VStack(alignment: .leading) {
                
                if let d = model.deadLine {
                    Text(d, format: .dateTime.weekday(.wide))
                }
                
                Text(model.title)
                    .font(.headline)
                    .strikethrough(model.isCompleted)
            }
            
            Spacer()
            
            flags(vertical: true)
        }
    }
    
    private func layoutToday() -> some View {
        
        let notExp = (model.deadLine ?? .now) > Date()
        let isCritical = model.prioritySystemImage  == "flame"
        

        return HStack(spacing: 12) {
            
            VStack {
                if let d = model.deadLine {
                    Text(d, format: .dateTime.day())
                        .font(.title2.bold())
                    
                    Text(d, format: .dateTime.month(.abbreviated))
                        .font(.caption.bold())
                        .textCase(.uppercase)
                }
            }
            .frame(width: 50, height: 77)
            .foregroundStyle(isCritical ? .white : model.statusColor)
            
            VStack(alignment: .leading, spacing: 4) {
                
                Text(notExp ? "⏳ Today ⏳" : "⚠️ Expired ⚠️")
                    .bold()
                    .foregroundStyle(isCritical ? .white : (notExp ? .orange : .red))
                
                Text(model.title)
                    .font(.headline)
                    .bold()
                    .foregroundStyle(isCritical ? .white : .primary)
                
                if let deadline = model.deadLine {
                    HStack {
                        Image(systemName: "clock")
                        Text(deadline, format: .dateTime.hour().minute())
                    }
                    .foregroundStyle(isCritical ? .white.opacity(0.9) : model.statusColor)
                }
            }
            
            Spacer()
            
            flags(vertical: true)
                .foregroundStyle(isCritical ? .white.opacity(0.8) : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (highlightCriticalOverdue && isCritical)
            ? Color.red
            : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, -8)
    }
    
    private func layoutStyle9() -> some View {
        
        HStack(spacing: 14) {
            
            // 📅 COLONNA DATA (sinistra)
            if let d = model.deadLine {
                VStack(spacing: 0) {
                    
                    Text(d, format: .dateTime.day())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    
                    Text(d, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 11, weight: .medium))
                        .textCase(.uppercase)
                }
                .frame(width: 44)
                .foregroundStyle(model.statusColor)
            }
            
            // 📌 CONTENUTO
            VStack(alignment: .leading, spacing: 6) {
                
                // 🏷️ TAG ICON + TITLE + BADGE
                HStack(alignment: .top, spacing: 8) {
                    
                    // 🔷 ICONA TAG (stessa dimensione del titolo)
                    Image(systemName: model.mainIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(
                            iconStyle == .polychrome ? .palette : .monochrome
                        )
                        .foregroundStyle(
                            iconStyle == .polychrome
                            ? AnyShapeStyle(.primary)
                            : AnyShapeStyle(.primary),
                            
                            iconStyle == .polychrome
                            ? AnyShapeStyle(model.statusColor)
                            : AnyShapeStyle(.primary)
                        )
                        .opacity(0.9)
                        .dueIconEffect(
                            deadline: model.deadLine,
                            effect: selectedEffect
                        )
                    Text(model.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.isCompleted ? .secondary : .primary)
                        .strikethrough(model.isCompleted)
                        .lineLimit(2)
                        .tracking(-0.2)
                    
                    Spacer()
                    
                    // 🔵 BADGE giorni (top right)
                    if showBadge, let badge = model.badgeText {
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(model.statusColor)
                            )
                    }
                }
                
                // 🪶 META LINE (orario + remind + flags)
                HStack(spacing: 10) {
                    
                    if let deadline = model.deadLine {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(deadline, format: .dateTime.hour().minute())
                        }
                        .foregroundStyle(model.statusColor)
                    }
                    
                    if model.reminderOffsetMinutes != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "bell")
                                .symbolRenderingMode(.hierarchical)
                            Text(formattedOffset(model: model))
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    flags(vertical: false)
                }
                .font(.system(size: 12, weight: .medium))
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}
