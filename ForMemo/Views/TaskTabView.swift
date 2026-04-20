import SwiftUI
import SwiftData

struct TaskTabView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedTab: Int? = 0
    @State private var hasRedirected = false
    
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
        .allowsHitTesting(scenePhase == .active)
        .onAppear {
            handleInitialRedirect()
        }
    }
    
    
    // MARK: - macLayout Layout (UNCHANGED)
    
    private var macLayout: some View {
        
        NavigationSplitView {
            
            List(selection: $selectedTab) {
                
                Label("Home", systemImage: "house").tag(0)
                Label("List", systemImage: "checklist").tag(1)
                Label("\(taskWeekDays) days", systemImage: "calendar.day.timeline.right").tag(4)
                Label("Calendar", systemImage: "calendar").tag(3)
                Label("Settings", systemImage: "gear").tag(2)
            }
            .listStyle(.sidebar)
            .navigationTitle("Tasks")
            
            
        } detail: {
            
            switch selectedTab {
            case 0:
                HomeView()
            case 1:
                TaskListView()
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
    
    
    // MARK: - iPhone Layout (UNCHANGED)
    
    private var iPhoneLayout: some View {
        
        TabView(selection: $selectedTab) {
            
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(0)
            
            NavigationStack {
                TaskListView()
            }
            .tabItem {
                Label("List", systemImage: "checklist")
            }
            .tag(1)
            
            NavigationStack {
                WeeklyTasksView()
            }
            .tabItem {
                Label("\(taskWeekDays) days", systemImage: "calendar.day.timeline.right")
            }
            .tag(4)
            
            NavigationStack {
                TaskCalendarView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(3)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
    
    // MARK: - iPad Layout
    
    private var iPadLayout: some View {
        
        NavigationSplitView {
            
            List {
                
                sidebarRow(title: "Home", systemImage: "house", tag: 0)
                sidebarRow(title: "List", systemImage: "checklist", tag: 1)
                sidebarRow(title: "\(taskWeekDays) days", systemImage: "calendar.day.timeline.right", tag: 4)
                sidebarRow(title: "Calendar", systemImage: "calendar", tag: 3)
                sidebarRow(title: "Settings", systemImage: "gear", tag: 2)
            }
            .listStyle(.sidebar)
            .navigationTitle("Tasks")
            
            
        } detail: {
            
            switch selectedTab {
            case 0:
                NavigationStack { HomeView() }
            case 1:
                NavigationStack { TaskListView() }
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
        
        let startingTab = selectedTab
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.4))
            
            guard !hasRedirected else { return }
            
            if selectedTab == startingTab {
                
                withAnimation(
                    .interactiveSpring(
                        response: 1,
                        dampingFraction: 0.3,
                        blendDuration: 0.9
                    )
                ) {
                    selectedTab = startupTab
                }
            }
            
            hasRedirected = true
        }
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
}
