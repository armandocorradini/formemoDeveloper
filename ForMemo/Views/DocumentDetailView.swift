import SwiftUI
import SwiftData
import os
import UniformTypeIdentifiers
import PhotosUI

struct DocumentDetailView: View {

    @Bindable var document: DocumentItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isNameFocused: Bool

    @State private var showingAddAssetMenu = false
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingPDFImporter = false
    
    @State private var selectedAsset: DocumentAsset?
    
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
                
                LabeledContent(String(localized: "Stored in: ")) {
                    TextField(
                        "",
                        text: $document.storageLocation,
                        prompt: Text(String(localized: "storage location"))
                        

                    )
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                }
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

                    if document.sortedAssets.isEmpty {

                        ContentUnavailableView(
                            String(localized: "No Pages"),
                            systemImage: "doc.viewfinder",
                            description: Text(
                                String(localized: "Add photos, scans or PDFs to this document.")
                            )
                        )

                    } else {

                        ScrollView(.horizontal) {

                            LazyHStack(spacing: 12) {

                                ForEach(document.sortedAssets) { asset in

                                    Button {

                                        selectedAsset = asset

                                    } label: {

                                        DocumentAssetThumbnail(
                                            asset: asset
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: 130)

                    }

                    Button {

                        showingAddAssetMenu = true

                    } label: {

                        Label(
                            String(localized: "Add"),
                            systemImage: "plus.circle.fill"
                        )
                    }

                } header: {

                    Text(String(localized: "Document"))

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
                        && document.storageLocation
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
                document.lastOpenedAt = .now
                modelContext.safeSave(operation: "UpdateDocumentLastOpened")
                let isNewDocument = document.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty

                guard isNewDocument else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isNameFocused = true
                }
            }
            
            .confirmationDialog(
                String(localized: "Add to Document"),
                isPresented: $showingAddAssetMenu
            ) {

                Button(String(localized: "Take Photo")) {
                    showingCamera = true
                }

                Button(String(localized: "Scan Document")) {
                    showingScanner = true
                }

                Button(String(localized: "Choose Photo")) {
                    showingPhotoPicker = true
                }

                Button(String(localized: "Import PDF")) {
                    showingPDFImporter = true
                }

                Button(
                    String(localized: "Cancel"),
                    role: .cancel
                ) { }

            }
            .sheet(isPresented: $showingCamera) {

                CameraPicker { image in

                    do {

                        try DocumentImportService.importImages(
                            [image],
                            into: document,
                            in: modelContext
                        )

                    } catch {

                        AppLogger.ui.error(
                            "Camera import failed: \(error.localizedDescription)"
                        )
                    }
                }
            }
            
            .sheet(isPresented: $showingScanner) {

                DocumentScannerView { images in

                    do {

                        try DocumentImportService.importImages(
                            images,
                            into: document,
                            in: modelContext
                        )

                    } catch {

                        AppLogger.ui.error(
                            "Scanner import failed: \(error.localizedDescription)"
                        )
                    }
                }
            }
            
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotos,
                maxSelectionCount: nil,
                matching: .images
            )
            .onChange(of: selectedPhotos) {

                Task {

                    var images: [UIImage] = []

                    for item in selectedPhotos {

                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {

                            images.append(image)
                        }
                    }

                    guard !images.isEmpty else {
                        return
                    }

                    do {

                        try DocumentImportService.importImages(
                            images,
                            into: document,
                            in: modelContext
                        )

                    } catch {

                        AppLogger.ui.error(
                            "Photo import failed: \(error.localizedDescription)"
                        )
                    }

                    selectedPhotos.removeAll()
                }
            }
            
            .fullScreenCover(item: $selectedAsset) { asset in

                DocumentAssetDetailView(
                    document: document,
                    asset: asset
                )
            }
            
            
            .fileImporter(
                isPresented: $showingPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in

                do {

                    guard let url = try result.get().first else {
                        return
                    }

                    try DocumentImportService.importPDF(
                        from: url,
                        into: document,
                        in: modelContext
                    )

                } catch {

                    AppLogger.ui.error(
                        "PDF import failed: \(error.localizedDescription)"
                    )
                }
            }
            
        }
    }
}
