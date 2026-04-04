import SwiftUI
import UserNotifications

// MARK: - DESTINAZIONE

enum GuideStart {
    case normal
    case siri
}

// MARK: - MODEL

struct AppQuickGuide: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let tint: Color
}

// MARK: - VIEW

struct AppQuickGuideView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStep: Int
    
    // MARK: - INIT
    
    init(start: GuideStart = .normal) {
        
        let steps = Self.stepsData
        let siriIndex = steps.firstIndex { $0.icon == "waveform.circle" } ?? 0
        
        switch start {
        case .normal:
            _currentStep = State(initialValue: 0)
        case .siri:
            _currentStep = State(initialValue: siriIndex)
        }
    }
    
    // MARK: - DATA
    
    private static let stepsData: [AppQuickGuide] = [
        
        .init(
            title: String(localized:"Smart Priorities"),
            description: String(localized:"Tasks change color automatically based on their category. Overdue tasks and upcoming deadlines are visually highlighted."),
            icon: "exclamationmark.circle",
            tint: .red
        ),
        
            .init(
                title: String(localized:"Smart Badges"),
                description: String(localized:"The app icon shows the number of urgent tasks. Inside the app, each task shows how many days are left."),
                icon: "app.badge",
                tint: .orange
            ),
        
            .init(
                title: String(localized:"Rich Attachments"),
                description: String(localized:"Attach photos, documents and scanned pages. All files remain linked to the related task."),
                icon: "paperclip",
                tint: .blue
            ),
        
            .init(
                title: String(localized:"Choose Your Map"),
                description: String(localized:"Select your preferred navigation app in Settings to open task locations using Apple Maps or Google Maps."),
                icon: "map",
                tint: .green
            ),
        
            .init(
                title: String(localized:"Selective Sharing"),
                description: String(localized:"When sharing a task, you can choose what to include, such as text, dates, locations and attachments."),
                icon: "square.and.arrow.up",
                tint: .purple
            ),
        
            .init(
                title: String(localized: "Interactive Calendar"),
                description: String(localized:
                                        "Visualize your schedule at a glance. Dots highlight days with open tasks, while intuitive swipes let you complete or delete tasks instantly.\n\nPublic holidays and Sundays are shown in red."
                                   ),
                icon: "calendar",
                tint: .pink
            ),
        
        // ⭐ SIRI
        .init(
            title: String(localized: "Use Siri Shortcuts"),
            description: String(localized:
                """
                Add tasks quickly using Siri. Try saying:
                
                • Add a task in \(appName)
                • Create a task in \(appName)
                • Remind me in \(appName)
                
                Siri will ask for the task details and automatically create it with a reminder.
                """
                               ),
            icon: "waveform.circle",
            tint: .teal
        ),
        
            .init(
                title: String(localized:"Automatic iCloud Login"),
                description: String(localized:"\(appName) automatically uses your Apple ID and your personal iCloud account. No sign in or additional account is required."),
                icon: "icloud",
                tint: .cyan
            ),
        
            .init(
                title: String(localized:"Your Data, Your Control"),
                description: String(localized:"Your tasks and attachments are stored only in your personal iCloud account. The developer does not run any server and cannot access your data."),
                icon: "lock.shield",
                tint: .indigo
            ),
        
            .init(
                title: String(localized: "Enable notifications"),
                description: String(localized:
                                        "To show the badge on the app icon and receive reminders and sound notifications, you must allow notifications for \(appName)."
                                   ),
                icon: "bell.badge",
                tint: .blue
            ),
        
            .init(
                title: String(localized: "Smart Notifications"),
                description: String(localized: "Stay on track with timely reminders. Long-press a notification to quickly snooze a task or open the app."),
                icon: "deskclock",
                tint: .orange
            ),
        
            .init(
                title: String(localized:"Customize your task list"),
                description: String(localized:"""
            • Change the main task icon style
            • Choose the days badge color
            • Show or hide attachments, location and priority icons
            • Preview changes before applying them
            """),
                icon: "list.bullet.circle",
                tint: .indigo
            )
    ]
    
    private var steps: [AppQuickGuide] { Self.stepsData }
    
    // MARK: - UI
    
    var body: some View {
        ZStack {
            
            LinearGradient(colors: [backColor1, backColor2],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .padding()
                }
                
                Text("Quick Guide")
                    .font(.title3)
                    .padding(.vertical, 8)
                    .foregroundStyle(.secondary)
                
                TabView(selection: $currentStep) {
                    
                    ForEach(steps.indices, id: \.self) { index in
                        
                        let step = steps[index]
                        
                        VStack(spacing: 16) {
                            
                            Image(systemName: step.icon)
                                .font(.system(size: 48))
                                .foregroundStyle(step.tint)
                            
                            Text(step.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                            
                            Text(step.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(index == steps.count - 1 ? .leading : .center)
                                .padding(.horizontal, 32)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                
                Button {
                    if currentStep < steps.count - 1 {
                        withAnimation {
                            currentStep += 1
                        }
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(currentStep == steps.count - 1 ? "Get Started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
            }
        }
    }
}
