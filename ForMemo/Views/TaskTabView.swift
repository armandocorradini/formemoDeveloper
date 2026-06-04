//import SwiftUI
//import SwiftData
//
//struct TaskTabView: View {
//    
//    @Environment(\.horizontalSizeClass) private var sizeClass
//    @Environment(\.colorScheme) private var colorScheme
//    
//    @State private var selectedTab: Int = 0
//    @State private var showSnoozeAlert = false
//    
//    @State private var homePath = NavigationPath()
//    @State private var listPath = NavigationPath()
//    @State private var mapPath = NavigationPath()
//    @State private var weeklyPath = NavigationPath()
//    @State private var calendarPath = NavigationPath()
//    @State private var settingsPath = NavigationPath()
//    @State private var walletPath = NavigationPath()
//    
//    @AppStorage("TaskWeekDays")
//    private var taskWeekDays: Int = 3
//    
//    @AppStorage("startupTab")
//    private var startupTab: Int = 1
//    
//    
//    
//    var body: some View {
//        
//        rootLayout
//        .onAppear {
//
//            // Always start from Home.
//            selectedTab = 0
//
//            // Start Home icon animation.
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//
//                NotificationCenter.default.post(
//                    name: Notification.Name("StartHomeIconRotationFast"),
//                    object: nil
//                )
//            }
//
//            // Fast transition to preferred startup tab.
//            DispatchQueue.main.asyncAfter(deadline: .now() + 2.80) {
//
//                guard selectedTab == 0 else {
//                    return
//                }
//
//                withAnimation(.easeInOut(duration: 0.18)) {
//                    selectedTab = startupTab
//                }
//            }
//        }
//        .onReceive(NotificationCenter.default.publisher(for: .snoozeRejectedDueToDeadline)) { _ in
//            showSnoozeAlert = true
//        }
//        .alert("Snooze not scheduled",
//               isPresented: $showSnoozeAlert) {
//            Button("OK", role: .cancel) {}
//        } message: {
//            Text("Snooze exceeds the deadline. No snooze notification will be scheduled. The deadline notification will still occur.")
//        }
//    }
//    
//    @ViewBuilder
//    private var rootLayout: some View {
//
//        if sizeClass == .regular {
//            iPadLayout
//        } else {
//            iPhoneLayout
//        }
//    }
//    
//    // MARK: - iPhone Layout
//    
//    private var iPhoneLayout: some View {
//        ZStack {
//            currentTabView
//        }
//        .safeAreaInset(edge: .bottom) {
//            HStack(spacing: 10) {
//                tabItem("house", NSLocalizedString("Home", comment: ""), 0)
//                tabItem("checklist", NSLocalizedString("list_tab", comment: ""), 1)
//                tabItem("calendar.day.timeline.right",
//                        taskWeekDays == 1
//                        ? String(localized: "today_tab")
//                        : String(localized: "\(taskWeekDays) days_tab"),
//                        4)
//                tabItem("calendar", NSLocalizedString("calendar_tab", comment: ""), 3)
//                tabItem("map", NSLocalizedString("map_tab", comment: ""), 5)
//                tabItem("wallet.bifold", NSLocalizedString("wallet_tab", comment: ""), 6)
//                tabItem("gear", NSLocalizedString("settings_tab", comment: ""), 2)
//            }
//            .frame(height: 60)
//            .frame(maxWidth: .infinity)
//            .padding(.horizontal, 12)
//            .background {
//                Capsule(style: .continuous)
//                    .fill(.regularMaterial)
//                    .overlay {
//                        Capsule(style: .continuous)
//                            .fill(
//                                LinearGradient(
//                                    colors: [
//                                        Color.white.opacity(0.24),
//                                        Color.white.opacity(0.05),
//                                        Color.clear
//                                    ],
//                                    startPoint: .top,
//                                    endPoint: .bottom
//                                )
//                            )
//                    }
//                    .overlay(alignment: .top) {
//                        Capsule(style: .continuous)
//                            .stroke(
//                                LinearGradient(
//                                    colors: [
//                                        Color.white.opacity(0.40),
//                                        Color.white.opacity(0.08)
//                                    ],
//                                    startPoint: .top,
//                                    endPoint: .bottom
//                                ),
//                                lineWidth: 0.8
//                            )
//                            .blur(radius: 0.25)
//                    }
//                    .overlay(alignment: .bottom) {
//                        Capsule(style: .continuous)
//                            .fill(
//                                LinearGradient(
//                                    colors: [
//                                        Color.black.opacity(0.10),
//                                        Color.clear
//                                    ],
//                                    startPoint: .bottom,
//                                    endPoint: .top
//                                )
//                            )
//                            .blur(radius: 6)
//                            .offset(y: 8)
//                    }
//                    .overlay {
//                        Capsule(style: .continuous)
//                            .fill(
//                                LinearGradient(
//                                    colors: [
//                                        Color.white.opacity(0.10),
//                                        Color.white.opacity(0.015)
//                                    ],
//                                    startPoint: .top,
//                                    endPoint: .bottom
//                                )
//                            )
//                    }
//                    .overlay(alignment: .topLeading) {
//                        Capsule(style: .continuous)
//                            .fill(
//                                RadialGradient(
//                                    colors: [
//                                        Color.white.opacity(colorScheme == .light ? 0.22 : 0.08),
//                                        Color.clear
//                                    ],
//                                    center: .topLeading,
//                                    startRadius: 4,
//                                    endRadius: 140
//                                )
//                            )
//                    }
//            }
//            .compositingGroup()
//            .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
//            .shadow(color: .white.opacity(0.05), radius: 2, y: -1)
//            .padding(.horizontal, 16)
//            .padding(.bottom, 2)//avvicina o allontana la bar al fondo telefono
//        }
//        .ignoresSafeArea(.keyboard)
//    }
//    
//    @ViewBuilder
//    private var currentTabView: some View {
//
//        switch selectedTab {
//
//        case 0:
//            homeStack
//
//        case 1:
//            listStack
//
//        case 5:
//            mapStack
//
//        case 4:
//            weeklyStack
//
//        case 3:
//            calendarStack
//
//        case 6:
//            walletStack
//
//        case 2:
//            settingsStack
//
//        default:
//            homeStack
//        }
//    }
//
//    private var homeStack: some View {
//        NavigationStack(path: $homePath) {
//            HomeView()
//        }
//    }
//
//    private var listStack: some View {
//        NavigationStack(path: $listPath) {
//            TaskListView()
//        }
//    }
//
//    private var mapStack: some View {
//        NavigationStack(path: $mapPath) {
//            TaskMapView(mapPath: $mapPath)
//        }
//    }
//
//    private var weeklyStack: some View {
//        NavigationStack(path: $weeklyPath) {
//            WeeklyTasksView()
//        }
//    }
//
//    private var calendarStack: some View {
//        NavigationStack(path: $calendarPath) {
//            TaskCalendarView()
//        }
//    }
//
//    private var walletStack: some View {
//        NavigationStack(path: $walletPath) {
//            WalletView()
//        }
//    }
//
//    private var settingsStack: some View {
//        NavigationStack(path: $settingsPath) {
//            SettingsView()
//        }
//    }
//    
//    // MARK: - iPad Layout
//    
//    private var iPadLayout: some View {
//        
//        NavigationSplitView {
//            
//            List {
//                
//                sidebarRow(title: NSLocalizedString("home_tab", comment: ""), systemImage: "house", tag: 0)
//                sidebarRow(title: NSLocalizedString("list_tab", comment: ""), systemImage: "checklist", tag: 1)
//                sidebarRow(title:
//                            taskWeekDays == 1
//                           ? String(localized: "today_tab")
//                           : String(localized: "days_tab \(taskWeekDays)"),
//                           systemImage: "calendar.day.timeline.right", tag: 4)
//                sidebarRow(title: NSLocalizedString("calendar_tab", comment: ""), systemImage: "calendar", tag: 3)
//                sidebarRow(title: NSLocalizedString("map_tab", comment: ""), systemImage: "map", tag: 5)
//                sidebarRow(title: NSLocalizedString("wallet_tab", comment: ""), systemImage: "wallet.bifold", tag: 6)
//                sidebarRow(title: NSLocalizedString("settings_tab", comment: ""), systemImage: "gear", tag: 2)
//            }
//            .listStyle(.sidebar)
//            .navigationTitle("Tasks")
//            
//            
//        } detail: {
//            
//            switch selectedTab {
//            case 0:
//                NavigationStack { HomeView() }
//            case 1:
//                NavigationStack { TaskListView() }
//            case 5:
//                NavigationStack(path: $mapPath) { TaskMapView(mapPath: $mapPath) }
//            case 4:
//                NavigationStack { WeeklyTasksView() }
//            case 3:
//                NavigationStack { TaskCalendarView() }
//            case 6:
//                NavigationStack { WalletView() }
//            case 2:
//                NavigationStack { SettingsView() }
//            default:
//                NavigationStack { HomeView() }
//            }
//            
//        }
//        
//        
//    }
//    
//    // MARK: - Sidebar Row (iPad)
//    
//    @ViewBuilder
//    private func sidebarRow(title: String, systemImage: String, tag: Int) -> some View {
//        
//        Button {
//            selectedTab = tag
//        } label: {
//            Label(title, systemImage: systemImage)
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .padding(.vertical, 6)
//                .background(
//                    selectedTab == tag
//                    ? Color.accentColor.opacity(0.15)
//                    : Color.clear
//                )
//                .clipShape(RoundedRectangle(cornerRadius: 8))
//        }
//        .buttonStyle(.plain)
//    }
//    
//    
//    // MARK: - Custom Tab Item
//    
//    private func tabItem(_ icon: String, _ title: String, _ tag: Int) -> some View {
//
//        Button {
//
//            UIImpactFeedbackGenerator(style: .light).impactOccurred()
//
//            if selectedTab != tag {
//                resetTab(selectedTab)
//                selectedTab = tag
//            } else {
//                resetTab(tag)
//            }
//
//        } label: {
//            VStack(spacing: 4) {
//                Image(systemName: icon)
//                    .font(.system(size: 21, weight: .regular))
//                    .symbolRenderingMode(.hierarchical)
//                    .frame(height: 22)
//                Text(title)
//                    .font(.system(size:9, weight: .medium))
//                    .lineLimit(1)
//                    .minimumScaleFactor(0.9)
//                    .layoutPriority(1)
//            }
//            .frame(minWidth: 0)
//            .frame(maxWidth: .infinity)
//            .frame(height: 49)
//            .foregroundStyle(selectedTab == tag ? Color.accentColor : Color.primary)
//            .contentShape(Rectangle())
//        }
//        .buttonStyle(.plain)
//        .transaction { $0.animation = nil }
//        .animation(.snappy(duration: 0.12), value: selectedTab)
//    }
//    
//    private func resetTab(_ tab: Int) {
//        switch tab {
//        case 0:
//            if !homePath.isEmpty { homePath = NavigationPath() }
//        case 1:
//            if !listPath.isEmpty { listPath = NavigationPath() }
//        case 5:
//            if !mapPath.isEmpty { mapPath = NavigationPath() }
//        case 4:
//            if !weeklyPath.isEmpty { weeklyPath = NavigationPath() }
//        case 3:
//            if !calendarPath.isEmpty { calendarPath = NavigationPath() }
//        case 6:
//            if !walletPath.isEmpty { walletPath = NavigationPath() }
//        case 2:
//            if !settingsPath.isEmpty { settingsPath = NavigationPath() }
//        default:
//            break
//        }
//    }
//}
//
