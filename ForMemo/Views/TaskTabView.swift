import SwiftUI
import SwiftData

struct TaskTabView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedTab: Int = 0
    @State private var hasRedirected = false
    @State private var showSnoozeAlert = false
    @Namespace private var tabAnimation
    
    @AppStorage("TaskWeekDays")
    private var taskWeekDays: Int = 3
    
    @AppStorage("startupTab")
    private var startupTab: Int = 1
    
    private var isMac: Bool {
#if targetEnvironment(macCatalyst)
        return true
#else
        return false
#endif
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .safeAreaInsets.bottom ?? 0
    }
    

    var body: some View {
        
        Group {
            if isMac {
                macLayout
            } else if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .onAppear {
            // Start from Home immediately
            selectedTab = 0
            
            // 1) Wait 1.5s (data loading)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                
                // Start faster rotation
                NotificationCenter.default.post(name: Notification.Name("StartHomeIconRotationFast"), object: nil)
                
                // 2) Wait for rotation duration (assumed handled in HomeView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    
                    // 3) Additional delay before navigation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if selectedTab == 0 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedTab = startupTab
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .snoozeRejectedDueToDeadline)) { _ in
            showSnoozeAlert = true
        }
        .alert("Snooze not scheduled",
               isPresented: $showSnoozeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Snooze exceeds the deadline. No snooze notification will be scheduled. The deadline notification will still occur.")
        }
    }
    
    
    // MARK: - macLayout Layout (UNCHANGED)
    
    private var macLayout: some View {
        
        NavigationSplitView {
            
            List(selection: Binding<Int?>(
                get: { selectedTab },
                set: { if let value = $0 { selectedTab = value } }
            )) {
                
                Label(NSLocalizedString("home", comment: ""), systemImage: "house").tag(0)
                Label(NSLocalizedString("list_tab", comment: ""), systemImage: "checklist").tag(1)
                Label(NSLocalizedString("map_tab", comment: ""), systemImage: "map").tag(5)
                Label(
                    taskWeekDays == 1
                    ? String(localized: "today_tab")
                    : String(localized: "\(taskWeekDays) days_tab"),
                    systemImage: "calendar.day.timeline.right"
                ).tag(4)
                Label(NSLocalizedString("calendar_tab", comment: ""), systemImage: "calendar").tag(3)
                Label(NSLocalizedString("settings_tab", comment: ""), systemImage: "gear").tag(2)
            }
            .listStyle(.sidebar)
            .navigationTitle("Tasks")
            
            
        } detail: {
            
            switch selectedTab {
            case 0:
                HomeView()
            case 1:
                TaskListView()
            case 5:
                TaskMapView()
            case 4:
                WeeklyTasksView()
            case 3:
                TaskCalendarView()
            case 2:
                SettingsView()
            default:
                HomeView()
            }
            
        }
        
    }
    
    
    // MARK: - iPhone Layout
    
    private var iPhoneLayout: some View {
        ZStack {
            switch selectedTab {
            case 0:
                NavigationStack {
                    HomeView()
                }
            case 1:
                NavigationStack {
                    TaskListView()
                }
            case 5:
                NavigationStack { TaskMapView() }
            case 4:
                NavigationStack { WeeklyTasksView() }
            case 3:
                NavigationStack { TaskCalendarView() }
            case 2:
                NavigationStack { SettingsView() }
            default:
                NavigationStack { HomeView() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    tabItem("house", NSLocalizedString("Home", comment: ""), 0)
                    tabItem("checklist", NSLocalizedString("list_tab", comment: ""), 1)
                    tabItem("calendar.day.timeline.right",
                            taskWeekDays == 1
                            ? String(localized: "today_tab")
                            : String(localized: "\(taskWeekDays) days_tab"),
                            4)
                    tabItem("calendar", NSLocalizedString("calendar_tab", comment: ""), 3)
                    tabItem("map", NSLocalizedString("map_tab", comment: ""), 5)
                    tabItem("gear", NSLocalizedString("settings_tab", comment: ""), 2)
                }
                .frame(height: 49)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .background(.bar)
            .overlay(
                Divider().opacity(0.3),
                alignment: .top
            )
            .padding(.vertical, 4)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    // MARK: - iPad Layout
    
    private var iPadLayout: some View {
        
        NavigationSplitView {
            
            List {
                
                sidebarRow(title: NSLocalizedString("home_tab", comment: ""), systemImage: "house", tag: 0)
                sidebarRow(title: NSLocalizedString("list_tab", comment: ""), systemImage: "checklist", tag: 1)
                sidebarRow(title:
                                taskWeekDays == 1
                                ? String(localized: "today_tab")
                                : String(localized: "days_tab \(taskWeekDays)"),
                           systemImage: "calendar.day.timeline.right", tag: 4)
                sidebarRow(title: NSLocalizedString("calendar_tab", comment: ""), systemImage: "calendar", tag: 3)
                sidebarRow(title: NSLocalizedString("map_tab", comment: ""), systemImage: "map", tag: 5)
                sidebarRow(title: NSLocalizedString("settings_tab", comment: ""), systemImage: "gear", tag: 2)
            }
            .listStyle(.sidebar)
            .navigationTitle("Tasks")
            
            
        } detail: {
            
            switch selectedTab {
            case 0:
                NavigationStack { HomeView() }
            case 1:
                NavigationStack { TaskListView() }
            case 5:
                NavigationStack { TaskMapView() }
            case 4:
                NavigationStack { WeeklyTasksView() }
            case 3:
                NavigationStack { TaskCalendarView() }
            case 2:
                NavigationStack { SettingsView() }
            default:
                NavigationStack { HomeView() }
            }
            
        }
        
        
    }
    
    // MARK: - Sidebar Row (iPad)
    
    @ViewBuilder
    private func sidebarRow(title: String, systemImage: String, tag: Int) -> some View {
        
        Button {
            selectedTab = tag
        } label: {
            Label(title, systemImage: systemImage)
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
    
    // MARK: - Redirect
    
    private func handleInitialRedirect() {
        // DISABLED: was overriding user tab selection
    }
    
    @ViewBuilder
    private func sidebarItem(_ title: String, _ icon: String, _ tag: Int) -> some View {
        
        Button {
            selectedTab = tag
        } label: {
            Label(title, systemImage: icon)
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
    // MARK: - Custom Tab Item

    private func tabItem(_ icon: String, _ title: String, _ tag: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTab = tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 22)
                Text(title)
                    .font(.system(size:8, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .layoutPriority(1)
            }
            .frame(minWidth: 0)
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .foregroundStyle(selectedTab == tag ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil }
        .animation(.snappy(duration: 0.12), value: selectedTab)
    }
}
