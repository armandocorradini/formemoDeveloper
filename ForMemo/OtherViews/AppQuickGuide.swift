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
                Control \(appName) with four simple commands:

                • New \(appName)
                Create a new task.

                • Search \(appName)
                Find tasks by keyword.

                • Check \(appName)
                Hear planned tasks.

                • Note \(appName)
                Create a new note.
                """
            ),
            icon: "waveform.circle",
            tint: .teal
        ),
        .init(
            title: String(localized: "Tasks"),
            description: String(localized: "Create and manage your tasks with due dates, priorities, categories, reminders, recurring schedules, locations and attachments. Quickly complete, edit,duplicate, archive or delete tasks, and use filters to focus on what matters."),
            icon: "checklist",
            tint: .blue
        ),
        .init(
            title: String(localized: "Notes"),
            description: String(localized: "Create and organize notes with rich text formatting. Add bold, italic and underlined text, and use bullet, dash and numbered lists. Share notes with other apps and import notes from Apple Notes."),
            icon: "note.text",
            tint: .green
        ),
        .init(
            title: String(localized:"Dashboard"),
            description: String(localized:"The Dashboard automatically highlights what needs your attention first. View overdue tasks, tasks due today, upcoming activities, weather forecasts and recently opened items from Wallet, Documents and Trip Lists in one place."),
            icon: "house",
            tint: .blue
        ),
        
        .init(
            title: String(localized:"Smart Priorities"),
            description: String(localized:"Tasks with critical priority that are due today or overdue are highlighted automatically. You can customize highlight color in Settings."),
            icon: "exclamationmark.circle",
            tint: .red
        ),
        
        .init(
            title: String(localized:"Smart Badges"),
            description: String(localized:"Choose what the app icon badge displays: overdue tasks or tasks that reached the global notification time. Inside the app, each task shows how many days are left."),
            icon: "app.badge",
            tint: .orange
        ),

        .init(
            title: String(localized:"Powerful Filters"),
            description: String(localized:"Instantly filter tasks by category, priority, due date period, overdue status or tasks without a deadline. Combine filters to focus only on what matters."),
            icon: "line.3.horizontal.decrease.circle",
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
            description: String(localized:"Select your preferred navigation app in Settings. Open task locations with your favorite navigation app or choose which app to use each time."),
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
            title: String(localized:"Integrated Weather"),
            description: String(localized:"Weather forecasts are available for today, tomorrow and the day after tomorrow directly inside task views and weekly planning. Tap the weather information to open the detailed forecast view with weekly and hourly conditions."),
            icon: "cloud.sun",
            tint: .cyan
        ),

        .init(
            title: String(localized:"Wallet for Cards and Tickets"),
            description: String(localized:"Store and organize loyalty cards and tickets with barcodes or QR codes, holder information, notes, custom colors and optional logos always available inside the app."),
            icon: "creditcard",
            tint: .mint
        ),

        .init(
            title: String(localized:"Documents Expiry Tracker"),
            description: String(localized:"Keep track of important documents, expiry dates, notes and reminders. Receive notifications before documents expire."),
            icon: "doc.text",
            tint: .brown
        ),

        .init(
            title: String(localized:"Barcode Scanner"),
            description: String(localized:"Quickly scan loyalty cards and tickets using the device camera or import ticket images to automatically save barcode and QR code information into your Wallet."),
            icon: "barcode.viewfinder",
            tint: .orange
        ),

        .init(
            title: String(localized:"Trip Lists"),
            description: String(localized:"Create and manage travel packing lists organized into sections."),
            icon: "suitcase.rolling",
            tint: .mint
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
                description: String(localized:"ForMemo automatically uses your Apple ID and personal iCloud account when iCloud is available. No separate ForMemo account or sign-in is required."),
                icon: "icloud",
                tint: .cyan
            ),
        
            .init(
                title: String(localized:"Your Data, Your Control"),
                description: String(localized:"Your tasks and attachments are stored on your device and, when iCloud is enabled, synchronized with your personal iCloud account. The developer does not run any server and cannot access your data."),
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
            title: String(localized: "Siri Notification Announcements"),
            description: String(localized:
                                    "If Siri notification announcements are enabled in iOS Settings, Siri can read \(appName) notifications aloud on supported devices such as AirPods or CarPlay."
                               ),
            icon: "waveform.badge.mic",
            tint: .teal
        ),
        
        .init(
            title: String(localized: "Smart Notifications"),
            description: String(localized: "Every task automatically generates a notification when it becomes overdue. Add additional reminders, location alerts and early notifications up to 7 days in advance."),
            icon: "deskclock",
            tint: .orange
        ),
        .init(
            title: String(localized: "Recurring Tasks"),
            description: String(localized: "Set tasks to repeat hourly, daily, weekly, monthly, or yearly. When you complete a recurring task, the next occurrence is scheduled automatically. You can also choose whether to keep completed occurrences in your history or simply move the task to the next occurrence."),
            icon: "arrow.triangle.2.circlepath",
            tint: .blue
        ),
        .init(

            title: String(localized: "Location-Based Reminders"),

            description: String(localized: "Get notified when you arrive at a place. Associate a location with a task and receive a reminder automatically at the right moment."),

            icon: "mappin.and.ellipse",

            tint: .blue

        ),
        
            .init(
                title: String(localized: "Vault & Secure Credentials"),
                description: String(localized: "Store and organize personal credentials including usernames, email addresses, websites, passwords, PINs, OTP secrets, notes, and custom secrets. Organize credentials into categories, mark favorites, generate strong passwords, and protect access using your device authentication."),
                icon: "lock.shield",
                tint: .indigo
            ),

            .init(
                title: String(localized: "AutoFill Passwords"),
                description: String(localized: "Enable ForMemo in iOS Settings > General > AutoFill & Passwords to securely use your saved Vault credentials in supported apps and websites. Copied passwords can be cleared automatically from the clipboard."),
                icon: "key.fill",
                tint: .blue
            ),
        .init(
            title: String(localized: "Password Generator"),
            description: String(localized: "Create strong passwords directly while adding or editing Vault credentials. Generated passwords help improve the security of your accounts."),
            icon: "key.horizontal",
            tint: .green
        ),
        .init(
            title: String(localized: "Import Credentials"),
            description: String(localized: "Import supported credential files from compatible password managers into the Vault to quickly transfer your existing accounts."),
            icon: "square.and.arrow.down",
            tint: .blue
        ),
            .init(
                title: String(localized: "Overview"),
                description: String(localized: "See an at-a-glance summary of your tasks, documents, Wallet items, trip lists, and Vault data to quickly understand what needs your attention."),
                icon: "rectangle.3.group",
                tint: .teal
            ),

            .init(
                title: String(localized: "Make ForMemo Yours"),
                description: String(localized: "Reorder the tabs in the navigation bar and personalize task rows by choosing their style, corners, borders, material, and height."),
                icon: "slider.horizontal.3",
                tint: .purple
            ),

            .init(
                title: String(localized: "Document Storage Location"),
                description: String(localized: "For each document, record where the original is physically stored, such as a drawer, cabinet, folder, or safe."),
                icon: "cabinet",
                tint: .brown
            ),

            .init(
                title: String(localized: "Snooze Overdue Tasks"),
                description: String(localized: "Manually snooze notifications for overdue tasks without changing the original task deadline."),
                icon: "clock.arrow.circlepath",
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
            ),

        .init(
            title: String(localized:"Backup & Restore"),
            description: String(localized:"Create complete backups including tasks, reminders, attachments, cards, tickets, trip lists, documents, Vault items, and app settings. Vault data in a backup requires a password for restoration. Restore everything or only selected sections on the same or another device."),
            icon: "externaldrive.badge.timemachine",
            tint: .indigo
        ),
        .init(
            title: String(localized:"Settings Backup"),
            description: String(localized:"Your appearance preferences, navigation settings, weather options, badge settings and other supported preferences can be included in backups and restored independently from your data."),
            icon: "gearshape.2",
            tint: .gray
        )
    ]
    
    private var steps: [AppQuickGuide] { Self.stepsData }
    
    // MARK: - UI
    
    var body: some View {
        ZStack {

            AppGlassBackground()

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
