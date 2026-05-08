import SwiftUI
import SwiftData
import CoreLocation


// MARK: - contextSection
 struct ContextSection: View {

    @Bindable var task: TodoTask
    @Query private var allTasks: [TodoTask]

    @AppStorage("hiddenSavedLocations")
    private var hiddenSavedLocationsData: Data = Data()

    let navigationApp: NavigationApp
    let showingDeleteConfirmation: Binding<Bool>
    let showingLocationPicker: Binding<Bool>
    let saveTask: () -> Void
    let openNavigation: (CLLocationCoordinate2D, String) -> Void

    private var hiddenSavedLocations: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: hiddenSavedLocationsData)) ?? []
    }

    private func hideSavedLocation(_ item: SavedLocationItem) {
        let key = "\(item.name.lowercased())|\(item.latitude)|\(item.longitude)"

        var hidden = hiddenSavedLocations
        hidden.insert(key)

        hiddenSavedLocationsData = (try? JSONEncoder().encode(hidden)) ?? Data()
    }

    private var savedLocations: [SavedLocationItem] {

        var seen = Set<String>()

        return allTasks.compactMap { task in

            guard let name = task.locationName,
                  let latitude = task.locationLatitude,
                  let longitude = task.locationLongitude else {
                return nil
            }

            let key = "\(name.lowercased())|\(latitude)|\(longitude)"

            guard !seen.contains(key),
                  !hiddenSavedLocations.contains(key) else {
                return nil
            }

            seen.insert(key)

            return SavedLocationItem(
                name: name,
                latitude: latitude,
                longitude: longitude
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

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

                if !savedLocations.isEmpty {

                    NavigationLink {
                        SavedLocationsListView(
                            locations: savedLocations,
                            onSelect: { item in
                                task.locationName = item.name
                                task.locationLatitude = item.latitude
                                task.locationLongitude = item.longitude
                                saveTask()
                            },
                            onDelete: { item in
                                hideSavedLocation(item)
                            }
                        )
                    } label: {
                        Label(
                            String(localized: "Choose saved location"),
                            systemImage: "mappin.circle"
                        )
                    }
                }
            }

            if task.locationLatitude != nil && task.locationLongitude != nil {
                let canUseLocationReminders =
                    UserDefaults.standard.bool(forKey: "locationRemindersEnabled")
                    && CLLocationManager().authorizationStatus == .authorizedAlways

                VStack(alignment: .leading) {

                    Toggle("Location Reminder", isOn: Binding(
                        get: { task.locationReminderEnabled },
                        set: { newValue in
                            task.locationReminderEnabled = newValue
                            saveTask()
                        }
                    ))
                    .disabled(!canUseLocationReminders)
                    .opacity(canUseLocationReminders ? 1 : 0.4)

                    if !canUseLocationReminders {
                        Text("Location reminders require \"Always Allow\" location access and must be enabled in Settings.")
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
