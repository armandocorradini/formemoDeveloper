import SwiftUI
import SwiftData
import CoreLocation
import os


// MARK: - contextSection
 struct ContextSection: View {

     
     @Environment(\.modelContext) private var modelContext
     
    @Bindable var task: TodoTask
     @State private var savedLocations: [SavedLocationItem] = []

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

     @MainActor
     private func loadSavedLocations() {
         let descriptor = FetchDescriptor<TodoTask>(
             predicate: #Predicate<TodoTask> {
                 $0.locationName != nil &&
                 $0.locationLatitude != nil &&
                 $0.locationLongitude != nil
             }
         )

         do {
             let tasks = try modelContext.fetch(descriptor)

             var seen = Set<String>()
             var locations: [SavedLocationItem] = []

             locations.reserveCapacity(tasks.count)

             for task in tasks {
                 guard
                     let name = task.locationName,
                     let latitude = task.locationLatitude,
                     let longitude = task.locationLongitude
                 else {
                     continue
                 }

                 let key = "\(name.lowercased())|\(latitude)|\(longitude)"

                 guard !seen.contains(key),
                       !hiddenSavedLocations.contains(key)
                 else {
                     continue
                 }

                 seen.insert(key)

                 locations.append(
                     SavedLocationItem(
                         name: name,
                         latitude: latitude,
                         longitude: longitude
                     )
                 )
             }

             locations.sort {
                 $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
             }

             savedLocations = locations

         } catch {
             AppLogger.persistence.error(
                 "Saved locations fetch failed: \(error.localizedDescription)"
             )
             savedLocations = []
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
                    set: {
                        task.mainTag = $0
                        saveTask()
                    }
                )
            ) {

                Text("None")
                    .tag(TaskMainTag?.none)

                ForEach(TaskMainTag.localizedSortedCases) { tag in
                    Label(tag.localizedTitle, systemImage: tag.mainIcon)
                        .tag(Optional(tag))
                }
            }
            .pickerStyle(.menu)
        }
        .listRowBackground(Color(.systemBackground).opacity(0.3))
    
         .task {
             loadSavedLocations()
         }
        }
     }
