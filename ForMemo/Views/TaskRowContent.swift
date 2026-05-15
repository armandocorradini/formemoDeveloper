

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
}

// MARK: - MAIN ROW

struct TaskRowContent: View, TaskRowBaseLogic {
    
    let model: TaskRowDisplayModel
    let iconStyle: TaskIconStyle
    
    let showBadge: Bool
    let showAttachments: Bool
    let showLocation: Bool
    let showPriority: Bool
    let showBadgeOnlyWithPriority: Bool
    
    let rowStyle: TaskRowStyle
    let showDateColumn: Bool
    
    @AppStorage("dueIconEffect") private var selectedEffectRaw: String = DueIconEffect.none.rawValue

    let highlightCriticalOverdue: Bool
    let showTodayExpiredLabel: Bool
    
    private var selectedEffect: DueIconEffect {
        DueIconEffect(rawValue: selectedEffectRaw) ?? .none
    }

    private var isToday: Bool {
        guard let d = model.deadLine else { return false }
        let now = Date()
        return Calendar.current.isDateInToday(d) && d >= now
    }

    private var isOverdue: Bool {
        guard let d = model.deadLine else { return false }
        return d < Date()
    }

    private var recurringFutureYearText: String? {
        guard model.recurrenceRule != nil,
              let deadline = model.deadLine
        else { return nil }

        let currentYear = Calendar.current.component(.year, from: Date())
        let deadlineYear = Calendar.current.component(.year, from: deadline)

        guard deadlineYear > currentYear else { return nil }

        return String(deadlineYear)
    }

    @ViewBuilder
    private func todayExpiredLabel() -> some View {
        if showTodayExpiredLabel {
            if isToday {
                Text("Today")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if isOverdue {
                Text("Overdue")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
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

    enum BadgeVisualStyle {
        case filled
        case soft
        case outlined
    }

    @ViewBuilder
    private func badgeView(text: String, color: Color, style: BadgeVisualStyle) -> some View {
        let isCircle = text.count <= 1

        switch style {
        case .filled:
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: isCircle ? 18 : nil, height: 18)
                .padding(.horizontal, isCircle ? 0 : 6)
                .background(
                    Group {
                        if isCircle {
                            Circle().fill(color)
                        } else {
                            Capsule().fill(color)
                        }
                    }
                )

        case .soft:
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: isCircle ? 18 : nil, height: 18)
                .padding(.horizontal, isCircle ? 0 : 6)
                .background(
                    Group {
                        if isCircle {
                            Circle().fill(color.opacity(0.2))
                        } else {
                            Capsule().fill(color.opacity(0.2))
                        }
                    }
                )

        case .outlined:
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: isCircle ? 18 : nil, height: 18)
                .padding(.horizontal, isCircle ? 0 : 6)
                .background(
                    Group {
                        if isCircle {
                            Circle().stroke(color, lineWidth: 1)
                        } else {
                            Capsule().stroke(color, lineWidth: 1)
                        }
                    }
                )
        }
    }
    
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
//        case .style10: layoutStyle10()
        }
    }
//    private func layoutStyle10() -> some View {
//        HStack(spacing: 14) {
//
//            // 📅 COLONNA DATA (sinistra)
//            if showDateColumn {
//
//                Group {
//
//                    if let d = model.deadLine {
//
//                        VStack(spacing: 0) {
//
//                            Text(d, format: .dateTime.weekday(.abbreviated))
//                                .font(.system(size: 10, weight: .semibold))
//                                .textCase(.uppercase)
//
//                            Text(d, format: .dateTime.day())
//                                .font(.system(size: 22, weight: .bold, design: .rounded))
//                                .foregroundStyle(model.statusColor)
//
//                            Text(d, format: .dateTime.month(.abbreviated))
//                                .font(.system(size: 11, weight: .medium))
//                                .textCase(.uppercase)
//                        }
//
//                    } else {
//
//                        Image(systemName: "clock.badge.questionmark")
//                            .font(.system(size: 24, weight: .regular))
//                            .foregroundStyle(.primary)
//                            .frame(width: 52, height: 44, alignment: .leading)
//                    }
//                }
//                .frame(width: 52, alignment: .leading)
//                .pulseEffect(active: isUrgent(model: model))
//            }
//            // ICONA (sinistra)
//            icon
//                .scaleEffect(0.9)
//                .frame(minWidth: 40)
//                .offset(x: -4)
//
//            // CONTENUTO (titolo + meta)
//            VStack(alignment: .leading, spacing: 4) {
//
//                // TITOLO
//                todayExpiredLabel()
//                HStack(spacing: 6) {
//                    Text(model.title)
//                        .font(.headline)
//                        .foregroundStyle(model.isCompleted ? .secondary : .primary)
//                        .strikethrough(model.isCompleted)
//                        .lineLimit(1)
//
//                    if model.recurrenceRule != nil {
//                        HStack(spacing: 3) {
//                            Image(systemName: "arrow.triangle.2.circlepath")
//                                .font(.caption)
//                                .foregroundStyle(.blue)
//                            if let recurringFutureYearText {
//                                Text(recurringFutureYearText)
//                                    .font(.system(size: 9, weight: .semibold))
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                    }
//                }
//
//                // META (remind + flags)
//                HStack(spacing: 8) {
//
//                    if model.reminderOffsetMinutes != nil {
//                        HStack(spacing: 4) {
//                            Image(systemName: "bell")
//                            Text(formattedOffset(model: model))
//                        }
//                    }
//
//                    Spacer()
//
//                    flags(vertical: false)
//                }
//                .font(.caption2)
//                .foregroundStyle(.primary).opacity(0.7)
//            }
//
//            Spacer()
//        }
//        .padding(.vertical, 6)
//        .padding(.leading, 8)
//    }
}

// MARK: - BASE COMPONENTS

extension TaskRowContent {
    
    var icon: some View {
        TaskIconContent(
            model: model,
            iconStyle: iconStyle,
            showAttachments: false,
            showLocation: false
        )
    }
    
    @ViewBuilder
    var flagsContent: some View {
        if showPriority, let image = model.prioritySystemImage {
            Image(systemName: image)
                .foregroundStyle(image == "flame" ? .red : .primary)
        }
        if showAttachments && model.hasValidAttachments {
            Image(systemName: "paperclip")
        }
        if showLocation && model.hasLocation {
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
        .foregroundStyle(.primary).opacity(0.7)
    }
    
    func timeColumn(style: Int) -> some View {
        Group {
            if let d = model.deadLine {
                VStack(spacing: style == 1 ? 1 : 0) {

                    if style == 1 || style == 7 || style == 9 {
                        Text(d, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .opacity(showDateColumn ? 1 : 0)
                    }

                    if style == 6 {
                        Text(d, format: .dateTime.hour().minute())
                            .font(.system(size: 11, weight: .medium))
                    }

                    Text(d, format: .dateTime.day())
                        .font(
                            style == 1
                            ? .headline
                            : .system(size: 22, weight: .bold, design: .rounded)
                        )
                        .foregroundStyle(model.statusColor)
                        .opacity(showDateColumn ? 1 : 0)

                    Text(d, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .opacity(showDateColumn ? 1 : 0)

                    if style != 0 && style != 6 && style != 1 && style != 7 {
                        Text(d, format: .dateTime.hour().minute())
                            .font(
                                .system(
                                    size: 12,
                                    weight: .medium,
                                    design: .monospaced
                                )
                            )
                            .opacity(0.8)
                    }
                }
                .frame(width: 52, height: 44, alignment: .leading)
                .shadow(
                    color: .primary.opacity(0.6),
                    radius: 0.5,
                    x: 0.5,
                    y: 0.5
                )
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
    
    private func layoutStyle9() -> some View {
        HStack(spacing: 2) {

            timeColumn(style: 9)
                .frame(width: 52, alignment: .leading)

            icon
                .scaleEffect(0.8)
                .frame(minWidth: 40)
                .offset(x: -4)

            VStack(alignment: .leading, spacing: 6) {
                todayExpiredLabel()
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .foregroundStyle(model.isCompleted ? .secondary : .primary)
                        .strikethrough(model.isCompleted)
                        .lineLimit(1)

                    if model.recurrenceRule != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                HStack(spacing: 6) {

                    if let deadline = model.deadLine {
                        Image(systemName: "clock")
                            .foregroundStyle(.primary)
                        Text(deadline, format: .dateTime.hour().minute())
                            .foregroundStyle(.primary)
                    }

                    if model.reminderOffsetMinutes != nil {
                        Image(systemName: "bell")
                        Text(formattedOffset(model: model))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.primary).opacity(0.7)
            }

            Spacer()

            flags(vertical: true)
        }
    }
    
    private func layoutStyle1() -> some View {
        HStack(spacing: 2) {
            
            timeColumn(style: 1)
            
            VStack(alignment: .leading, spacing: 1) {
                todayExpiredLabel()

                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)
                    
                    if model.recurrenceRule != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let recurringFutureYearText {
                                Text(recurringFutureYearText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                .foregroundStyle(.primary).opacity(0.7)
            }
            icon.scaleEffect(0.72)
        }
        .padding(1)
        .padding(.leading, 8)
    }
    
    private func layoutStyle2() -> some View {
        HStack(spacing: 2) {

            timeColumn(style: 2)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                todayExpiredLabel()

                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)

                    if model.recurrenceRule != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let recurringFutureYearText {
                                Text(recurringFutureYearText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                .foregroundStyle(.primary).opacity(0.7)
            }
            icon.scaleEffect(0.85)
        }
    }
    
    private func layoutStyle3() -> some View {
        HStack(spacing: 14) {

            VStack(spacing: 4) {
                icon.scaleEffect(0.85)
                flags(vertical: false)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 6) {
                todayExpiredLabel()
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)
                        .lineLimit(1)

                    if model.recurrenceRule != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let recurringFutureYearText {
                                Text(recurringFutureYearText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

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
                .frame(width: 52, alignment: .leading)
        }
        .padding(.leading, 8)
    }
    
    private func layoutStyle4() -> some View {
        HStack(spacing: 14) {
            
            icon
            
            VStack(alignment: .leading, spacing: 6) {
                todayExpiredLabel()
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)
                    
                    if model.recurrenceRule != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let recurringFutureYearText {
                                Text(recurringFutureYearText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
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
            VStack {
                flags(vertical: false)
                timeColumn(style: 4)
                    .frame(width: 52, alignment: .leading)
            }
        }
        .padding(.leading, 8)
    }
    
    private func layoutStyle5() -> some View {
        HStack(spacing: 2) {

            timeColumn(style: 5)
                .frame(width: 52, alignment: .leading)
            
            icon
            
            VStack(alignment: .leading) {
                todayExpiredLabel()
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)
                    
                    if model.recurrenceRule != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let recurringFutureYearText {
                                Text(recurringFutureYearText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                if let deadline = model.deadLine {
                    Text(deadline, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                }
            }
            
            Spacer()
            
            flags(vertical: true)
        }
        .padding(.leading, 8)
    }
    
    private func layoutStyle6() -> some View {
        HStack(spacing: 2) {

            timeColumn(style: 6)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading) {

                todayExpiredLabel()

                if let d = model.deadLine {
                    Text(d, format: .dateTime.weekday(.wide))
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)

                    if model.recurrenceRule != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            flags(vertical: true)
        }
    }
    
    private func layoutStyle7() -> some View {
        HStack(spacing: 2) {

            timeColumn(style: 7)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading) {

                todayExpiredLabel()

                if let d = model.deadLine {
                    Text(d, format: .dateTime.hour().minute())
                }

                HStack(spacing: 6) {
                    Text(model.title)
                        .strikethrough(model.isCompleted)

                    if model.recurrenceRule != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let recurringFutureYearText {
                                Text(recurringFutureYearText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer()

            flags(vertical: true)
        }
    }
    
    private func layoutStyle8() -> some View {
        HStack(spacing: 2) {

            timeColumn(style: 8)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading) {

                todayExpiredLabel()

                if let d = model.deadLine {
                    Text(d, format: .dateTime.weekday(.wide))
                }

                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.headline)
                        .strikethrough(model.isCompleted)

                    if model.recurrenceRule != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let recurringFutureYearText {
                                Text(recurringFutureYearText)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer()

            flags(vertical: true)
        }
    }
    
    
    private func layoutStyle0() -> some View {
        HStack(spacing: 2) {

            // 📅 COLONNA DATA (sinistra)
            Group {
                if let d = model.deadLine {
                    VStack(spacing: 0) {
                        Text(d, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .opacity(showDateColumn ? 1 : 0)

                        Text(d, format: .dateTime.day())
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(model.statusColor)
                            .opacity(showDateColumn ? 1 : 0)

                        Text(d, format: .dateTime.month(.abbreviated))
                            .font(.system(size: 11, weight: .medium))
                            .textCase(.uppercase)
                            .opacity(showDateColumn ? 1 : 0)
                    }
                } else {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.secondary)
                        .opacity(showDateColumn ? 1 : 0)
                }
            }
            .frame(width: 38, height: 44, alignment: .leading)

            // 📌 CONTENUTO
            VStack(alignment: .leading, spacing: 6) {
                todayExpiredLabel()
                // 🏷️ TAG ICON + TITLE + BADGE
                HStack(alignment: .center, spacing: 8) {

                    // 🔷 ICONA TAG (stessa dimensione del titolo)
                    Image(systemName: model.mainIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(
                            iconStyle == .polychrome && model.mainTag != nil ? .palette : .monochrome
                        )
                        .foregroundStyle(
                            iconStyle == .polychrome
                            ? (model.mainTag?.color ?? model.statusColor)
                            : .primary,
                            .primary
                        )
                        .opacity(0.9)
                        .dueIconEffect(
                            deadline: model.deadLine,
                            effect: selectedEffect
                        )
                    HStack(spacing: 6) {
                        Text(model.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(model.isCompleted ? .secondary : .primary)
                            .strikethrough(model.isCompleted)
                            .lineLimit(2)
                            .tracking(-0.2)

                        if model.recurrenceRule != nil {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                if let recurringFutureYearText {
                                    Text(recurringFutureYearText)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()

                    // 🔵 BADGE giorni – verticalmente allineato
                    if model.shouldShowBadge,
                       let badge = model.badgeText,
                       let deadline = model.deadLine {

                        VStack {
                            Spacer(minLength: 0)

                            TaskBadgeView(
                                deadline: deadline,
                                badgeText: badge,
                                statusColor: model.statusColor
                            )

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 32)
                    }
                }

                // 🪶 META LINE (orario + remind + flags)
                HStack(spacing: 10) {

                    if let deadline = model.deadLine {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(deadline, format: .dateTime.hour().minute())
                        }
                        .foregroundStyle(.primary)
                    }

                    if model.reminderOffsetMinutes != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "bell")
                                .symbolRenderingMode(.hierarchical)
                            Text(formattedOffset(model: model))
                        }
                        .foregroundStyle(.primary).opacity(0.7)
                    }
                    Spacer()
                    flags(vertical: false)
                }
                .font(.system(size: 12, weight: .medium))
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(
            .bottom,
            showTodayExpiredLabel && (isToday || isOverdue)
            ? 14
            : 10
        )
    }
}
