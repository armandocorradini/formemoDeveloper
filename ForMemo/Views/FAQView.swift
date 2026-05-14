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
                answer: String(localized:"ForMemo lets you create, organize, and manage tasks in a simple and intuitive way.\n\nYou can quickly create tasks, even with Siri. Attachments (photos, documents, audio) can be added directly within the app.\n\nWhen you set a due date, the app automatically schedules a notification: at the due time or in advance (from 1 to 7 days), based on your settings. You can also add a custom reminder and a location-based notification.\n\nWith reminders, you can choose when to be notified or, using Siri, let them be set automatically.\n\nYou can associate a location with a task and receive a notification when you arrive, with the option to open navigation apps to reach it.\n\nThe app offers customization options, light and dark mode, and different viewing layouts.\n\nYou can import tasks from Calendar, Apple Reminders, or CSV files, and export them to Calendar, CSV, or ICS format.\n\nAvailable in English, Italian, French, German, and Spanish.\n\nYour data stays on your device (or iCloud, if enabled). No account required and no tracking.")
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
                answer: String(localized:"Yes. All features work offline and data is stored locally on your device.")
            ),
            FAQItem(
                question: String(localized:"How do recurring tasks work?"),
                answer: String(localized:"You can set tasks to repeat daily, weekly, monthly, or yearly. When you complete a recurring task, the app automatically creates the next one based on the selected frequency, so you don’t need to recreate it manually. You can modify or stop recurrence at any time.")
            )
        ]),

        // MARK: - NOTIFICATIONS
        FAQSection(title: String(localized: "Notifications & Reminders"), items: [
            FAQItem(
                question: String(localized:"How are notifications managed?"),
                answer: String(localized:"The app schedules a notification at the task’s due time. In Settings, you can enable an automatic early notification (from 1 to 7 days before), applied to every task. You can also add a custom reminder for each task. You can also associate a location with a task and receive a notification when you arrive at that place. Only one notification is active at a time, and when it fires, the system automatically schedules the next one. Recurring tasks follow the same logic for each occurrence.")
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
            // --- ADDED FAQItems ---
            FAQItem(
                question: String(localized:"Why are my notifications not working?"),
                answer: String(localized:"Make sure notifications are enabled in iOS Settings, Focus modes are not blocking alerts, and the task has a valid date or reminder. The app only schedules notifications when they are meaningful.")
            ),
            FAQItem(
                question: String(localized:"Why do notifications seem inconsistent?"),
                answer: String(localized:"Notifications are updated dynamically. If a task changes, old notifications are removed and replaced with new ones, which can make them appear different.")
            ),
            FAQItem(
                question: String(localized:"Why do I receive notifications at unexpected times?"),
                answer: String(localized:"Notification times depend on the task date, reminder settings, and system adjustments. The app avoids past or invalid times and schedules only valid future alerts.")
            )
        ]),

        // MARK: - SNOOZE
        FAQSection(title: String(localized: "Snooze"), items: [
            FAQItem(
                question: String(localized:"How does snooze work?"),
                answer: String(localized:"Snooze delays a notification. The current alert is removed and a new one is scheduled for the selected time.")
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
            )
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
                answer: String(localized:"ForMemo supports three main Siri commands. “New ForMemo” creates a new task using natural language. “Search ForMemo” searches tasks by keyword. “Check ForMemo” reads tasks planned for a date or period such as today, tomorrow, weekends, weeks, or specific dates.")
            ),
            FAQItem(
                question: String(localized:"Can Siri search tasks by keyword?"),
                answer: String(localized:"Yes. Use commands like “Search ForMemo” followed by a keyword to find matching tasks.")
            ),
            FAQItem(
                question: String(localized:"Can Siri read tasks for a specific date or period?"),
                answer: String(localized:"Yes. Use “Check ForMemo” and say periods like today, tomorrow, this week, next week, weekend, next weekend, or a specific date.")
            )
        ]),

        // MARK: - ATTACHMENTS / COMPLETED TASKS
        FAQSection(title: String(localized: "Completed Tasks & Attachments"), items: [
            FAQItem(
                question: String(localized:"Can I add attachments to tasks?"),
                answer: String(localized:"Yes. You can attach files, images, documents, and record audio.")
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
