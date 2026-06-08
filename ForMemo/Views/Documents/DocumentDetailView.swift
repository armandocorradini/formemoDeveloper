import SwiftUI
import SwiftData

struct DocumentDetailView: View {

    @Bindable var document: DocumentItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isNameFocused: Bool

    var body: some View {
        
        ZStack {

            AppGlassBackground()

            Form {
            
            Section {
                
                TextField(
                    String(localized: "Name"),
                    text: $document.name
                )
                .focused($isNameFocused)
                
                Picker(
                    String(localized: "Document Type"),
                    selection: $document.documentTypeRaw
                ) {
                    Label(
                        String(localized: DocumentType.other.localizedTitle),
                        systemImage: DocumentType.other.systemImage
                    )
                    .tag(DocumentType.other.rawValue)
                    
                    Divider()
                    
                    ForEach(
                        DocumentType.localizedSortedCases.filter { $0 != .other },
                        id: \.rawValue
                    ) { type in
                        Label(
                            String(localized: type.localizedTitle),
                            systemImage: type.systemImage
                        )
                        .tag(type.rawValue)
                    }
                }
                .pickerStyle(.automatic)
                .onChange(of: document.documentTypeRaw) { oldValue, newValue in
                    
                    guard let newType = DocumentType(rawValue: newValue) else {
                        return
                    }
                    
                    let trimmedName = document.name
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let oldAutomaticName = DocumentType(rawValue: oldValue)
                        .map { String(localized: $0.localizedTitle) }
                    
                    if trimmedName.isEmpty || trimmedName == oldAutomaticName {
                        document.name = String(localized: newType.localizedTitle)
                    }
                }
                
                TextField(
                    String(localized: "Document Number"),
                    text: $document.documentNumber
                )
            } header: {
                Text(String(localized: "Information"))
            }
            .listRowBackground(
                Color(.systemBackground).opacity(0.3)
            )
            Section {
                
                DatePicker(
                    String(localized: "Issue Date"),
                    selection: Binding(
                        get: {
                            document.issueDate ?? Date()
                        },
                        set: {
                            document.issueDate = $0
                        }
                    ),
                    displayedComponents: .date
                )
                
                DatePicker(
                    String(localized: "Expiry Date"),
                    selection: Binding(
                        get: {
                            document.expiryDate ?? Date()
                        },
                        set: {
                            var components = Calendar.current.dateComponents(
                                [.year, .month, .day],
                                from: $0
                            )
                            
                            components.hour = 8
                            components.minute = 0
                            components.second = 0
                            
                            document.expiryDate = Calendar.current.date(from: components) ?? $0
                        }
                    ),
                    displayedComponents: .date
                )
                
                if let days = document.daysRemaining {
                    
                    HStack {
                        Text(String(localized: "Days Remaining"))
                        Spacer()
                        Text("\(days)")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Toggle(
                    String(localized: "Notify Before Expiry"),
                    isOn: $document.notificationEnabled
                )
                
                if document.notificationEnabled {
                    
                    Picker(
                        String(localized: "Reminder"),
                        selection: $document.notificationDaysBefore
                    ) {
                        
                        Text(String(localized: "Same Day"))
                            .tag(0)
                        
                        ForEach(1...365, id: \.self) { day in
                            
                            Text(
                                day == 1
                                ? String(localized: "1 Day Before")
                                : "\(day) " + String(localized: "Days Before")
                            )
                            .tag(day)
                        }
                    }
                }
                
            } header: {
                Text(String(localized: "Dates"))
            }
            .listRowBackground(
                Color(.systemBackground).opacity(0.3)
            )
            
            Section {
                
                TextEditor(text: $document.notes)
                    .frame(minHeight: 120)
                
            } header: {
                Text(String(localized: "Notes"))
            }
            .listRowBackground(
                Color(.systemBackground).opacity(0.3)
            )
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 70, for: .scrollContent)
            .navigationTitle(document.name.isEmpty ? String(localized: "Document") : document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) {
                        
                        let isEmptyDocument = document.name
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        && document.documentNumber
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        && document.notes
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        
                        if isEmptyDocument {
                            modelContext.delete(document)
                            modelContext.safeSave(operation: "CancelDocument")
                        }
                        
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    
                    let canSave = !document.name
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                    && !document.documentTypeRaw
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                    
                    Button(String(localized: "Save")) {
                        
                        if document.modelContext == nil {
                            modelContext.insert(document)
                        }
                        
                        if document.notificationEnabled,
                           let expiryDate = document.expiryDate {
                            
                            NotificationManager.shared
                                .removeDocumentNotification(
                                    documentID: document.id
                                )
                            
                            let triggerDate = Calendar.current.date(
                                byAdding: .day,
                                value: -document.notificationDaysBefore,
                                to: expiryDate
                            )
                            
                            if let triggerDate {
                                Task {
                                    await NotificationManager.shared
                                        .scheduleDocumentNotification(
                                            id: document.id,
                                            title: document.name,
                                            triggerDate: triggerDate
                                        )
                                }
                            }
                            
                        } else {
                            
                            NotificationManager.shared
                                .removeDocumentNotification(
                                    documentID: document.id
                                )
                        }
                        document.updatedAt = Date()
                        modelContext.safeSave(
                            operation: "SaveDocument"
                        )

                        modelContext.processPendingChanges()

                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                let isNewDocument = document.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty

                guard isNewDocument else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isNameFocused = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DocumentDetailView(
            document: DocumentItem(name: "Passport")
        )
    }
}
