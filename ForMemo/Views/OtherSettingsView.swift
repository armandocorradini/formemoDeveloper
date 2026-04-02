import SwiftUI
import SwiftData

struct OtherSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("startupTab")
    private var startupTab: Int = 1
    
    @AppStorage("confirmTaskDeletion")
    private var confirmTaskDeletion = true
    @AppStorage("notificationLeadTimeDays")
    private var notificationLeadTimeDays: Int = 1
    
    @AppStorage("badgeIncludeExpired") private var badgeIncludeExpired: Bool = true
    @AppStorage("showAppBadge") private var showAppBadge: Bool = true
    @AppStorage("TaskWeekDays")
    private var taskWeekDays: Int = 3
    
    @State private var path = NavigationPath()
    
    @State private var showShort = false
    
    var body: some View {
        ZStack {
            // 1. IL GRADIENTE (Sotto a tutto)
            LinearGradient(colors: [backColor1, backColor2],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // 2. IL MATERIAL (Effetto vetro)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Form {
                Section(
                    header: Text(String(localized: "Open at launch"))
                ) {
                    
                    Picker(
                        String(localized: "View"),
                        selection: $startupTab
                    ) {
                        Text(String(localized: "Home"))
                            .tag(0)
                        
                        Text(String(localized: "List"))
                            .tag(1)
                        
                        Text(String(localized: "\(taskWeekDays) days"))
                            .tag(4)
                        
                        Text(String(localized: "Calendar"))
                            .tag(3)
                    }
                    .pickerStyle(.navigationLink)
                    //                .labelsHidden()
                }
                
                
                
                Section(
                    header: Text(String(localized: "Notification and badge time"))
                ) {
                    Picker("Notify", selection: Binding(
                        get: { notificationLeadTimeDays },
                        set: { newValue in
                            notificationLeadTimeDays = newValue
                            
                            // Aggiorna badge
                            NotificationManager.shared.refresh(force: true)
                        }
                    )) {
                        ForEach(NotificationLeadTime.allCases) { value in
                            Text(value.title).tag(value.rawValue)
                        }
                        Text(notificationLeadTimeDays == 0
                             ? String(localized: "Notification and updating badge: \nAt time of event")
                             : String(localized: "Notification and updating badge: \n\(notificationLeadTimeDays) days before"))
                        .foregroundStyle(.blue)
                        .font(.footnote)
                        
                    }
                    .pickerStyle(.navigationLink)
                    //                .labelsHidden()
                    
                    Toggle("Show app badge", isOn: $showAppBadge)
                    
                    Toggle("Include expired tasks in badge", isOn: $badgeIncludeExpired)
                }
                Section("Deletion") {
                    
                    Toggle("Confirm task deletion", isOn: $confirmTaskDeletion)
                }
                
            }
            .onChange(of: badgeIncludeExpired) { oldValue, newValue in
                // Questa logica viene eseguita non appena il valore cambia
                NotificationManager.shared.refresh(force: true)
            }
            .onChange(of: showAppBadge) { _, _ in
                NotificationManager.shared.refresh(force: true)
            }
            .onChange(of: notificationLeadTimeDays) { _, _ in
                NotificationManager.shared.refresh(force: true)
            }
            .navigationTitle("")
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                }
            }
        }
    }
}
