import SwiftUI
import UserNotifications


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
    
    // let start: GuideStart
    
    // MARK: - DATA
    
    private static let stepsData: [AppQuickGuide] = [
        
        // ⭐ SIRI
        .init(
            title: String(localized: "Use Siri Shortcuts"),
            description: String(localized:
                """
                Add tasks quickly using Siri. Try saying:
                
                • Add a task in \(appName)
                • Create a task in \(appName)
                • Remind me in \(appName)
                
                Best option:
                • New \(appName)   
                
                You can let Siri decide the best reminder automatically or choose it yourself.
                """
                               ),
            icon: "waveform.circle",
            tint: .teal
        ),
        
        .init(
            title: String(localized:"Smart Priorities"),
            description: String(localized:"Tasks with critical priority that are due today or overdue are highlighted automatically. You can customize highlight color and opacity in Settings."),
            icon: "exclamationmark.circle",
            tint: .red
        ),
        
            .init(
                title: String(localized:"Smart Badges"),
                description: String(localized:"The app icon shows the number of overdue tasks. Inside the app, each task shows how many days are left."),
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
            icon: "iphone.badge.location",
            tint: .green
        ),
        .init(
            title: String(localized:"Map View"),
            description: String(localized:"View tasks directly on the map. Tasks with a location appear as pins. Tap a pin to open task details. The map automatically fits all tasks on first load and preserves your zoom level afterward."),
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
                description: String(localized: "Stay on track with intelligent reminders. Every task includes a notification at the due time. You can add custom reminders, enable an automatic early notification (1–7 days before), and quickly snooze notifications when needed."),
                icon: "deskclock",
                tint: .orange
            ),
        .init(
            title: String(localized:"Recurring Tasks"),
            description: String(localized:"Set tasks to repeat daily, weekly, monthly, or yearly. When you complete a recurring task, the next one is created automatically based on the selected frequency."),
            icon: "repeat",
            tint: .green
        ),
        .init(

            title: String(localized: "Location-Based Reminders"),

            description: String(localized: "Get notified when you arrive at a place. Associate a location with a task and receive a reminder automatically at the right moment."),

            icon: "mappin.and.ellipse",

            tint: .blue

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
            ),
        
            .init(
                title: String(localized:"Import Your Data"),
                description: String(localized:"Import tasks from Apple Reminders, Calendar or CSV files. Avoid duplicates and keep everything in one place.\n\nNote: attachments are not included in imports."),
                icon: "arrow.down.circle",
                tint: .blue
            ),
        
            .init(
                title: String(localized:"Export Anywhere"),
                description: String(localized:"Export your tasks to Calendar, CSV or ICS format to share or reuse them in other apps.\n\nNote: attachments are not included in exports."),
                icon: "arrow.up.circle",
                tint: .purple
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
                Text("Quick Guide")
                    .font(.title3)
                    .padding(.vertical, 8)
                    .foregroundStyle(.secondary)
                
                TabView {
                    
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
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                
                Button("Get Started") {
                    dismiss()
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
            }
        }
    }
}
