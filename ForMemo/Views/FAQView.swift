import Foundation
import SwiftUI

// MARK: - FAQ View
struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}
struct FAQSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [FAQItem]
}

struct FAQView: View {
    
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - DATA
    private let sections: [FAQSection] = [

        // MARK: - GENERAL
        FAQSection(title: String(localized: "General"), items: [
            FAQItem(
                question: String(localized:"What features does this app offer?"),
                answer: String(localized:"ForMemo lets you create, organize, and manage tasks in a simple and intuitive way.\n\nYou can quickly create tasks, even with Siri. Attachments (photos, documents, audio) can be added directly within the app.\n\nWhen you set a due date, the app automatically schedules a notification: at the due time or in advance (from 1 to 7 days), based on your settings. You can also add a custom reminder and a location-based notification.\n\nWith reminders, you can choose when to be notified or, using Siri, let them be set automatically.\n\nYou can associate a location with a task and receive a notification when you arrive, with the option to open navigation apps to reach it.\n\nThe app offers customization options, light and dark mode, and different viewing layouts.\n\nYou can import tasks from Calendar, Apple Reminders, or CSV files, and export them to Calendar, CSV, or ICS format.\n\nThe app also includes a Wallet section for loyalty cards and tickets, with barcode and QR code scanning and quick access to your saved items.\n\nYou can create and manage Trip Lists (packing lists) for your travels, and keep track of important documents and their expiration dates in the Documents section. You can attach photos, documents, PDFs, audio recordings, and scanned pages directly to tasks.\n\nWeather forecasts are integrated, including detailed weekly and hourly views to help you plan your activities.\n\nComplete backup and restore is available, including tasks, reminders, attachments, cards, tickets, trips, documents, and app settings.\n\nAvailable in English, Italian, French, German, and Spanish.\n\nYour data stays on your device (or iCloud, if enabled). No account required and no tracking.")
            ),
            FAQItem(
                question: String(localized:"What is the Dashboard?"),
                answer: String(localized:"The Dashboard gives you a quick overview of what needs your attention. It highlights overdue tasks, tasks due today, upcoming activities, weather forecasts, and recently opened items from Wallet, Documents, and Trip Lists, helping you access important information from a single screen.")
            ),
            FAQItem(
                question: String(localized:"What is the Overview?"),
                answer: String(localized:"Overview gives you a quick summary of the information that matters most. It provides an at-a-glance view of your tasks, documents, Wallet items, trip lists, and other useful information, helping you quickly understand the current status of your data.")
            ),
            FAQItem(
                question: String(localized:"How does task creation work?"),
                answer: String(localized:"You can create tasks manually or with Siri. When using Siri, you are guided step by step: first what to add, then when, and finally which reminder to set. The app saves the task using the information you provide.")
            ),
            FAQItem(
                question: String(localized:"How are tags assigned automatically?"),
                answer: String(localized:"This feature applies only to tasks created with Siri. The app analyzes the task title using a multilingual keyword system. Each category has its own keywords, and the best match is applied automatically.")
            ),
            FAQItem(
                question: String(localized:"Does the app work offline?"),
                answer: String(localized:"Most features work offline. Weather forecasts, cloud synchronization, and some online services require an internet connection.")
            ),
            FAQItem(
                question: String(localized:"Can I organize travel packing lists?"),
                answer: String(localized:"Yes. The Trips section lets you create and manage packing lists for your travels.")
            ),
            FAQItem(
                question: String(localized:"What is the Documents section used for?"),
                answer: String(localized:"The Documents section helps you keep track of important documents and their expiration dates. You can store document details, issue dates, expiry dates, notes, and receive reminders before a document expires.")
            ),
            FAQItem(
                question: String(localized:"How do recurring tasks work?"),
                answer: String(localized:"You can set tasks to repeat hourly, daily, weekly, monthly, or yearly. When you complete a recurring task, the app automatically creates the next one based on the selected frequency, so you don’t need to recreate it manually. You can modify or stop recurrence at any time.")
            ),
            FAQItem(
                question: String(localized:"Does the app include weather forecasts?"),
                answer: String(localized:"Yes. ForMemo can display weather forecasts directly inside task views and weekly planning views to help you organize your activities more easily. Tap the weather info to open the detailed weekly weather forecast view.")
            ),
            FAQItem(
                question: String(localized:"Can I view hourly weather conditions?"),
                answer: String(localized:"Yes. The detailed forecast view includes weather conditions throughout the day to help you better plan your activities.")
            ),
            FAQItem(
                question: String(localized:"Why is weather information different from other weather apps?"),
                answer: String(localized:"Weather data is provided by Open-Meteo. Different weather providers may use different forecasting models and update schedules.")
            ),
            FAQItem(
                question: String(localized:"Do weather forecasts require location access?"),
                answer: String(localized:"Yes. Weather forecasts depend on your device location. If location access is disabled, weather information may not be available.")
            ),
            FAQItem(
                question: String(localized:"Does the app include a Wallet for cards and tickets?"),
                answer: String(localized:"Yes. ForMemo includes a Wallet section where you can save and organize loyalty cards and tickets, barcodes, QR codes, holder information, notes, custom colors, and optional logos.")
            ),
            FAQItem(
                question: String(localized:"Can I scan cards and tickets with the camera?"),
                answer: String(localized:"Yes. You can quickly scan barcodes and QR codes using the device camera and save cards and tickets directly inside the Wallet. Tickets can also be imported from images containing supported codes.")
            )
        ]),

        // MARK: - NOTIFICATIONS
        FAQSection(title: String(localized: "Notifications & Reminders"), items: [
            FAQItem(
                question: String(localized:"How are notifications managed?"),
                answer: String(localized:"The app schedules a notification at the task’s due time. In Settings, you can enable an automatic early notification (from 1 to 7 days before), applied to every task. You can also add a custom reminder for each task. You can also associate a location with a task and receive a notification when you arrive at that place. Only one notification is active at a time, and when it fires, the system automatically schedules the next one. Recurring tasks follow the same logic for each occurrence.")
            ),
            FAQItem(
                question: String(localized:"Does every task generate a notification when it becomes overdue?"),
                answer: String(localized:"Yes. Every task with a due date automatically generates a notification when it reaches its deadline. You can also add custom reminders, location reminders, and advance notifications.")
            ),
            FAQItem(
                question: String(localized:"What is the difference between a due date notification and a reminder?"),
                answer: String(localized:"The due date notification is automatically generated when a task reaches its deadline. Reminders are optional notifications that can occur before the deadline at a time you choose.")
            ),
            FAQItem(
                question: String(localized:"Why am I not receiving notifications?"),
                answer: String(localized:"Check system permissions, Focus modes, and app settings. Notifications are only scheduled when valid and allowed.")
            ),
            FAQItem(
                question: String(localized:"Why did a notification disappear?"),
                answer: String(localized:"It may no longer be relevant. If a task changes, old notifications are removed and replaced with updated ones if needed.")
            ),
            FAQItem(
                question: String(localized:"Why do I receive fewer notifications than expected?"),
                answer: String(localized:"The app avoids duplicates, past alerts, and night-time notifications to reduce noise.")
            ),
            FAQItem(
                question: String(localized:"Why do I receive notifications at unexpected times?"),
                answer: String(localized:"Notification times depend on the task date, reminder settings, and system adjustments. The app avoids past or invalid times and schedules only valid future alerts.")
            ),
            FAQItem(
                question: String(localized:"Can Siri read notifications from the app?"),
                answer: String(localized:"Yes. If Siri notification announcements are enabled in iOS Settings, Siri can read ForMemo notifications aloud on supported devices such as AirPods or CarPlay.")
            )
        ]),

        // MARK: - SNOOZE
        FAQSection(title: String(localized: "Snooze"), items: [
            FAQItem(
                question: String(localized:"How does snooze work?"),
                answer: String(localized:"Snooze delays a notification. The current alert is removed and a new one is scheduled for the selected time.")
            ),
            FAQItem(
                question: String(localized:"Can I snooze an overdue task?"),
                answer: String(localized:"Yes. If a task is already overdue, you can manually snooze its notification by choosing one of the available time intervals. Unlike Reschedule, Snooze does not change the task deadline—it only postpones the notification.")
            ),
            FAQItem(
                question: String(localized:"What is reschedule and how is it different from snooze?"),
                answer: String(localized:"Reschedule changes the task deadline itself by moving it to a new date or time. Snooze only delays the current notification without changing the original deadline. Reschedule is useful when plans change, while snooze is meant for temporary delays.")
            ),
            FAQItem(
                question: String(localized:"Why does snooze seem to disappear?"),
                answer: String(localized:"Snooze is temporary. Once its time passes or the task changes, it is no longer shown.")
            ),
            FAQItem(
                question: String(localized:"Why did my snooze not trigger?"),
                answer: String(localized:"Snooze follows specific rules. For reminders and early notifications, snooze is ignored if it would go beyond the task’s deadline. For deadline notifications, snooze is always applied and triggers at the selected time. If a snooze seems missing, it was ignored to respect the deadline.")
            )
        ]),

        // MARK: - BADGE
        FAQSection(title: String(localized: "Badges & Indicators"), items: [
            FAQItem(
                question: String(localized:"How is the app badge calculated?"),
                answer: String(localized:"The app badge shows tasks that require attention based on the selected badge mode. In Settings > General, you can choose whether the badge updates only when tasks become overdue or before the deadline, at the moment the global notification is triggered. The badge updates automatically even if the app is closed.")
            ),
            FAQItem(
                question: String(localized:"Why does the badge change suddenly?"),
                answer: String(localized:"The badge is dynamic and updates based on time, deadlines, and task status.")
            ),
            FAQItem(
                question: String(localized:"What do badges in task rows mean?"),
                answer: String(localized:"They indicate the task status, for example if it is approaching its deadline, but only if a priority is set.")
            ),
            FAQItem(
                question: String(localized:"Can I filter tasks without a deadline?"),
                answer: String(localized:"Yes. Open the Filters menu and select No Deadline to display only tasks that do not have a due date assigned.")
            ),
            FAQItem(
                question: String(localized:"Can I combine multiple filters?"),
                answer: String(localized:"Yes. You can combine category, priority, due date period, and other filters to quickly focus on the tasks that matter most.")
            ),
            FAQItem(
                question: String(localized:"What are Powerful Filters?"),
                answer: String(localized:"Powerful Filters help you quickly find tasks by category, priority, due date period, overdue status, or tasks without a deadline. Multiple filters can be combined at the same time.")
            ),
            // --- ADDED FAQItems ---
            FAQItem(
                question: String(localized:"Why is the badge not updating?"),
                answer: String(localized:"The badge updates automatically based on task changes and time. If it seems incorrect, try reopening the app or checking your notification settings.")
            ),
            FAQItem(
                question: String(localized:"What is the difference between badge modes?"),
                answer: String(localized:"At deadline updates the badge only when tasks become overdue. With global notification, the badge instead updates at the exact same moment the advance global notification is triggered. You can change this behavior anytime in Settings > General.")
            ),
            FAQItem(
                question: String(localized:"Can I choose how the app badge works?"),
                answer: String(localized:"Yes. In Settings > General, you can choose whether the badge counts overdue tasks or tasks that reached the global notification time.")
            ),
            FAQItem(
                question: String(localized:"Why is the badge different from what I expect?"),
                answer: String(localized:"The badge behavior depends on the selected mode. In classic mode, tasks appear in the badge only after their deadline has passed. In global notification mode, tasks can appear earlier, when the advance notification is triggered.")
            ),
            // --- BEGIN NEW FAQItems ---
            FAQItem(
                question: String(localized:"Why are some tasks highlighted?"),
                answer: String(localized:"Tasks with critical priority that are due today or overdue are highlighted to help you quickly identify the most urgent items.")
            ),
            FAQItem(
                question: String(localized:"Can I disable the highlight for critical tasks?"),
                answer: String(localized:"Yes. You can customize the highlight in Customize > Appearance by adjusting color and opacity, or disable it in Visible elements.")
            ),
            FAQItem(
                question: String(localized:"Can I view tasks on a map?"),
                answer: String(localized:"Yes. Tasks with a location are shown as pins on the map. Tap a pin to open task details.")
            ),
            FAQItem(
                question: String(localized:"Does the map adjust zoom automatically?"),
                answer: String(localized:"The map automatically adjusts to show all tasks when it opens. After that, your zoom level is preserved.")
            ),
            FAQItem(
                question: String(localized:"Can I customize task highlighting?"),
                answer: String(localized:"Yes. You can choose both color and opacity for highlighting critical tasks in Settings.")
            ),
            FAQItem(
                question: String(localized:"Can I customize the appearance of task rows?"),
                answer: String(localized:"Yes. You can personalize task rows by choosing different styles, rounded corners, borders, and materials to match your preferred appearance.")
            ),
            // --- END NEW FAQItems ---
        ]),

        // MARK: - LOCATION
        FAQSection(title: String(localized: "Location Reminders"), items: [
            FAQItem(
                question: String(localized:"How do location reminders work?"),
                answer: String(localized:"The app reminds you when you arrive at a place. It focuses on the most relevant tasks based on distance and timing.")
            ),
            FAQItem(
                question: String(localized:"Why is a location task not monitored?"),
                answer: String(localized:"iOS limits monitored regions, so only top-priority tasks are active.")
            ),
            FAQItem(
                question: String(localized:"Why does a location reminder not trigger?"),
                answer: String(localized:"Check permissions, accuracy, and whether the task is actively monitored.")
            ),
            // --- ADDED FAQItem ---
            FAQItem(
                question: String(localized:"Why does location reminder not trigger when I arrive?"),
                answer: String(localized:"Location accuracy, permissions, or system limits may affect this. Make sure location access is set to Always and that the task is actively monitored.")
            ),
            FAQItem(
                question: String(localized:"Can I open navigation apps from a task?"),
                answer: String(localized:"Yes. Tasks with a saved location can be opened directly in supported navigation apps.")
            ),
            FAQItem(
                question: String(localized:"Why is weather information not visible?"),
                answer: String(localized:"Weather information requires location access. Make sure location permissions are enabled and weather forecasts are activated in app settings.")
            )
        ]),

        // MARK: - SIRI & AUTOMATIONS
        FAQSection(title: String(localized: "Siri & Automations"), items: [
            FAQItem(
                question: String(localized:"What is “Add reminders automatically”?"),
                answer: String(localized:"When using Siri, if “Add reminders automatically” is enabled, Siri adds a reminder automatically based on the task. If disabled, Siri will ask you which reminder to set.")
            ),
            FAQItem(
                question: String(localized:"How can I use Siri with ForMemo?"),
                answer: String(localized:"ForMemo supports three main Siri commands:\n\n• “New ForMemo” creates a new task using natural language. The app can automatically assign a category and reminder based on your task title and deadline.\n• “Search ForMemo” lets you search tasks by keyword.\n• “Check ForMemo” reads tasks planned for a date or period such as today, tomorrow, weekends, weeks, or specific dates.\n\nAutomatic category and reminder assignment can be enabled in Settings for Siri-created tasks.")
            ),
            FAQItem(
                question: String(localized:"Can Siri search tasks by keyword?"),
                answer: String(localized:"Yes. Use commands like “Search ForMemo” followed by a keyword to find matching tasks.")
            ),
            FAQItem(
                question: String(localized:"Can Siri read tasks for a specific date or period?"),
                answer: String(localized:"Yes. Use “Check ForMemo” and say periods like today, tomorrow, this week, next week, weekend, next weekend, or a specific date.")
            ),
            FAQItem(
                question: String(localized:"Can Siri automatically assign categories?"),
                answer: String(localized:"Yes. Tasks created with Siri can automatically receive a category based on the task title.")
            ),
            FAQItem(
                question: String(localized:"Can Siri automatically add reminders?"),
                answer: String(localized:"Yes. If enabled in Settings, Siri can automatically add reminders based on the task deadline.")
            )
        ]),

        // MARK: - ATTACHMENTS / COMPLETED TASKS
        FAQSection(title: String(localized: "Completed Tasks & Attachments"), items: [
            FAQItem(
                question: String(localized:"Can I add attachments to tasks?"),
                answer: String(localized:"Yes. You can attach files, images, documents, and record audio.")
            ),
            FAQItem(
                question: String(localized:"Which file types can I attach?"),
                answer: String(localized:"You can attach photos, scanned documents, files, PDFs, and audio recordings.")
            ),
            FAQItem(
                question: String(localized:"Can I record audio directly from the app?"),
                answer: String(localized:"Yes. Audio recordings can be attached directly to tasks.")
            ),
            FAQItem(
                question: String(localized:"Can I scan documents and attach them to tasks?"),
                answer: String(localized:"Yes. You can use your device camera to scan pages and attach them directly to a task.")
            ),
            FAQItem(
                question: String(localized:"Are attachments deleted automatically?"),
                answer: String(localized:"Only attachments of completed tasks are deleted automatically if the option is enabled in settings.")
            ),
            FAQItem(
                question: String(localized:"After how many days are attachments deleted?"),
                answer: String(localized:"You can choose after how many days attachments of completed tasks are automatically removed.")
            ),
            FAQItem(
                question: String(localized:"Can I delete all attachments at once?"),
                answer: String(localized:"Yes. You can manually delete all attachments of completed tasks from settings.")
            ),
            FAQItem(
                question: String(localized:"Can I save multiple cards or tickets from the same provider?"),
                answer: String(localized:"Yes. You can save multiple cards or tickets from the same store, event, or provider and distinguish them using the holder field or custom notes.")
            )
        ]),

        // MARK: - DOCUMENTS & TRIPS
        FAQSection(title: String(localized: "Documents & Trips"), items: [
            FAQItem(
                question: String(localized:"What is the Documents section?"),
                answer: String(localized:"The Documents section helps you keep track of important documents and their expiration dates. You can store document details, issue dates, expiry dates, notes, and receive reminders before a document expires.")
            ),
            FAQItem(
                question: String(localized:"Can I save where a document is physically stored?"),
                answer: String(localized:"Yes. For each document you can record its physical storage location, such as a drawer, cabinet, folder, or safe. This helps you quickly find the original document whenever you need it.")
            ),
            FAQItem(
                question: String(localized:"Can I receive reminders before a document expires?"),
                answer: String(localized:"Yes. You can enable a reminder and choose how many days before the expiration date you want to be notified.")
            ),
            FAQItem(
                question: String(localized:"What are Trip Lists?"),
                answer: String(localized:"Trip Lists help you organize everything you need to take with you on your travels. You can create them from scratch or start from a template, organize them into sections, and mark items as completed as you prepare them.")
            ),
            FAQItem(
                question: String(localized:"Are Trip Lists synchronized and backed up?"),
                answer: String(localized:"Yes. Trip Lists, sections, items and templates are synchronized with iCloud if enabled and included in manual backups.")
            )
        ]),
        // MARK: - DATA
        FAQSection(title: String(localized: "Data & Recovery"), items: [
            FAQItem(
                question: String(localized:"What is Recently Deleted?"),
                answer: String(localized:"Deleted items are temporarily stored and can be restored before permanent removal.")
            ),
            FAQItem(
                question: String(localized:"Why do things change automatically?"),
                answer: String(localized:"The app reacts to time, task updates, and system events to keep everything consistent.")
            ),
            FAQItem(
                question: String(localized:"Does the app support backup and restore?"),
                answer: String(localized:"Yes. ForMemo allows you to create complete backups that include tasks, reminders, attachments, cards, tickets and logos, trip lists, documents, app settings, and related data. You can restore them later or transfer everything to another device.")
            ),
            FAQItem(
                question: String(localized:"What is included in a backup?"),
                answer: String(localized:"Backups include tasks, reminders, recurrence rules, tags, priorities, locations, attachments, cards, tickets and logos, trip lists, documents, and app settings. Backups are independent from iCloud sync and can be used to transfer data to another device.")
            ),
            FAQItem(
                question: String(localized:"Are attachments included in backups?"),
                answer: String(localized:"Yes. Complete backups include task attachments such as images, documents, scans, and audio recordings.")
            ),
            FAQItem(
                question: String(localized:"Are trip lists included in backups?"),
                answer: String(localized:"Yes. Trip lists, sections, items and templates are included in backups.")
            ),
            FAQItem(
                question: String(localized:"Are documents included in backups?"),
                answer: String(localized:"Yes. Document records, expiry dates, notes, and reminder settings stored in the Documents section are included in backups.")
            ),
            FAQItem(
                question: String(localized:"Can I restore backups on another device?"),
                answer: String(localized:"Yes. You can import a backup file on another compatible device to restore your tasks, cards, tickets, attachments, trips, documents, and related data.")
            ),
            FAQItem(
                question: String(localized:"Can I restore only specific data from a backup?"),
                answer: String(localized:"Yes. During restore, you can choose which sections to restore, such as tasks, cards, tickets, trip lists, documents, and app settings. This allows you to recover only the data you need without restoring everything.")
            ),
            FAQItem(
                question: String(localized:"Can I transfer my data to another device?"),
                answer: String(localized:"Yes. You can restore a backup on another compatible device and continue using your data.")
            ),
            FAQItem(
                question: String(localized:"Are cards and tickets included in backups?"),
                answer: String(localized:"Yes. Cards, tickets, barcodes, QR codes, notes, custom colors, and logos are included in backups and can be restored on compatible devices.")
            ),
            FAQItem(
                question: String(localized:"Does iCloud replace backups?"),
                answer: String(localized:"No. iCloud synchronization and manual backups are separate features. Backups are still recommended for additional safety and portability.")
            ),
            FAQItem(
                question: String(localized:"Are app settings included in backups?"),
                answer: String(localized:"Yes. Backups can include app settings such as appearance preferences, navigation preferences, weather settings, badge options, attachment management settings, and other supported preferences. During restore, app settings can be restored separately from your data.")
            )
        ])
    ]
    
    // MARK: - FILTER
    
    private var filteredSections: [FAQSection] {
        if searchText.isEmpty { return sections }
        
        return sections.compactMap { section in
            let filteredItems = section.items.filter {
                $0.question.localizedCaseInsensitiveContains(searchText)
                || $0.answer.localizedCaseInsensitiveContains(searchText)
            }
            return filteredItems.isEmpty ? nil : FAQSection(title: section.title, items: filteredItems)
        }
    }

    // MARK: - HIGHLIGHT

    private func highlight(_ text: String) -> Text {
        guard !searchText.isEmpty else { return Text(text) }

        var attributed = AttributedString(text)

        if let range = attributed.range(of: searchText, options: .caseInsensitive) {
            attributed[range].foregroundColor = .blue
            attributed[range].font = .body.bold()
        }

        return Text(attributed)
    }

    // MARK: - UI

    var body: some View {
        ZStack {
            AppGlassBackground()
            List {
                ForEach(filteredSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            DisclosureGroup {
                                Text(item.answer)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            } label: {
                                highlight(item.question)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search FAQ")
            )
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(String(localized: "Help"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
    // MARK: - DETAIL VIEW

    struct FAQDetailView: View {
        
        let item: FAQItem
        
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    Text(item.question)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(item.answer)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(String(localized:"FAQ"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
