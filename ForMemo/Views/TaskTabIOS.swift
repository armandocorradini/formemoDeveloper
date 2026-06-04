import SwiftUI
import SwiftData

struct TaskTabView: View {
    
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    @State private var selectedTab: Int = 0
    @State private var showSnoozeAlert = false
    @State private var showMorePopover = false
    
    @State private var StartPath = NavigationPath()
    @State private var listPath = NavigationPath()
    @State private var weeklyPath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var mapPath = NavigationPath()
    @State private var walletPath = NavigationPath()
    @State private var TripsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    
    @AppStorage("TaskWeekDays")
    private var taskWeekDays: Int = 3
    
    @AppStorage("startupTab")
    private var startupTab: Int = 1
    
    var body: some View {
        rootLayout
            .onAppear {
                
                selectedTab = 0
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(
                        name: Notification.Name("StartStartIconRotationFast"),
                        object: nil
                    )
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                    
                    guard selectedTab == 0 else {
                        return
                    }
                    
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = startupTab
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .snoozeRejectedDueToDeadline)) { _ in
                showSnoozeAlert = true
            }
            .alert(
                "Snooze not scheduled",
                isPresented: $showSnoozeAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Snooze exceeds the deadline. No snooze notification will be scheduled. The deadline notification will still occur.")
            }
    }
    
    @ViewBuilder
    private var rootLayout: some View {
        
        if sizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }
    
    // MARK: - iPhone
    
    private var iPhoneLayout: some View {
        
        ZStack {
            currentTabView
        }
        .safeAreaInset(edge: .bottom) {
            
            HStack(spacing: 10) {
                
                tabItem(
                    "checklist",
                    String(localized: "list_tab"),
                    1
                )
                
                tabItem(
                    "calendar.day.timeline.right",
                    taskWeekDays == 1
                    ? String(localized: "today_tab")
                    : String(localized: "\(taskWeekDays) days_tab"),
                    4
                )
                
                tabItem(
                    "calendar",
                    String(localized: "calendar_tab"),
                    3
                )
                
                tabItem(
                    "map",
                    String(localized: "map_tab"),
                    5
                )
                
                Button {
                    showMorePopover.toggle()
                } label: {
                    
                    VStack(spacing: 4) {
                        
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 21, weight: .regular))
                            .frame(height: 22)
                        
                        Text("More")
                            .font(.system(size: 9, weight: .medium))
                        
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 16, height: 3)
                            .opacity([0,2,6,7].contains(selectedTab) ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .foregroundStyle(
                        [0,2,6,7].contains(selectedTab)
                        ? Color.accentColor
                        : Color.secondary
                    )
                    // Bubble background removed
                }
                .popover(isPresented: $showMorePopover, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {

                        Button {
                            selectedTab = 0
                            showMorePopover = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                                    .frame(width: 22)
                                Text(String(localized: "Start_tab"))
                            }
                            .foregroundStyle(selectedTab == 0 ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        Button {
                            selectedTab = 6
                            showMorePopover = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedTab == 6 ? "wallet.bifold.fill" : "wallet.bifold")
                                    .frame(width: 22)
                                Text(String(localized: "wallet_tab"))
                            }
                            .foregroundStyle(selectedTab == 6 ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            selectedTab = 7
                            showMorePopover = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedTab == 7 ? "suitcase.rolling.fill" : "suitcase.rolling")
                                    .frame(width: 22)
                                Text("Trips")
                            }
                            .foregroundStyle(selectedTab == 7 ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        Button {
                            selectedTab = 2
                            showMorePopover = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedTab == 2 ? "gearshape.fill" : "gear")
                                    .frame(width: 22)
                                Text(String(localized: "settings_tab"))
                            }
                            .foregroundStyle(selectedTab == 2 ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .frame(width: 240)
                    .presentationCompactAdaptation(.popover)
                }
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.white.opacity(0.003))
                    }
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .offset(y: 10)
        }
        .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder
    private var currentTabView: some View {
        
        switch selectedTab {
            
        case 0:
            NavigationStack(path: $StartPath) {
                StartView()
            }
            
        case 1:
            NavigationStack(path: $listPath) {
                TaskListView()
            }
            
        case 4:
            NavigationStack(path: $weeklyPath) {
                WeeklyTasksView()
            }
            
        case 3:
            NavigationStack(path: $calendarPath) {
                TaskCalendarView()
            }
            
        case 5:
            NavigationStack(path: $mapPath) {
                TaskMapView(mapPath: $mapPath)
            }
            
        case 6:
            NavigationStack(path: $walletPath) {
                WalletView()
            }
            
        case 7:
            NavigationStack(path: $TripsPath) {
                TravelKitListView()
            }
            
        case 2:
            NavigationStack(path: $settingsPath) {
                SettingsView()
            }
            
        default:
            NavigationStack(path: $StartPath) {
                StartView()
            }
        }
    }
    
    // MARK: - iPad
    
    private var iPadLayout: some View {
        
        NavigationSplitView {
            
            List {
                sidebarRow(String(localized: "list_tab"), "checklist", 1)
                
                sidebarRow(
                    taskWeekDays == 1
                    ? String(localized: "today_tab")
                    : String(localized: "days_tab \(taskWeekDays)"),
                    "calendar.day.timeline.right",
                    4
                )
                
                sidebarRow(String(localized: "calendar_tab"), "calendar", 3)
                sidebarRow(String(localized: "map_tab"), "map", 5)
                sidebarRow(String(localized: "Start_tab"), "house", 0)
                sidebarRow(String(localized: "wallet_tab"), "wallet.bifold", 6)
                sidebarRow("Trips", "suitcase.rolling", 7)
                sidebarRow(String(localized: "settings_tab"), "gear", 2)
            }
            .listStyle(.sidebar)
            .navigationTitle("Tasks")
            
        } detail: {
            currentTabView
        }
    }
    
    private func sidebarRow(
        _ title: String,
        _ image: String,
        _ tag: Int
    ) -> some View {
        
        Button {
            selectedTab = tag
        } label: {
            Label(title, systemImage: image)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .background(
                    selectedTab == tag
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private func tabItem(
        _ icon: String,
        _ title: String,
        _ tag: Int
    ) -> some View {
        
        Button {
            
//            UIImpactFeedbackGenerator(style: .light)
//                .impactOccurred()
            
            if selectedTab != tag {
                resetTab(selectedTab)
//                withAnimation(.easeInOut(duration: 0.12)) {
                    selectedTab = tag
//                }
            } else {
                resetTab(tag)
            }
            
        } label: {
            
            VStack(spacing: 2) {
                
                Image(systemName: icon)
                    .font(.system(
                        size: selectedTab == tag ? 22 : 20,
                        weight: selectedTab == tag ? .semibold : .regular
                    ))
                    .scaleEffect(selectedTab == tag ? 1.10 : 1)
                    .frame(height: 22)
                
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 16, height: 3)
                    .opacity(selectedTab == tag ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .foregroundStyle(
                selectedTab == tag
                ? Color.accentColor
                : Color.secondary
            )
            // Bubble background removed
        }
        .buttonStyle(.plain)
    }
    
    private func resetTab(_ tab: Int) {
        
        switch tab {
            
        case 0:
            if !StartPath.isEmpty {
                StartPath = NavigationPath()
            }
            
        case 1:
            if !listPath.isEmpty {
                listPath = NavigationPath()
            }
            
        case 4:
            if !weeklyPath.isEmpty {
                weeklyPath = NavigationPath()
            }
            
        case 3:
            if !calendarPath.isEmpty {
                calendarPath = NavigationPath()
            }
            
        case 5:
            if !mapPath.isEmpty {
                mapPath = NavigationPath()
            }
            
        case 6:
            if !walletPath.isEmpty {
                walletPath = NavigationPath()
            }
            
        case 7:
            if !TripsPath.isEmpty {
                TripsPath = NavigationPath()
            }
            
        case 2:
            if !settingsPath.isEmpty {
                settingsPath = NavigationPath()
            }
            
        default:
            break
        }
    }
}
