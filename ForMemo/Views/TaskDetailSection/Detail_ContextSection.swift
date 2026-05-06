
import SwiftUI
import SwiftData
import CoreLocation



// MARK: - contextSection
 struct ContextSection: View {

    @Bindable var task: TodoTask

    let navigationApp: NavigationApp
    let showingDeleteConfirmation: Binding<Bool>
    let showingLocationPicker: Binding<Bool>
    let saveTask: () -> Void
    let openNavigation: (CLLocationCoordinate2D, String) -> Void

    var body: some View {

        Section("Context") {

            if let name = task.locationName,
               let coordinate = task.locationCoordinate {

                HStack {

                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.blue)

                    Text(name)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        openNavigation(coordinate, name)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        showingDeleteConfirmation.wrappedValue = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .confirmationDialog(
                        "Remove location?",
                        isPresented: showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Remove", role: .destructive) {
                            task.locationName = nil
                            task.locationLatitude = nil
                            task.locationLongitude = nil
                            saveTask()
                        }

                        Button("Cancel") { }
                    }
                }

            } else {

                HStack {

                    Text("No location set")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showingLocationPicker.wrappedValue = true
                    } label: {
                        Label("", systemImage: "mappin.and.ellipse")
                    }
                }
            }

            if task.locationLatitude != nil && task.locationLongitude != nil {
                let isGlobalEnabled = UserDefaults.standard.bool(forKey: "locationRemindersEnabled")

                VStack(alignment: .leading) {

                    Toggle("Location Reminder", isOn: Binding(
                        get: { task.locationReminderEnabled },
                        set: { newValue in
                            task.locationReminderEnabled = newValue
                            saveTask()
                        }
                    ))
                    .disabled(!isGlobalEnabled)
                    .opacity(isGlobalEnabled ? 1 : 0.4)

                    if !isGlobalEnabled {
                        Text("Enable Location Reminders in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
            }

            Picker(
                String(localized: "Tags"),
                selection: Binding<TaskMainTag?>(
                    get: { task.mainTag },
                    set: { task.mainTag = $0 }
                )
            ) {

                Text("None")
                    .tag(TaskMainTag?.none)

                ForEach(TaskMainTag.allCases) { tag in
                    Label(tag.localizedTitle, systemImage: tag.mainIcon)
                        .tag(Optional(tag))
                }
            }
            .pickerStyle(.menu)
        }
        .listRowBackground(Color(.systemBackground).opacity(0.3))
    }
}
