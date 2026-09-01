import SwiftUI
import SwiftData
import os

struct TaskTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppSettings.self) private var settings

    @Query private var tasks: [TodoTask]
    @Query private var documents: [DocumentItem]
    @Query private var cards: [LoyaltyCard]
    @Query private var trips: [TripList]
    
    @State private var selectedTab: Int = 0
    @State private var previousTab = 0
    @State private var showSnoozeAlert = false
    @State private var showMorePopover = false
    @State
    private var recoveryResult: AssetRecoveryCoordinator.RecoveryCheckResult?
    @State
    private var recoveryCheckPerformed = false
    
    @State private var StartPath = NavigationPath()
    @State private var dashboardPath = NavigationPath()
    @State private var listPath = NavigationPath()
    @State private var weeklyPath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var mapPath = NavigationPath()
    @State private var walletPath = NavigationPath()
    @State private var vaultPath = NavigationPath()
    @State private var TripsPath = NavigationPath()
    @State private var documentsPath = NavigationPath()
    @State private var weatherPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var notesPath = NavigationPath()
    @StateObject private var noteEditorCoordinator = NoteEditorCoordinator()
    @State private var showNoteUnsavedChangesAlert = false
    @State private var pendingNoteTab: Int?
    
    var body: some View {
        rootLayout
            .onAppear {

                selectedTab = 0

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(
                        name: Notification.Name("StartStartIconRotationFast"),
                        object: nil
                    )

                    // Wait exactly for the single rotation to complete.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard selectedTab == 0 else {
                            return
                        }

                        withAnimation(.easeInOut(duration: 0.18)) {
                            if settings.startupTab == -1 {
                                let hasContent =
                                    !tasks.isEmpty ||
                                    !documents.isEmpty ||
                                    !cards.isEmpty ||
                                    !trips.isEmpty

                                selectedTab = hasContent ? 10 : 1
                            } else {
                                selectedTab = settings.startupTab
                            }
                        }
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {

                    guard selectedTab == 0 else {
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.18)) {
                        if settings.startupTab == -1 {
                            let hasContent =
                                !tasks.isEmpty ||
                                !documents.isEmpty ||
                                !cards.isEmpty ||
                                !trips.isEmpty
                            selectedTab = hasContent ? 10 : 1
                        } else {
                            selectedTab = settings.startupTab
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .snoozeRejectedDueToDeadline)) { _ in
                showSnoozeAlert = true
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("DashboardOpenList")
                )
            ) { _ in

                dashboardPath = NavigationPath()

                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = 1
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("VaultAuthenticationFailed")
                )
            ) { _ in

                vaultPath = NavigationPath()

                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = previousTab == 11 ? 10 : previousTab
                }
            }
            .onChange(of: settings.showWeatherForecast) { _, enabled in
                if !enabled && selectedTab == 9 {
                    selectedTab = 0
                }
            }
        
            .onChange(of: settings.showVault) { _, enabled in
                if !enabled && selectedTab == 11 {
                    selectedTab = 0
                }
            }
        
            .onChange(of: selectedTab) { oldValue, newValue in

                previousTab = oldValue

                if oldValue == 11 && newValue != 11 {

                    VaultLock.shared.lock()

                    vaultPath = NavigationPath()
                }
            }
            .alert(
                "Snooze not scheduled",
                isPresented: $showSnoozeAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Snooze exceeds the deadline. No snooze notification will be scheduled. The deadline notification will still occur.")
            }
        
            .alert(item: $recoveryResult) { result in

                Alert(

                    title: Text("Asset Recovery"),

                    message: Text(
    """
    \(result.duplicateFolders.count) duplicate asset folders detected.

    \(result.duplicateFolders
        .map { "• \($0)" }
        .joined(separator: "\n"))

    Automatic recovery has been suspended because
    Asset Recovery Diagnostics is enabled.

    Press Repair to merge the folders.
    """
),

                    primaryButton: .default(
                        Text("Repair")
                    ) {

                        AssetRecoveryCoordinator.recoverAutomaticallyIfNeeded(
                            context: modelContext
                        )

                        recoveryResult = nil

                    },

                    secondaryButton: .cancel {

                        recoveryResult = nil

                    }

                )

            }
            .alert(
                String(localized: "Save changes?"),
                isPresented: $showNoteUnsavedChangesAlert
            ) {
                Button(String(localized: "Save")) {
                    noteEditorCoordinator.save?()
                    noteEditorCoordinator.reset()

                    if let pendingNoteTab {
                        withAnimation(nil) {
                            selectedTab = pendingNoteTab
                        }
                        resetTab(pendingNoteTab)
                    }

                    self.pendingNoteTab = nil
                }

                Button(String(localized: "Don’t Save"), role: .destructive) {
                    noteEditorCoordinator.discard?()
                    noteEditorCoordinator.reset()

                    if let pendingNoteTab {
                        withAnimation(nil) {
                            selectedTab = pendingNoteTab
                        }
                        resetTab(pendingNoteTab)
                    }

                    self.pendingNoteTab = nil
                }

                Button(String(localized: "Cancel"), role: .cancel) {
                    pendingNoteTab = nil
                }
            } message: {
                Text(String(localized: "You have unsaved changes."))
            }
        
            .task {
                
                AppLogger.persistence.notice("TASKTAB .task STARTED")
                
                guard !recoveryCheckPerformed else {
                    return
                }

                recoveryCheckPerformed = true

                let result = AssetRecoveryCoordinator.launchRecoveryCheck()

                guard DiagnosticsOptions.assetRecoveryDiagnostics else {
                    return
                }

                guard result.needsRepair else {
                    return
                }

                recoveryResult = result

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

    private var visibleTabs: [AppTab] {
        settings.orderedTabs.filter { $0.isVisible(using: settings) }
    }

    private var primaryTabs: [AppTab] {
        Array(visibleTabs.prefix(4))
    }

    private var moreTabs: [AppTab] {
        Array(visibleTabs.dropFirst(4))
    }
    
    private var iPhoneLayout: some View {
        
        ZStack {
            currentTabView
        }
        .safeAreaInset(edge: .bottom) {
            
            HStack(spacing: 10) {
                ForEach(primaryTabs) { tab in
                    tabItem(tab.icon, tab.title(using: settings), tab.rawValue)
                }
                
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
                            .opacity(moreTabs.contains { $0.rawValue == selectedTab } ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .contentShape(Rectangle())
                    .foregroundStyle(
                        moreTabs.contains { $0.rawValue == selectedTab }
                        ? Color.accentColor
                        : Color.primary
                    )
                }
                .popover(isPresented: $showMorePopover, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(moreTabs) { tab in
                            moreTabItem(tab)
                        }
                    }
                    .padding(.vertical, 13)
                    .padding(.trailing, 36)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: true, vertical: false)
                    .presentationCompactAdaptation(.popover)
                }
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.clear)
                    .glassEffect()
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.accentColor.opacity(0.06))
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
            
        case 10:
            NavigationStack(path: $dashboardPath) {
                Dashboard()
            }
            
            
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
        
        case 11:
            NavigationStack(path: $vaultPath) {
                VaultGateView()
            }
            
        case 7:
            NavigationStack(path: $TripsPath) {
                TravelKitListView()
            }
            
        case 8:
            NavigationStack(path: $documentsPath) {
                DocumentsView()
            }
        case 12:
            NavigationStack(path: $notesPath) {
                NoteListView(noteEditorCoordinator: noteEditorCoordinator)
                    .environmentObject(noteEditorCoordinator)
            }
        case 9:
            NavigationStack(path: $weatherPath) {
                WeatherForecastView()
            }
            
        case 2:
            NavigationStack(path: $settingsPath) {
                SettingsView()
            }
        case 13:
            NavigationStack {
                RecentlyDeletedView(onClose: {
                    selectedTab = previousTab
                })
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
                ForEach(visibleTabs) { tab in
                    sidebarRow(tab.title(using: settings), tab.icon, tab.rawValue)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Tasks")
            
        } detail: {
            currentTabView
                .safeAreaPadding(.leading, 8)
                
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

    private func moreTabItem(_ tab: AppTab) -> some View {
        Button {
            selectedTab = tab.rawValue
            showMorePopover = false
        } label: {
            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    Image(systemName: tab.icon)
                        .frame(width: 22)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 3)
                        .opacity(selectedTab == tab.rawValue ? 1 : 0)
                }

                Text(tab.title(using: settings))
            }
            .foregroundStyle(selectedTab == tab.rawValue ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func selectTab(_ tag: Int) {
        if selectedTab == 12,
           tag != 12,
           noteEditorCoordinator.isDirty {
            pendingNoteTab = tag
            showNoteUnsavedChangesAlert = true
            return
        }

        withAnimation(nil) {
            selectedTab = tag
        }

        Task {
            resetTab(tag)
        }
    }

    private func tabItem(
        _ icon: String,
        _ title: String,
        _ tag: Int
    ) -> some View {
        
        Button {
            
            if selectedTab != tag {
                selectTab(tag)
            }
            
        } label: {
            
            VStack(spacing: 2) {
                
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
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
            .contentShape(Rectangle())
            .foregroundStyle(
                selectedTab == tag
                ? Color.accentColor
                : Color.primary
            )
            // Bubble background removed
        }
        .buttonStyle(.plain)
    }
    
    private func resetTab(_ tab: Int) {
        
        switch tab {
            
        case 10:
            dashboardPath = NavigationPath()

            NotificationCenter.default.post(
                name: Notification.Name("DashboardReset"),
                object: nil
            )
            
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
        
        case 11:
            if !vaultPath.isEmpty {
                vaultPath = NavigationPath()
            }
            
        case 7:
            if !TripsPath.isEmpty {
                TripsPath = NavigationPath()
            }
        
        case 8:
            if !documentsPath.isEmpty {
                documentsPath = NavigationPath()
            }
        case 9:
            if !weatherPath.isEmpty {
                weatherPath = NavigationPath()
            }
            
        case 2:
            if !settingsPath.isEmpty {
                settingsPath = NavigationPath()
            }
        case 12:
            if !notesPath.isEmpty {
                notesPath = NavigationPath()
            }
        case 13:
            break
            
        default:
            break
        }
    }
}
