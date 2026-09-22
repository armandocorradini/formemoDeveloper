import SwiftUI
import UniformTypeIdentifiers

struct TabBarCustomizationView: View {

    @Environment(AppSettings.self) private var settings

    @State private var tabs: [AppTab] = []
    @State private var selectedPreviewTab: AppTab = .dashboard
    @State private var draggedTab: AppTab?
    @State private var lastDropTarget: AppTab?

    var body: some View {
        ZStack {
            AppGlassBackground()

            ScrollView {
                VStack(spacing: 0) {

                    // MARK: - Preview

                    VStack(spacing: 0) {
                        morePopupPreview
                        tabBarPreview
                    }
                    .padding(.horizontal, 16)

                    // MARK: - Instructions

                    Text("Drag the items to change their order.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                        .padding(.horizontal, 24)

                    // MARK: - Icon Color

                    iconColorSection

                    // MARK: - Hidden Tabs

                    hiddenTabsSection
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Customize Tab Bar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Reset") {
                    resetCustomization()
                }
            }
        }
        .onAppear {
            tabs = settings.orderedTabs

            if let first = tabs.first(where: {
                $0.isVisible(using: settings)
            }) {
                selectedPreviewTab = first
            }
        }
        .onChange(of: settings.tabOrder) { _, _ in
            guard draggedTab == nil else {
                return
            }

            let newTabs = settings.orderedTabs

            if newTabs.map(\.rawValue) != tabs.map(\.rawValue) {
                tabs = newTabs
            }
        }
        .onChange(of: settings.showVault) { _, _ in
            tabs = settings.orderedTabs
        }
        .onChange(of: settings.showWeatherForecast) { _, _ in
            tabs = settings.orderedTabs
        }
    }



    // MARK: - Popup Preview

    private var morePopupPreview: some View {
        let visibleTabs = tabs.filter { $0.isVisible(using: settings) }
        let moreTabs = Array(visibleTabs.dropFirst(4))

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(moreTabs) { tab in
                previewMoreItem(tab)
            }
        }
        .padding(.vertical, 13)
        .padding(.leading, 20)
        .padding(.trailing, 36)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(
                        cornerRadius: 30,
                        style: .continuous
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    .white.opacity(0.08),
                    lineWidth: 0.6
                )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 2)
        .padding(.bottom, 6)
    }
 
    // MARK: - Popup Item
    private func previewMoreItem(_ tab: AppTab) -> some View {
        let isSettings = tab == .settings
        let iconColor = Color(hex: settings.tabBarCustomizationIconColorHex) ?? .blue

        return HStack(spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 21, weight: .regular))
                    .frame(width: 22)

                Capsule()
                    .fill(iconColor)
                    .frame(width: 16, height: 3)
                    .opacity(tab == .settings ? 1 : 0)
            }

            Text(tab.title(using: settings))
                .font(.system(size: 17, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .foregroundStyle(
            isSettings ? iconColor : Color.primary
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) {
                selectedPreviewTab = tab
            }
        }
        .onDrag {
            draggedTab = tab
            lastDropTarget = nil
            return NSItemProvider(
                object: String(tab.rawValue) as NSString
            )
        }
        .onDrop(
            of: [.text],
            delegate: TabPreviewDropDelegate(
                target: tab,
                draggedTab: $draggedTab,
                lastDropTarget: $lastDropTarget,
                tabs: $tabs,
                settings: settings
            )
        )
    }
    // MARK: - Tab Bar Preview

    private var tabBarPreview: some View {

        let visibleTabs = tabs.filter {
            $0.isVisible(using: settings)
        }

        let primaryTabs = Array(visibleTabs.prefix(4))
        let hasMore = visibleTabs.count > 4

        return HStack(spacing: 10) {

            ForEach(primaryTabs) { tab in
                previewTabItem(tab)
            }

            if hasMore {
                previewMoreButton
            }
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .background {

            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
            .fill(.clear)
            .glassEffect()
            .overlay {

                RoundedRectangle(
                    cornerRadius: 30,
                    style: .continuous
                )
                .fill(
                    Color.accentColor.opacity(0.06)
                )
            }
            .shadow(
                color: .black.opacity(0.05),
                radius: 8,
                y: 3
            )
        }
        .overlay {

            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
            .strokeBorder(
                .white.opacity(0.08),
                lineWidth: 0.6
            )
        }
    }

    // MARK: - Tab Item

    private func previewTabItem(_ tab: AppTab) -> some View {

//        let selected = selectedPreviewTab == tab
        let iconColor =
            Color(hex: settings.tabBarCustomizationIconColorHex) ?? .blue

        return Button {

            withAnimation(.snappy) {
                selectedPreviewTab = tab
            }

        } label: {

            VStack(spacing: 2) {

                Image(systemName: tab.icon)
                    .font(
                        .system(
                            size: 21,
                            weight: .medium
                        )
                    )
                    .frame(height: 22)

                Text(tab.title(using: settings))
                    .font(
                        .system(
                            size: 9,
                            weight: .medium
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Capsule()
                    .fill(iconColor)
                    .frame(width: 16, height: 3)
                    .opacity(tab == .settings ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .contentShape(Rectangle())
            .foregroundStyle(
                tab == .settings
                    ? iconColor
                    : Color.primary
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            draggedTab = tab
            lastDropTarget = nil

            return NSItemProvider(
                object: String(tab.rawValue) as NSString
            )
        }
        .onDrop(
            of: [.text],
            delegate: TabPreviewDropDelegate(
                target: tab,
                draggedTab: $draggedTab,
                lastDropTarget: $lastDropTarget,
                tabs: $tabs,
                settings: settings
            )
        )
    }

    // MARK: - More Button

    private var previewMoreButton: some View {

//        let visibleTabs = tabs.filter {
//            $0.isVisible(using: settings)
//        }

//        let moreTabs = Array(visibleTabs.dropFirst(4))


        let iconColor =
            Color(hex: settings.tabBarCustomizationIconColorHex) ?? .blue

        return VStack(spacing: 2) {

            Image(systemName: "square.grid.2x2")
                .font(
                    .system(
                        size: 21,
                        weight: .regular
                    )
                )
                .frame(height: 22)

            Text("More")
                .font(
                    .system(
                        size: 9,
                        weight: .medium
                    )
                )
                .lineLimit(1)

            Capsule()
                .fill(iconColor)
                .frame(width: 16, height: 3)
                
        }
        .frame(maxWidth: .infinity)
        .frame(height: 49)
        .foregroundStyle(iconColor)
        .contentShape(Rectangle())
    }

    // MARK: - Icon Color

    private var iconColorSection: some View {

        HStack {
            Text("Icon color")
                .font(.callout)
            Spacer()

            ColorPicker(
                "",
                selection: Binding(
                    get: {
                        Color(
                            hex:
                                settings
                                    .tabBarCustomizationIconColorHex
                        ) ?? .blue
                    },
                    set: { newColor in
                        settings
                            .tabBarCustomizationIconColorHex =
                            newColor.toHex()
                            ?? settings
                                .tabBarCustomizationIconColorHex
                    }
                )
            )
            .labelsHidden()
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
    }

    // MARK: - Hidden Tabs

    @ViewBuilder
    private var hiddenTabsSection: some View {

        let hiddenTabs = tabs.filter {
            !$0.isVisible(using: settings)
        }

        if !hiddenTabs.isEmpty {

            VStack(alignment: .leading, spacing: 12) {

                Text("Hidden")
                    .font(.headline)

                VStack(spacing: 0) {

                    ForEach(hiddenTabs) { tab in

                        HStack(spacing: 12) {

                            Image(systemName: tab.icon)
                                .frame(width: 24)

                            Text(tab.title(using: settings))

                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
        }
    }

    // MARK: - Reset

    private func resetCustomization() {

        withAnimation(.snappy) {

            tabs = AppTab.defaultOrder

            settings.tabOrder =
                AppTab.defaultOrder.map(\.rawValue)

            settings.tabBarCustomizationIconColorHex =
                Color.blue.toHex() ?? ""

            if let first = tabs.first(
                where: { $0.isVisible(using: settings) }
            ) {
                selectedPreviewTab = first
            }
        }
    }
}


private struct MorePopoverShape: Shape {

    func path(in rect: CGRect) -> Path {

        let cornerRadius: CGFloat = 30

        // La freccia del popover reale è vicina al bordo destro,
        // perché è ancorata al pulsante "More".
        let arrowCenterX = rect.width - 120

        let arrowWidth: CGFloat = 34
        let arrowHeight: CGFloat = 18

        let bodyBottom = rect.height - arrowHeight

        var path = Path()

        // MARK: Top-left

        path.move(
            to: CGPoint(
                x: cornerRadius,
                y: 0
            )
        )

        // Top edge

        path.addLine(
            to: CGPoint(
                x: rect.width - cornerRadius,
                y: 0
            )
        )

        // Top-right

        path.addQuadCurve(
            to: CGPoint(
                x: rect.width,
                y: cornerRadius
            ),
            control: CGPoint(
                x: rect.width,
                y: 0
            )
        )

        // Right edge

        path.addLine(
            to: CGPoint(
                x: rect.width,
                y: bodyBottom - cornerRadius
            )
        )

        // Bottom-right rounded corner

        path.addQuadCurve(
            to: CGPoint(
                x: rect.width - cornerRadius,
                y: bodyBottom
            ),
            control: CGPoint(
                x: rect.width,
                y: bodyBottom
            )
        )

        // Bottom edge → right side of arrow

        path.addLine(
            to: CGPoint(
                x: arrowCenterX + arrowWidth / 2,
                y: bodyBottom
            )
        )

        // Arrow right side

        path.addLine(
            to: CGPoint(
                x: arrowCenterX,
                y: rect.height
            )
        )

        // Arrow left side

        path.addLine(
            to: CGPoint(
                x: arrowCenterX - arrowWidth / 2,
                y: bodyBottom
            )
        )

        // Bottom edge → bottom-left corner

        path.addLine(
            to: CGPoint(
                x: cornerRadius,
                y: bodyBottom
            )
        )

        // Bottom-left rounded corner

        path.addQuadCurve(
            to: CGPoint(
                x: 0,
                y: bodyBottom - cornerRadius
            ),
            control: CGPoint(
                x: 0,
                y: bodyBottom
            )
        )

        // Left edge

        path.addLine(
            to: CGPoint(
                x: 0,
                y: cornerRadius
            )
        )

        // Top-left rounded corner

        path.addQuadCurve(
            to: CGPoint(
                x: cornerRadius,
                y: 0
            ),
            control: CGPoint(
                x: 0,
                y: 0
            )
        )

        path.closeSubpath()

        return path
    }
}// MARK: - Drop Delegate


private struct TabPreviewDropDelegate: DropDelegate {
    
    let target: AppTab

    @Binding var draggedTab: AppTab?
    @Binding var lastDropTarget: AppTab?

    @Binding var tabs: [AppTab]

    let settings: AppSettings

    func dropEntered(info: DropInfo) {

        guard let draggedTab else {
            return
        }

        guard draggedTab != target else {
            return
        }

        // Evita che lo stesso target provochi
        // spostamenti ripetuti durante il drag.
        guard lastDropTarget != target else {
            return
        }

        guard
            let fromIndex = tabs.firstIndex(of: draggedTab),
            let targetIndex = tabs.firstIndex(of: target)
        else {
            return
        }

        lastDropTarget = target

        withAnimation(.snappy) {

            tabs.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: fromIndex < targetIndex
                    ? targetIndex + 1
                    : targetIndex
            )

            settings.tabOrder = tabs.map(\.rawValue)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {

        draggedTab = nil
        lastDropTarget = nil

        return true
    }
}
