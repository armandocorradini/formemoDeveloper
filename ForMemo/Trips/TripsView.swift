import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Observation

@Observable
final class TripClipboard {

    static let shared = TripClipboard()

    var copiedSection: TripSectionData?
}

// MARK: - Main View

struct ChecklistListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    @Query(sort: \TripList.sortOrder)
    private var categories: [TripList]
    
    @State private var showNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var selectedIcon = "list.bullet.clipboard"
    @State private var showNewCategorySheet = false
    @State private var editingCategory: TripList?
    @State private var isEditingCategory = false
    @State private var searchText = ""
    @State private var showImportPicker = false
    @State private var showExportSheet = false
    @State private var exportIncludeChecks = true
    @State private var exportDocument: FMTripDocument?
    @State private var categoryToExport: TripList?

    private var visibleCategories: [TripList] {

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return categories
        }

        return categories.filter {
            localizedTripText($0.name)
                .localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func moveCategories(from source: IndexSet, to destination: Int) {

        var reordered = categories

        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }

        try? modelContext.save()
    }
    
    var body: some View {

        ZStack {

            AppGlassBackground()

            NavigationStack {
            
            List {
                
                if visibleCategories.isEmpty {
                    
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Checklists"),
                            systemImage: "list.bullet.clipboard"
                        )
                    } description: {
                        Text(
                            String(localized: "Tap + to start with a template or create your own checklist")
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                
                ForEach(visibleCategories) { category in
                    
                    NavigationLink {
                        ChecklistView(category: category)
                    } label: {
                        
                        HStack(spacing: 14) {
                            
                            Image(systemName: category.icon)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    tripIconColors(for: category.icon).0,
                                    tripIconColors(for: category.icon).1
                                )
                                .font(.title2)
                                .frame(width: 34)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                
                                let totalItems = category.sections.reduce(0) { $0 + $1.items.count }

                                let checkedItems = category.sections.reduce(0) {
                                    partialResult,
                                    section in
                                    partialResult + section.items.filter(\.isChecked).count
                                }

                                let remainingItems = max(totalItems - checkedItems, 0)
                                let isComplete = totalItems > 0 && remainingItems == 0

                                Text(localizedTripText(category.name))
                                    .font(.headline)
                                    .foregroundStyle(isComplete ? .green : .primary)

                                Text(
                                    "\(totalItems) \(String(localized: "items")) • \(remainingItems) \(String(localized: "remaining"))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button {
                                let baseName = category.name
                                var candidateName = baseName + " 2"
                                var suffix = 2

                                while categories.contains(where: {
                                    localizedTripText($0.name) == localizedTripText(candidateName)
                                }) {
                                    suffix += 1
                                    candidateName = baseName + " \(suffix)"
                                }

                                let duplicated = duplicateTripList(
                                    category,
                                    name: candidateName
                                )

                                duplicated.sortOrder = (categories.map(\.sortOrder).max() ?? 0) + 1

                                modelContext.insert(duplicated)
                                try? modelContext.save()
                            } label: {
                                Label(
                                    String(localized: "Duplicate"),
                                    systemImage: "plus.square.on.square"
                                )
                            }

                            Button {
                                editingCategory = category
                                newCategoryName = localizedTripText(category.name)
                                selectedIcon = category.icon
                                isEditingCategory = true
                                showNewCategorySheet = true
                            } label: {
                                Label(
                                    String(localized: "Edit"),
                                    systemImage: "pencil"
                                )
                            }

                            Button(role: .destructive) {
                                withAnimation {
                                    deleteTrip(category, in: modelContext)
                                }
                            } label: {
                                Label(
                                    String(localized: "Delete"),
                                    systemImage: "trash"
                                )
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                let baseName = category.name
                                var candidateName = baseName + " 2"
                                var suffix = 2

                                while categories.contains(where: {
                                    localizedTripText($0.name) == localizedTripText(candidateName)
                                }) {
                                    suffix += 1
                                    candidateName = baseName + " \(suffix)"
                                }

                                let duplicated = duplicateTripList(
                                    category,
                                    name: candidateName
                                )

                                duplicated.sortOrder = (categories.map(\.sortOrder).max() ?? 0) + 1

                                modelContext.insert(duplicated)
                                try? modelContext.save()
                            } label: {
                                Label(String(localized: "Duplicate"), systemImage: "plus.square.on.square")
                            }
                            .tint(.green)

                            Button {
                                editingCategory = category
                                newCategoryName = localizedTripText(category.name)
                                selectedIcon = category.icon
                                isEditingCategory = true
                                showNewCategorySheet = true
                            } label: {
                                Label(String(localized: "Edit"), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation {
                                    deleteTrip(category, in: modelContext)
                                }
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowBackground(
                        Color(.systemBackground).opacity(0.3)
                    )
                }

                .onDelete { indexSet in

                    for index in indexSet {
                        deleteTrip(
                            categories[index],
                            in: modelContext
                        )
                    }
                }
                .onMove(perform: moveCategories)
                
            }
            .contentMargins(.bottom, 70, for: .scrollContent)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            .navigationTitle(String(localized: "Checklists"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("Search checklists")
            )
            .task {
                // Backfill old categories created before templates existed.
                for category in categories {
                    
                    if category.checklistType.isEmpty {
                        category.checklistType = category.systemTemplate.isEmpty ? "custom" : "travel"
                    }
                    
                    if category.systemTemplate.isEmpty {
                        
                        switch category.name.lowercased() {
                        case "travel":
                            category.systemTemplate = "travel"
                            
                        case "car":
                            category.systemTemplate = "car"
                            
                        case "motorbike":
                            category.systemTemplate = "motorbike"
                            
                        case "camper":
                            category.systemTemplate = "camper"
                            
                        case "bicycle":
                            category.systemTemplate = "bicycle"
                            
                        case "boat":
                            category.systemTemplate = "boat"
                            
                        case "hiking":
                            category.systemTemplate = "hiking"
                            
                        case "photography":
                            category.systemTemplate = "photography"
                            
                        default:
                            break
                        }
                    }
                }
                
                for category in categories {
                    
                    switch category.systemTemplate {
                    case "travel":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeTravelSections()
                        )
                        
                    case "car":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeCarSections()
                        )
                        
                    case "motorbike":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeMotorbikeSections()
                        )
                        
                    case "camper":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeCamperSections()
                        )
                        
                    case "bicycle":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeBicycleSections()
                        )
                        
                    case "boat":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeBoatSections()
                        )
                        
                    case "hiking":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeHikingSections()
                        )
                        
                    case "photography":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makePhotographySections()
                        )
                    case "project":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeProjectSections()
                        )

                    case "work":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeWorkSections()
                        )

                    case "home":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeHomeSections()
                        )

                    case "event":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makeEventSections()
                        )

                    case "personal":
                        TripTemplates.mergeSections(
                            into: category,
                            newSections: TripTemplates.makePersonalSections()
                        )
                    default:
                        break
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Checklists")
                            .font(.headline)

                        Text(
                            "\(categories.count) lists"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showImportPicker = true
                        } label: {
                            Label(String(localized: "Import"), systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showExportSheet = true
                        } label: {
                            Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .padding(10)
                            .contentShape(Rectangle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingCategory = nil
                        isEditingCategory = false
                        newCategoryName = ""
                        selectedIcon = "list.bullet.clipboard"
                        showNewCategorySheet = true
                    } label: {
                        Image(systemName:
                        "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
//                            .padding(.trailing, 1)
                    }
                }
            }
            .sheet(isPresented: $showNewCategorySheet) {
                
                NavigationStack {
                    
                    ScrollView {
                        
                        VStack(alignment: .leading, spacing: 24) {

                            Text(String(localized: "Start with a template or create your own checklist"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Menu {
                                
                                ForEach(TripTemplates.allCategories) { template in
                                    Button {
                                        let localizedName = localizedTripText(template.name)
                                        var finalName = localizedName
                                        var suffix = 2
                                        while categories.contains(where: {
                                            localizedTripText($0.name) == finalName
                                        }) {
                                            finalName = "\(localizedName) \(suffix)"
                                            suffix += 1
                                        }
                                        let newCategory = TripList(
                                            name: finalName,
                                            icon: template.icon,
                                            systemTemplate: template.systemTemplate,
                                            checklistType: template.checklistType,
                                            sections: template.sections.map { section in                                                TripSectionData(
                                                    title: section.title,
                                                    items: section.items.map {
                                                        TripItemData(title: $0.title)
                                                    }
                                                )
                                            }
                                        )
                                        modelContext.insert(newCategory)
                                        try? modelContext.save()
                                        showNewCategorySheet = false
                                    } label: {
                                        Label(
                                            localizedTripText(template.name),
                                            systemImage: template.icon
                                        )
                                    }
                                }
                            } label: {
                                Label(
                                    String(localized: "Templates"),
                                    systemImage: "square.grid.3x3"
                                )
                                .font(.headline)
                            }
                            
                            VStack(alignment: .leading, spacing: 10) {
                                
                                Text(String(localized: "Checklist Name"))
                                    .font(.headline)
                                
                                TextField(String(localized: "Name"), text: $newCategoryName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 14) {
                                
                                Text(String(localized: "Choose Icon"))
                                    .font(.headline)
                                
                                LazyVGrid(
                                    columns: [
                                        GridItem(.adaptive(minimum: 58))
                                    ],
                                    spacing: 16
                                ) {
                                    
                                    ForEach(TripTemplates.availableIcons, id: \.self) { icon in
                                        
                                        let isSelected = selectedIcon == icon
                                        let backgroundColor = isSelected
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.clear
                                        
                                        let borderColor = isSelected
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.2)
                                        
                                        let borderWidth: CGFloat = isSelected ? 2 : 1
                                        
                                        Button {
                                            selectedIcon = icon
                                        } label: {
                                            
                                            Image(systemName: icon)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(
                                                    tripIconColors(for: icon).0,
                                                    tripIconColors(for: icon).1
                                                )
                                                .font(.title2)
                                                .frame(width: 54, height: 54)
                                                .background(
                                                    Circle()
                                                        .fill(backgroundColor)
                                                )
                                                .overlay {
                                                    Circle()
                                                        .stroke(
                                                            borderColor,
                                                            lineWidth: borderWidth
                                                        )
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationTitle(
                        isEditingCategory
                        ? String(localized: "Edit Checklist")
                        : String(localized: "New Checklist")
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        
                        ToolbarItem(placement: .topBarLeading) {
                            
                            Button(String(localized: "Cancel")) {
                                newCategoryName = ""
                                selectedIcon = "list.bullet.clipboard"
                                editingCategory = nil
                                isEditingCategory = false
                                showNewCategorySheet = false
                            }
                        }
                        
                        ToolbarItem(placement: .topBarTrailing) {
                            
                            
                            let trimmedName = newCategoryName
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            let originalName = editingCategory.map {
                                localizedTripText($0.name)
                            } ?? ""
                            
                            let originalIcon = editingCategory?.icon ?? ""
                            
                            let hasChanges = !trimmedName.isEmpty && (
                                trimmedName != originalName ||
                                selectedIcon != originalIcon
                            )
                            
                            if hasChanges || editingCategory == nil {
                                Button(String(localized: "Save")) {
                                
                                guard !trimmedName.isEmpty else {
                                    return
                                }
                                
                                do {
                                    if let editingCategory {
                                        let originalSystemName = editingCategory.systemTemplate.isEmpty
                                            ? nil
                                        : TripTemplates.allCategories.first(where: {
                                                $0.systemTemplate == editingCategory.systemTemplate
                                            })?.name
                                        
                                        if let originalSystemName,
                                           localizedTripText(originalSystemName) == trimmedName {
                                            editingCategory.name = originalSystemName
                                        } else {
                                            editingCategory.name = trimmedName
                                        }
                                        
                                        editingCategory.icon = selectedIcon

                                    } else {
                                        // Ensure unique trip type name
                                        let baseName = trimmedName
                                        var finalName = baseName
                                        var suffix = 2
                                        while categories.contains(where: {
                                            localizedTripText($0.name) == localizedTripText(finalName)
                                        }) {
                                            finalName = "\(baseName) \(suffix)"
                                            suffix += 1
                                        }
                                        let category = TripList(
                                            name: finalName,
                                            icon: selectedIcon,
                                            checklistType: "custom",
                                            sections: []
                                        )

                                        withAnimation {
                                            modelContext.insert(category)
                                        }

                                    }
                                    
                                    try modelContext.save()
                                } catch {
                                    print("Failed to save trip category:", error)
                                }
                                
                                newCategoryName = ""
                                selectedIcon = "list.bullet.clipboard"
                                editingCategory = nil
                                isEditingCategory = false
                                showNewCategorySheet = false
                            }
                                .disabled(trimmedName.isEmpty)
                            }
                        }
                    }
                }
            }
            // Removed confirmationDialogs for export pickers and all checklists.

            .sheet(isPresented: $showExportSheet) {
                NavigationStack {
                    List {
                        Section(String(localized: "Options")) {
                            Toggle(
                                String(localized: "Include Checks"),
                                isOn: $exportIncludeChecks
                            )
                        }
                        Section(String(localized: "Export All")) {
                            Button {
                                exportDocument = makeExportAllDocument(
                                    includeChecks: exportIncludeChecks
                                )
                                showExportSheet = false
                            } label: {
                                Label(
                                    String(localized: "Export All Checklists"),
                                    systemImage: "square.stack.3d.up"
                                )
                            }
                        }
                        Section(String(localized: "Export Single Checklist")) {
                            ForEach(visibleCategories) { category in
                                Button {
                                    categoryToExport = category

                                    let payload = FMTripPayload(
                                        name: category.name,
                                        icon: category.icon,
                                        systemTemplate: category.systemTemplate,
                                        checklistType: category.checklistType,
                                        sections: category.sections.map {
                                            FMTripSection(
                                                title: $0.title,
                                                items: $0.items.map {
                                                    FMTripItem(
                                                        title: $0.title,
                                                        isChecked: exportIncludeChecks ? $0.isChecked : false
                                                    )
                                                }
                                            )
                                        }
                                    )

                                    exportDocument = FMTripDocument(
                                        payload: FMTripCollectionPayload(lists: [payload])
                                    )

                                    showExportSheet = false
                                } label: {
                                    HStack {
                                        Image(systemName: category.icon)
                                        Text(localizedTripText(category.name))
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(String(localized: "Export"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(String(localized: "Done")) {
                                showExportSheet = false
                            }
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.data, .fmtrip]
            ) { result in
                if case .success(let url) = result {
                    importFMTrip(from: url)
                }
            }
            }
            // Move the following modifiers outside NavigationStack but inside ZStack:
            .fileExporter(
                isPresented: Binding(
                    get: { exportDocument != nil },
                    set: { if !$0 { exportDocument = nil } }
                ),
                document: exportDocument,
                contentType: .fmtrip,
                defaultFilename: categoryToExport.map { localizedTripText($0.name) } ?? "ForMemo-Checklists"
            ) { _ in
               
                exportDocument = nil
                categoryToExport = nil
            }
        }
    }
// MARK: - Import/Export Helpers

private func importFMTrip(from url: URL) {
    Task {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let collection = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                return try JSONDecoder().decode(
                    FMTripCollectionPayload.self,
                    from: data
                )
            }.value

            await MainActor.run {
                for payload in collection.lists {
                    let importedChecklistType =
                        payload.checklistType
                        ?? (payload.systemTemplate.isEmpty ? "custom" : "travel")

                    let trip = TripList(
                        name: payload.name,
                        icon: payload.icon,
                        systemTemplate: payload.systemTemplate,
                        checklistType: importedChecklistType,
                        sections: payload.sections.map {
                            TripSectionData(
                                title: $0.title,
                                items: $0.items.map {
                                    TripItemData(
                                        title: $0.title,
                                        isChecked: $0.isChecked
                                    )
                                }
                            )
                        }
                    )

                    modelContext.insert(trip)
                }

                try? modelContext.save()
            }
        } catch {
            print("Import failed:", error)
        }
    }
}


private func makeExportAllDocument(includeChecks: Bool) -> FMTripDocument {
    let payloads = categories.map { category in
        FMTripPayload(
            name: category.name,
            icon: category.icon,
            systemTemplate: category.systemTemplate,
            checklistType: category.checklistType,
            sections: category.sections.map {
                FMTripSection(
                    title: $0.title,
                    items: $0.items.map {
                        FMTripItem(
                            title: $0.title,
                            isChecked: includeChecks ? $0.isChecked : false
                        )
                    }
                )
            }
        )
    }

    return FMTripDocument(
        payload: FMTripCollectionPayload(lists: payloads)
    )
}
}


private func duplicateTripList(
    _ source: TripList,
    name: String
) -> TripList {
    var duplicatedSections: [TripSectionData] = []

    for sourceSection in source.sections {
        var duplicatedItems: [TripItemData] = []

        for sourceItem in sourceSection.items {
            var item = TripItemData(
                title: sourceItem.title,
                isChecked: sourceItem.isChecked,
                notes: sourceItem.notes,
                quantity: sourceItem.quantity,
                isImportant: sourceItem.isImportant,
                url: sourceItem.url,
                dueDate: sourceItem.dueDate,
                locationName: sourceItem.locationName,
                sortOrder: sourceItem.sortOrder,
                isTemplateLocked: sourceItem.isTemplateLocked
            )

            item.createdAt = sourceItem.createdAt
            item.updatedAt = sourceItem.updatedAt
            duplicatedItems.append(item)
        }

        var section = TripSectionData(
            title: sourceSection.title,
            isCollapsed: sourceSection.isCollapsed,
            icon: sourceSection.icon,
            notes: sourceSection.notes,
            sortOrder: sourceSection.sortOrder,
            items: duplicatedItems
        )

        section.createdAt = sourceSection.createdAt
        section.updatedAt = sourceSection.updatedAt
        duplicatedSections.append(section)
    }

    let duplicated = TripList(
        name: name,
        icon: source.icon,
        colorHex: source.colorHex,
        notes: source.notes,
        systemTemplate: source.systemTemplate,
        checklistType: source.checklistType,
        sortOrder: source.sortOrder,
        sections: duplicatedSections
    )

    return duplicated
}
// MARK: - Checklist View

import SwiftData
import SwiftUI

struct ChecklistView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Bindable var category: TripList
    
    @State private var newSectionTitle = ""
    @State private var showNewSectionAlert = false
    @State private var editingSectionID: UUID?
    @State private var sectionTitleDraft = ""
    @State private var showRenameSectionAlert = false

    @FocusState private var editingItemID: UUID?
    @State private var newlyCreatedItemID: UUID?
    @State private var newItemDraft: String = ""
    @State private var areAllSectionsCollapsed = false
    @State private var showResetChecksConfirmation = false
    
    @ViewBuilder
    private func newItemDraftRow(
        for section: Binding<TripSectionData>
    ) -> some View {
        if newlyCreatedItemID != nil {
            HStack {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)

                TextField(
                    String(localized: "Item"),
                    text: $newItemDraft
                )
                .textFieldStyle(.plain)
                .focused(
                    $editingItemID,
                    equals: newlyCreatedItemID
                )
                .onSubmit {
                    let title = newItemDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !title.isEmpty else {
                        newlyCreatedItemID = nil
                        newItemDraft = ""
                        editingItemID = nil
                        return
                    }

                    let newItem = TripItemData(title: title)
                    section.wrappedValue.items.append(newItem)

                    newlyCreatedItemID = nil
                    newItemDraft = ""
                    editingItemID = nil
                }
            }
            .listRowBackground(
                Color(.systemBackground).opacity(0.3)
            )
        }
    }
    
    
    var body: some View {
        ZStack {

            AppGlassBackground()

            List {
            ForEach($category.sections) { $section in
                Section {
                    if !section.isCollapsed {

                        ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, _ in
                            let itemBinding = $section.items[itemIndex]
                            HStack {
                                Button {
                                    itemBinding.isChecked.wrappedValue.toggle()
                                } label: {
                                    Image(
                                        systemName: itemBinding.isChecked.wrappedValue
                                        ? "checkmark.circle"
                                        : "circle"
                                    )
                                    .foregroundStyle(
                                        itemBinding.isChecked.wrappedValue
                                        ? AnyShapeStyle(.green)
                                        : AnyShapeStyle(.secondary)
                                    )
                                    .font(.title3)
                                }
                                .buttonStyle(.plain)

                                TextField(
                                    String(localized: "Item"),
                                    text: bindingForLocalizedTripText(itemBinding.title)
                                )
                                .textFieldStyle(.plain)
                                .focused(
                                    $editingItemID,
                                    equals: itemBinding.id
                                )
                                .onChange(of: editingItemID) { _, newFocusID in
                                    guard
                                        newFocusID != newlyCreatedItemID,
                                        let newItemID = newlyCreatedItemID
                                    else {
                                        return
                                    }

                                    if let index = section.items.firstIndex(where: { $0.id == newItemID }),
                                       section.items[index].title
                                           .trimmingCharacters(in: .whitespacesAndNewlines)
                                           .isEmpty {
                                        section.items.remove(at: index)
                                    }

                                    newlyCreatedItemID = nil
                                }
                                .strikethrough(itemBinding.isChecked.wrappedValue)
                                .foregroundStyle(
                                    itemBinding.isChecked.wrappedValue
                                        ? AnyShapeStyle(.secondary)
                                        : AnyShapeStyle(.primary)
                                )
                            }
                            .listRowBackground(
                                Color(.systemBackground).opacity(0.3)
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    section.items.remove(at: itemIndex)
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                            }
                        }
                        
                        
                        .onDelete { indexSet in
                            section.items.remove(atOffsets: indexSet)
                        }
                        .onMove { source, destination in
                            section.items.move(fromOffsets: source, toOffset: destination)
                        }
                        newItemDraftRow(for: $section)
                        
                        Button {
                            newItemDraft = ""
                            let newItemID = UUID()
                            newlyCreatedItemID = newItemID

                            DispatchQueue.main.async {
                                editingItemID = newItemID
                            }
                        } label: {
                            Label(String(localized: "Add Item"), systemImage: "plus")
                        }
                    }
                } header: {

                    let totalItems = section.items.count
                    let checkedItems = section.items.filter(\.isChecked).count
                    let remainingItems = max(totalItems - checkedItems, 0)
                    let isComplete = totalItems > 0 && remainingItems == 0

                    HStack(spacing: 12) {

                        Menu {

                            Button {
                                if let index = category.sections.firstIndex(where: { $0.id == section.id }) {
                                    editingSectionID = category.sections[index].id
                                    sectionTitleDraft = localizedTripText(category.sections[index].title)
                                    showRenameSectionAlert = true
                                }
                            } label: {
                                Label(String(localized: "Edit"), systemImage: "pencil")
                            }
                            Button {

                                TripClipboard.shared.copiedSection = TripSectionData(
                                    title: section.title,
                                    items: section.items.map {
                                        TripItemData(
                                            title: $0.title,
                                            isChecked: false
                                        )
                                    }
                                )

                            } label: {
                                Label(
                                    String(localized: "Copy Section"),
                                    systemImage: "doc.on.doc"
                                )
                            }
                            Button(role: .destructive) {
                                if let index = category.sections.firstIndex(where: { $0.id == section.id }) {
                                    category.sections.remove(at: index)
                                    try? modelContext.save()
                                }
                            } label: {
                                Label(String(localized: "Delete"), systemImage: "trash")
                            }

                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.primary)
                        }

                        Button {
                            editingItemID = nil

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    section.isCollapsed.toggle()
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizedTripText(section.title))
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(isComplete ? .green : .primary)
                                        .textCase(nil)
                                    if totalItems > 0 {
                                        Text("\(remainingItems) \(String(localized: "remaining"))")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }
                                }

                                Spacer()

                                Image(systemName: section.isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Removed Divider overlay, will add custom line below
                    }
                    // Add 1pt Rectangle separator line below the header
                    .clipShape(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.25))
                            .frame(height: 1)
                            .padding(.leading, 44)
                            .offset(y: 12)
                    }
                }
            }
            .onMove { source, destination in
                category.sections.move(fromOffsets: source, toOffset: destination)
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 70, for: .scrollContent)
        .onAppear {
            category.lastOpenedAt = Date()
            try? modelContext.save()
        }

        .navigationTitle(localizedTripText(category.name))
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .foregroundStyle(.tint)

                    Text(localizedTripText(category.name))
                        .font(.headline)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if TripClipboard.shared.copiedSection != nil {

                        Button {

                            guard let copied = TripClipboard.shared.copiedSection
                            else { return }

                            var newTitle = copied.title
                            var suffix = 2

                            while category.sections.contains(where: {
                                localizedTripText($0.title) ==
                                localizedTripText(newTitle)
                            }) {

                                newTitle = "\(copied.title) \(suffix)"
                                suffix += 1
                            }

                            category.sections.append(
                                TripSectionData(
                                    title: newTitle,
                                    items: copied.items.map {
                                        TripItemData(
                                            title: $0.title,
                                            isChecked: false
                                        )
                                    }
                                )
                            )

                            try? modelContext.save()

                        } label: {
                            Label(
                                String(localized: "Paste Section"),
                                systemImage: "doc.on.clipboard"
                            )
                        }

                        Divider()
                    }
                    Button {
                        showResetChecksConfirmation = true
                    } label: {
                        Label(String(localized: "Reset Checks"), systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        let shouldCollapse = category.sections.contains { !$0.isCollapsed }

                        withAnimation(.easeInOut(duration: 0.2)) {
                            for index in category.sections.indices {
                                category.sections[index].isCollapsed = shouldCollapse
                            }
                        }

                        areAllSectionsCollapsed = shouldCollapse
                    } label: {
                        Label(
                            category.sections.contains { !$0.isCollapsed }
                                ? String(localized: "Collapse All Sections")
                                : String(localized: "Expand All Sections"),
                            systemImage: category.sections.contains { !$0.isCollapsed }
                                ? "arrow.up.left.and.arrow.down.right"
                                : "arrow.down.right.and.arrow.up.left"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewSectionAlert = true
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .alert(String(localized: "New Section"), isPresented: $showNewSectionAlert) {

            TextField(String(localized: "Section Name"), text: $newSectionTitle)

            Button(String(localized: "Cancel"), role: .cancel) {
                newSectionTitle = ""
            }

            Button(String(localized: "Add")) {

                guard !newSectionTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return
                }

                category.sections.append(
                    TripSectionData(
                        title: newSectionTitle,
                        items: []
                    )
                )

                newSectionTitle = ""
            }
        }
        .alert(String(localized: "Edit"), isPresented: $showRenameSectionAlert) {

            TextField(String(localized: "Section Name"), text: $sectionTitleDraft)

            Button(String(localized: "Cancel"), role: .cancel) {
                editingSectionID = nil
            }

            Button(String(localized: "Save")) {

                guard let editingSectionID,
                      let index = category.sections.firstIndex(where: { $0.id == editingSectionID })
                else { return }

                let trimmed = sectionTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmed.isEmpty else { return }

                category.sections[index].title = trimmed
                try? modelContext.save()

                self.editingSectionID = nil
                sectionTitleDraft = ""
            }
        }
        .confirmationDialog(
            String(localized: "Reset Checks"),
            isPresented: $showResetChecksConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Reset Checks"), role: .destructive) {
                for sectionIndex in category.sections.indices {
                    for itemIndex in category.sections[sectionIndex].items.indices {
                        category.sections[sectionIndex].items[itemIndex].isChecked = false
                    }
                }
            }

            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "Are you sure you want to clear all checkmarks?"))
        }
        }
    }
}

// MARK: - Templates

enum TripTemplates {
    static func mergeSections(
        into category: TripList,
        newSections: [TripSectionData]
    ) {
        for newSection in newSections {
            if let sectionIndex = category.sections.firstIndex(where: {
                $0.title == newSection.title
            }) {
                for newItem in newSection.items {

                    let existsAnywhere = category.sections.contains { section in
                        section.items.contains { item in
                            item.title == newItem.title
                        }
                    }

                    if !existsAnywhere {
                        category.sections[sectionIndex].items.append(newItem)
                    }
                }
            } else {

                let filteredItems = newSection.items.filter { newItem in
                    !category.sections.contains { section in
                        section.items.contains { item in
                            item.title == newItem.title
                        }
                    }
                }

                if !filteredItems.isEmpty {
                    category.sections.append(
                        TripSectionData(
                            title: newSection.title,
                            items: filteredItems
                        )
                    )
                }
            }
        }
    }
    
    static let availableIcons: [String] = [
        "airplane.path.dotted",
        "car.2",
        "motorcycle",
        "bicycle",
        "tram",
        "ferry",
        "bus",
        "sailboat",
        "figure",
        "tent.2",
        "backpack",
        "suitcase.rolling.and.suitcase",
        "camera",
        "beach.umbrella",
        "snowflake",
        "mountain.2",
        "water.waves",
        "drop",
        "globe.europe.africa",
        "list.bullet.clipboard",
        "briefcase",
        "house",
        "calendar",
        "person",
        "folder",
        "hammer",
        "wrench.and.screwdriver",
        "cart",
        "gift",
        "star",
        "flag",
        "target",
        "building.2",
        "graduationcap",
        "sportscourt"
    ]
    
    static let featuredCategories: [TripList] = [
        TripList(
            name: "Travel",
            icon: "airplane.path.dotted",
            systemTemplate: "travel",
            sections: makeTravelSections()
        ),
        TripList(
            name: "Car",
            icon: "car.2",
            systemTemplate: "car",
            sections: makeCarSections()
        ),
        TripList(
            name: "Boat",
            icon: "sailboat",
            systemTemplate: "boat",
            sections: makeBoatSections()
        )
    ]

    static let additionalCategories: [TripList] = [
        TripList(
            name: "Motorbike",
            icon: "motorcycle",
            systemTemplate: "motorbike",
            sections: makeMotorbikeSections()
        ),
        TripList(
            name: "Camper",
            icon: "bus",
            systemTemplate: "camper",
            sections: makeCamperSections()
        ),
        TripList(
            name: "Bicycle",
            icon: "bicycle",
            systemTemplate: "bicycle",
            sections: makeBicycleSections()
        ),
        TripList(
            name: "Hiking",
            icon: "figure.hiking",
            systemTemplate: "hiking",
            sections: makeHikingSections()
        ),
        TripList(
            name: "Photography",
            icon: "camera",
            systemTemplate: "photography",
            sections: makePhotographySections()
        ),
        TripList(
            name: "Snow",
            icon: "snowflake",
            systemTemplate: "snow",
            sections: makeSnowSections()
        ),
        TripList(
            name: "Mountain",
            icon: "mountain.2",
            systemTemplate: "mountain",
            sections: makeMountainSections()
        ),
        TripList(
            name: "Sea",
            icon: "beach.umbrella",
            systemTemplate: "sea",
            sections: makeSeaSections()
        ),
        TripList(
            name: "River",
            icon: "water.waves",
            systemTemplate: "river",
            sections: makeRiverSections()
        ),
        TripList(
            name: "Lake",
            icon: "drop",
            systemTemplate: "lake",
            sections: makeLakeSections()
        ),
        TripList(
            name: "Project",
            icon: "target",
            systemTemplate: "project",
            checklistType: "custom",
            sections: makeProjectSections()
        ),
        TripList(
            name: "Work",
            icon: "briefcase",
            systemTemplate: "work",
            checklistType: "custom",
            sections: makeWorkSections()
        ),
        TripList(
            name: "Home",
            icon: "house",
            systemTemplate: "home",
            checklistType: "custom",
            sections: makeHomeSections()
        ),
        TripList(
            name: "Event",
            icon: "calendar",
            systemTemplate: "event",
            checklistType: "custom",
            sections: makeEventSections()
        ),
        TripList(
            name: "Personal",
            icon: "person",
            systemTemplate: "personal",
            checklistType: "custom",
            sections: makePersonalSections()
        )
    ]

    static var allCategories: [TripList] {
        featuredCategories + additionalCategories
    }
    
    
    static func makeProjectSections() -> [TripSectionData] {
        [
            TripSectionData(
                title: "Planning",
                items: [
                    TripItemData(title: "Define objectives"),
                    TripItemData(title: "Set deadline"),
                    TripItemData(title: "Create milestones"),
                    TripItemData(title: "Break down tasks"),
                    TripItemData(title: "Identify dependencies"),
                    TripItemData(title: "Assign responsibilities"),
                    TripItemData(title: "Estimate resources")
                ]
            ),
            TripSectionData(
                title: "Execution",
                items: [
                    TripItemData(title: "Start project"),
                    TripItemData(title: "Review progress"),
                    TripItemData(title: "Check milestones"),
                    TripItemData(title: "Resolve blockers"),
                    TripItemData(title: "Update priorities"),
                    TripItemData(title: "Review deadlines")
                ]
            ),
            TripSectionData(
                title: "Finalization",
                items: [
                    TripItemData(title: "Complete remaining tasks"),
                    TripItemData(title: "Review results"),
                    TripItemData(title: "Finalize deliverables"),
                    TripItemData(title: "Archive documents"),
                    TripItemData(title: "Record lessons learned"),
                    TripItemData(title: "Close project")
                ]
            )
        ]
    }

    static func makeWorkSections() -> [TripSectionData] {
        [
            TripSectionData(
                title: "Preparation",
                items: [
                    TripItemData(title: "Review agenda"),
                    TripItemData(title: "Prepare documents"),
                    TripItemData(title: "Check deadlines"),
                    TripItemData(title: "Review priorities"),
                    TripItemData(title: "Prepare meetings"),
                    TripItemData(title: "Check pending requests")
                ]
            ),
            TripSectionData(
                title: "Tasks",
                items: [
                    TripItemData(title: "Priority tasks"),
                    TripItemData(title: "Follow-ups"),
                    TripItemData(title: "Pending items"),
                    TripItemData(title: "Emails to send"),
                    TripItemData(title: "Calls to make"),
                    TripItemData(title: "Documents to review"),
                    TripItemData(title: "Tasks to delegate")
                ]
            ),
            TripSectionData(
                title: "Follow-up",
                items: [
                    TripItemData(title: "Send updates"),
                    TripItemData(title: "Schedule follow-ups"),
                    TripItemData(title: "Confirm pending items"),
                    TripItemData(title: "Update stakeholders"),
                    TripItemData(title: "Review open tasks"),
                    TripItemData(title: "Archive completed work")
                ]
            )
        ]
    }

    static func makeHomeSections() -> [TripSectionData] {
        [
            TripSectionData(
                title: "Planning",
                items: [
                    TripItemData(title: "Make a plan"),
                    TripItemData(title: "Check supplies"),
                    TripItemData(title: "Prepare tools"),
                    TripItemData(title: "Set priorities"),
                    TripItemData(title: "Set deadlines"),
                    TripItemData(title: "Organize materials")
                ]
            ),
            TripSectionData(
                title: "Tasks",
                items: [
                    TripItemData(title: "Cleaning"),
                    TripItemData(title: "Shopping"),
                    TripItemData(title: "Maintenance"),
                    TripItemData(title: "Repairs"),
                    TripItemData(title: "Organizing"),
                    TripItemData(title: "Laundry"),
                    TripItemData(title: "Other tasks")
                ]
            ),
            TripSectionData(
                title: "Final Checks",
                items: [
                    TripItemData(title: "Review completed tasks"),
                    TripItemData(title: "Clean up"),
                    TripItemData(title: "Put everything away"),
                    TripItemData(title: "Check remaining tasks"),
                    TripItemData(title: "Plan next steps")
                ]
            )
        ]
    }

    static func makeEventSections() -> [TripSectionData] {
        [
            TripSectionData(
                title: "Planning",
                items: [
                    TripItemData(title: "Set date and time"),
                    TripItemData(title: "Choose location"),
                    TripItemData(title: "Create guest list"),
                    TripItemData(title: "Set budget"),
                    TripItemData(title: "Plan activities"),
                    TripItemData(title: "Define schedule")
                ]
            ),
            TripSectionData(
                title: "Preparation",
                items: [
                    TripItemData(title: "Send invitations"),
                    TripItemData(title: "Prepare materials"),
                    TripItemData(title: "Arrange catering"),
                    TripItemData(title: "Confirm arrangements"),
                    TripItemData(title: "Prepare the location"),
                    TripItemData(title: "Check guest responses"),
                    TripItemData(title: "Prepare final details")
                ]
            ),
            TripSectionData(
                title: "Event Day",
                items: [
                    TripItemData(title: "Final check"),
                    TripItemData(title: "Welcome guests"),
                    TripItemData(title: "Follow the schedule"),
                    TripItemData(title: "Complete event"),
                    TripItemData(title: "Clean up"),
                    TripItemData(title: "Review remaining tasks")
                ]
            )
        ]
    }

    static func makePersonalSections() -> [TripSectionData] {
        [
            TripSectionData(
                title: "Planning",
                items: [
                    TripItemData(title: "Define goals"),
                    TripItemData(title: "Set priorities"),
                    TripItemData(title: "Set deadlines"),
                    TripItemData(title: "Make a plan"),
                    TripItemData(title: "Define next steps"),
                    TripItemData(title: "Set reminders")
                ]
            ),
            TripSectionData(
                title: "Tasks",
                items: [
                    TripItemData(title: "Important tasks"),
                    TripItemData(title: "Things to do"),
                    TripItemData(title: "Errands"),
                    TripItemData(title: "Calls"),
                    TripItemData(title: "Appointments"),
                    TripItemData(title: "Follow-ups"),
                    TripItemData(title: "Personal projects")
                ]
            ),
            TripSectionData(
                title: "Review",
                items: [
                    TripItemData(title: "Review progress"),
                    TripItemData(title: "Complete remaining tasks"),
                    TripItemData(title: "Adjust priorities"),
                    TripItemData(title: "Review deadlines"),
                    TripItemData(title: "Archive completed items")
                ]
            )
        ]
    }
    
    
    static func makeBaseSections() -> [TripSectionData] {
        [
            TripSectionData(
                title: "Documents",
                items: [
                    TripItemData(title: "ID Card"),
                    TripItemData(title: "Passport"),
                    TripItemData(title: "Tickets"),
                    TripItemData(title: "Insurance"),
                    TripItemData(title: "Driving License"),
                    TripItemData(title: "Boarding Pass"),
                    TripItemData(title: "Credit Card")
                ]
            ),
            TripSectionData(
                title: "Clothing",
                items: [
                    TripItemData(title: "T-Shirts"),
                    TripItemData(title: "Shoes"),
                    TripItemData(title: "Pajamas"),
                    TripItemData(title: "Jacket"),
                    TripItemData(title: "Underwear"),
                    TripItemData(title: "Socks"),
                    TripItemData(title: "Hat"),
                    TripItemData(title: "Swimsuit")
                ]
            ),
            TripSectionData(
                title: "Technology",
                items: [
                    TripItemData(title: "Phone Charger"),
                    TripItemData(title: "Power Bank"),
                    TripItemData(title: "Headphones"),
                    TripItemData(title: "Tablet"),
                    TripItemData(title: "Smartwatch Charger"),
                    TripItemData(title: "USB Cable")
                ]
            ),
            TripSectionData(
                title: "Bathroom",
                items: [
                    TripItemData(title: "Toothbrush"),
                    TripItemData(title: "Shampoo"),
                    TripItemData(title: "Medicines"),
                    TripItemData(title: "Sunscreen"),
                    TripItemData(title: "Deodorant"),
                    TripItemData(title: "Hairbrush")
                ]
            )
        ]
    }
    
    static func makeTravelSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Airport",
                items: [
                    TripItemData(title: "Checked Baggage"),
                    TripItemData(title: "Travel Pillow"),
                    TripItemData(title: "Neck Pillow"),
                    TripItemData(title: "Snacks"),
                    TripItemData(title: "Water Bottle")
                ]
            )
        ]
    }
    
    static func makeCarSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Car Essentials",
                items: [
                    TripItemData(title: "Car Charger"),
                    TripItemData(title: "Emergency Kit"),
                    TripItemData(title: "Fuel Card"),
                    TripItemData(title: "Car Documents"),
                    TripItemData(title: "Phone Holder"),
                    TripItemData(title: "Sunglasses")
                ]
            )
        ]
    }
    
    static func makeMotorbikeSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Motorbike Gear",
                items: [
                    TripItemData(title: "Helmet"),
                    TripItemData(title: "Gloves"),
                    TripItemData(title: "Rain Suit"),
                    TripItemData(title: "Protective Jacket"),
                    TripItemData(title: "Rain Gloves"),
                    TripItemData(title: "Motorbike Lock")
                ]
            )
        ]
    }
    
    static func makeCamperSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Camper",
                items: [
                    TripItemData(title: "Water Hose"),
                    TripItemData(title: "Camping Chairs"),
                    TripItemData(title: "Gas Bottle"),
                    TripItemData(title: "Electric Adapter")
                ]
            ),
            TripSectionData(
                title: "Kitchen",
                items: [
                    TripItemData(title: "Coffee"),
                    TripItemData(title: "Pots"),
                    TripItemData(title: "Cutlery"),
                    TripItemData(title: "Dish Soap"),
                    TripItemData(title: "Paper Towels"),
                    TripItemData(title: "Trash Bags"),
                    TripItemData(title: "Food Supplies")
                ]
            )
        ]
    }
    
    static func makeBicycleSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Bike Gear",
                items: [
                    TripItemData(title: "Helmet"),
                    TripItemData(title: "Repair Kit"),
                    TripItemData(title: "Water Bottle"),
                    TripItemData(title: "Bike Pump"),
                    TripItemData(title: "Bike Lock"),
                    TripItemData(title: "Cycling Glasses"),
                    TripItemData(title: "Energy Bars")
                ]
            )
        ]
    }
    
    static func makeBoatSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Boat Essentials",
                items: [
                    TripItemData(title: "Life Jackets"),
                    TripItemData(title: "Anchor"),
                    TripItemData(title: "GPS"),
                    TripItemData(title: "Ropes"),
                    TripItemData(title: "Dry Bags"),
                    TripItemData(title: "Sunscreen")
                ]
            )
        ]
    }
    
    static func makeHikingSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Hiking Gear",
                items: [
                    TripItemData(title: "Hiking Boots"),
                    TripItemData(title: "Flashlight"),
                    TripItemData(title: "Trail Snacks"),
                    TripItemData(title: "Compass"),
                    TripItemData(title: "Backpack"),
                    TripItemData(title: "Rain Jacket"),
                    TripItemData(title: "Thermal Bottle")
                ]
            )
        ]
    }
    
    static func makePhotographySections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Photography",
                items: [
                    TripItemData(title: "Camera"),
                    TripItemData(title: "Tripod"),
                    TripItemData(title: "SD Cards"),
                    TripItemData(title: "Extra Batteries"),
                    TripItemData(title: "Lens Cleaner"),
                    TripItemData(title: "Camera Bag"),
                    TripItemData(title: "Memory Card Reader")
                ]
            )
        ]
    }
    
    static func makeSnowSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Snow Gear",
                items: [
                    TripItemData(title: "Ski Goggles"),
                    TripItemData(title: "Ski Gloves"),
                    TripItemData(title: "Thermal Clothing"),
                    TripItemData(title: "Snow Boots"),
                    TripItemData(title: "Helmet"),
                    TripItemData(title: "Hand Warmers")
                ]
            )
        ]
    }

    static func makeMountainSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Mountain Gear",
                items: [
                    TripItemData(title: "Hiking Boots"),
                    TripItemData(title: "Trekking Poles"),
                    TripItemData(title: "Backpack"),
                    TripItemData(title: "Windproof Jacket"),
                    TripItemData(title: "Flashlight"),
                    TripItemData(title: "Water Bottle")
                ]
            )
        ]
    }

    static func makeSeaSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Beach Essentials",
                items: [
                    TripItemData(title: "Beach Towel"),
                    TripItemData(title: "Sunscreen"),
                    TripItemData(title: "Swimsuit"),
                    TripItemData(title: "Sunglasses"),
                    TripItemData(title: "Flip-Flops"),
                    TripItemData(title: "Beach Bag")
                ]
            )
        ]
    }

    static func makeRiverSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "River Essentials",
                items: [
                    TripItemData(title: "Water Shoes"),
                    TripItemData(title: "Dry Bag"),
                    TripItemData(title: "Life Jacket"),
                    TripItemData(title: "Waterproof Phone Case"),
                    TripItemData(title: "Towel"),
                    TripItemData(title: "Change of Clothes")
                ]
            )
        ]
    }

    static func makeLakeSections() -> [TripSectionData] {
        makeBaseSections() + [
            TripSectionData(
                title: "Lake Essentials",
                items: [
                    TripItemData(title: "Picnic Blanket"),
                    TripItemData(title: "Folding Chair"),
                    TripItemData(title: "Fishing Gear"),
                    TripItemData(title: "Insect Repellent"),
                    TripItemData(title: "Water Bottle"),
                    TripItemData(title: "Cooler Bag")
                ]
            )
        ]
    }
    
}

// MARK:helper localization functions

private func tripIconColors(for icon: String) -> (Color, Color) {
    switch icon {
    case "airplane.path.dotted": return (.blue, .primary)
    case "car.2": return (.mint, .blue)
    case "motorcycle": return (.orange, .red)
    case "bicycle": return (.green, .mint)
    case "tram": return (.indigo, .blue)
    case "ferry": return (.cyan, .blue)
    case "bus": return (.purple, .pink)
    case "sailboat": return (.teal, .cyan)
    case "figure", "figure.hiking": return (.green, .orange)
    case "tent.2": return (.brown, .green)
    case "backpack": return (.green, .brown)
    case "suitcase.rolling.and.suitcase": return (.blue, .cyan)
    case "camera": return (.purple, .pink)
    case "beach.umbrella": return (.yellow, .orange)
    case "snowflake": return (.cyan, .white)
    case "mountain.2": return (.brown, .green)
    case "water.waves": return (.blue, .primary)
    case "drop": return (.teal, .blue)
    case "globe.europe.africa": return (.green, .blue)
    case "list.bullet.clipboard": return (.indigo, .blue)
    case "briefcase": return (.purple, .blue)
    case "house": return (.orange, .red)
    case "calendar": return (.red, .orange)
    case "person": return (.teal, .blue)
    case "folder": return (.yellow, .orange)
    case "hammer": return (.orange, .brown)
    case "wrench.and.screwdriver": return (.gray, .blue)
    case "cart": return (.green, .teal)
    case "gift": return (.pink, .purple)
    case "star": return (.yellow, .orange)
    case "flag": return (.red, .orange)
    case "target": return (.red, .pink)
    case "building.2": return (.blue, .indigo)
    case "graduationcap": return (.purple, .indigo)
    case "sportscourt": return (.green, .blue)
    default: return (.blue, .cyan)
    }
}

// MARK:helper localization functions
private func localizedTripText(_ text: String) -> String {
    String(localized: String.LocalizationValue(text))
}

private func bindingForLocalizedTripText(_ binding: Binding<String>) -> Binding<String> {
    Binding(
        get: {
            localizedTripText(binding.wrappedValue)
        },
        set: { newValue in
            binding.wrappedValue = newValue
        }
    )
}
// MARK: - Localization Preload

private func preloadTripLocalizationKeys() {
    
    _ = String(localized: "%lld items")
    
    _ = String(localized: "Add")
    _ = String(localized: "Add Item")
    _ = String(localized: "Airport")
    _ = String(localized: "Anchor")
    _ = String(localized: "Bathroom")
    _ = String(localized: "Bicycle")
    _ = String(localized: "Bike Gear")
    _ = String(localized: "Bike Pump")
    _ = String(localized: "Boarding Pass")
    _ = String(localized: "Boat")
    _ = String(localized: "Boat Documents")
    _ = String(localized: "Boat Essentials")
    _ = String(localized: "Camera")
    _ = String(localized: "Camper")
    _ = String(localized: "Camping Chairs")
    _ = String(localized: "Car")
    _ = String(localized: "Car Charger")
    _ = String(localized: "Car Essentials")
    _ = String(localized: "Checked Baggage")
    _ = String(localized: "Choose Icon")
    _ = String(localized: "Clothing")
    _ = String(localized: "Coffee")
    _ = String(localized: "Compass")
    _ = String(localized: "Create")
    _ = String(localized: "Cutlery")
    _ = String(localized: "Dish Soap")
    _ = String(localized: "Documents")
    _ = String(localized: "Driving License")
    _ = String(localized: "Electric Adapter")
    _ = String(localized: "Emergency Kit")
    _ = String(localized: "Extra Batteries")
    _ = String(localized: "Flashlight")
    _ = String(localized: "Fuel Card")
    _ = String(localized: "Gas Bottle")
    _ = String(localized: "Gloves")
    _ = String(localized: "GPS")
    _ = String(localized: "Headphones")
    _ = String(localized: "Helmet")
    _ = String(localized: "Hiking")
    _ = String(localized: "Hiking Boots")
    _ = String(localized: "Hiking Gear")
    _ = String(localized: "ID Card")
    _ = String(localized: "Insurance")
    _ = String(localized: "Item")
    _ = String(localized: "Jacket")
    _ = String(localized: "Kitchen")
    _ = String(localized: "Life Jackets")
    _ = String(localized: "Medicines")
    _ = String(localized: "Motorbike")
    _ = String(localized: "Motorbike Documents")
    _ = String(localized: "Motorbike Gear")
    _ = String(localized: "Name")
    _ = String(localized: "New Section")
    _ = String(localized: "New Checklist")
    _ = String(localized: "No Checklists")
    _ = String(localized: "Tap + to start with a template or create your own checklists")
    _ = String(localized: "Edit")
    _ = String(localized: "Edit Checklist")
    _ = String(localized: "Save")
    _ = String(localized: "Pajamas")
    _ = String(localized: "Passport")
    _ = String(localized: "Phone Charger")
    _ = String(localized: "Photography")
    _ = String(localized: "Pots")
    _ = String(localized: "Power Bank")
    _ = String(localized: "Rain Suit")
    _ = String(localized: "Repair Kit")
    _ = String(localized: "remaining")
    _ = String(localized: "Reset Checks")
    _ = String(localized: "SD Cards")
    _ = String(localized: "Section Name")
    _ = String(localized: "Shampoo")
    _ = String(localized: "Shoes")
    _ = String(localized: "T-Shirts")
    _ = String(localized: "Technology")
    _ = String(localized: "Templates")
    _ = String(localized: "Start with a template or create your own checklist")
    _ = String(localized: "Tickets")
    _ = String(localized: "Toothbrush")
    _ = String(localized: "Trail Snacks")
    _ = String(localized: "Travel")
    _ = String(localized: "Travel Pillow")
    _ = String(localized: "Checklist Name")
    _ = String(localized: "Tripod")
    _ = String(localized: "Water Bottle")
    _ = String(localized: "Water Hose")
    _ = String(localized: "Credit Card")
    _ = String(localized: "Underwear")
    _ = String(localized: "Socks")
    _ = String(localized: "Hat")
    _ = String(localized: "Swimsuit")
    _ = String(localized: "Tablet")
    _ = String(localized: "Smartwatch Charger")
    _ = String(localized: "USB Cable")
    _ = String(localized: "Sunscreen")
    _ = String(localized: "Deodorant")
    _ = String(localized: "Hairbrush")
//    _ = String(localized: "Neck Pillow")
    _ = String(localized: "Snacks")
    _ = String(localized: "Car Documents")
    _ = String(localized: "Phone Holder")
    _ = String(localized: "Sunglasses")
    _ = String(localized: "Protective Jacket")
    _ = String(localized: "Rain Gloves")
    _ = String(localized: "Motorbike Lock")
    _ = String(localized: "Paper Towels")
    _ = String(localized: "Trash Bags")
    _ = String(localized: "Food Supplies")
    _ = String(localized: "Bike Lock")
    _ = String(localized: "Cycling Glasses")
    _ = String(localized: "Energy Bars")
    _ = String(localized: "Ropes")
    _ = String(localized: "Dry Bags")
    _ = String(localized: "Backpack")
    _ = String(localized: "Rain Jacket")
    _ = String(localized: "Thermal Bottle")
    _ = String(localized: "Lens Cleaner")
    _ = String(localized: "Camera Bag")
    _ = String(localized: "Memory Card Reader")

    _ = String(localized: "Snow")
    _ = String(localized: "Mountain")
    _ = String(localized: "Sea")
    _ = String(localized: "River")
    _ = String(localized: "Lake")
    _ = String(localized: "Snow Gear")
    _ = String(localized: "Ski Goggles")
    _ = String(localized: "Ski Gloves")
    _ = String(localized: "Thermal Clothing")
    _ = String(localized: "Snow Boots")
    _ = String(localized: "Hand Warmers")
    _ = String(localized: "Mountain Gear")
    _ = String(localized: "Trekking Poles")
    _ = String(localized: "Windproof Jacket")
    _ = String(localized: "Beach Essentials")
    _ = String(localized: "Beach Towel")
    _ = String(localized: "Flip-Flops")
    _ = String(localized: "Beach Bag")
    _ = String(localized: "River Essentials")
    _ = String(localized: "Water Shoes")
    _ = String(localized: "Dry Bag")
    _ = String(localized: "Life Jacket")
    _ = String(localized: "Waterproof Phone Case")
    _ = String(localized: "Change of Clothes")
    _ = String(localized: "Lake Essentials")
    _ = String(localized: "Picnic Blanket")
    _ = String(localized: "Folding Chair")
    _ = String(localized: "Fishing Gear")
    _ = String(localized: "Insect Repellent")
    _ = String(localized: "Cooler Bag")
    
    
    // Generic checklist templates

    _ = String(localized: "Project")
    _ = String(localized: "Work")
    _ = String(localized: "Home")
    _ = String(localized: "Event")
    _ = String(localized: "Personal")

    // Section titles
    _ = String(localized: "Planning")
    _ = String(localized: "Execution")
    _ = String(localized: "Finalization")
    _ = String(localized: "Preparation")
    _ = String(localized: "Tasks")
    _ = String(localized: "Follow-up")
    _ = String(localized: "Final Checks")
    _ = String(localized: "Event Day")
    _ = String(localized: "Review")

    // Project
    _ = String(localized: "Define objectives")
    _ = String(localized: "Set deadline")
    _ = String(localized: "Create milestones")
    _ = String(localized: "Break down tasks")
    _ = String(localized: "Identify dependencies")
    _ = String(localized: "Assign responsibilities")
    _ = String(localized: "Estimate resources")
    _ = String(localized: "Start project")
    _ = String(localized: "Review progress")
    _ = String(localized: "Check milestones")
    _ = String(localized: "Resolve blockers")
    _ = String(localized: "Update priorities")
    _ = String(localized: "Review deadlines")
    _ = String(localized: "Complete remaining tasks")
    _ = String(localized: "Review results")
    _ = String(localized: "Finalize deliverables")
    _ = String(localized: "Archive documents")
    _ = String(localized: "Record lessons learned")
    _ = String(localized: "Close project")

    // Work
    _ = String(localized: "Review agenda")
    _ = String(localized: "Prepare documents")
    _ = String(localized: "Check deadlines")
    _ = String(localized: "Review priorities")
    _ = String(localized: "Prepare meetings")
    _ = String(localized: "Check pending requests")
    _ = String(localized: "Priority tasks")
    _ = String(localized: "Follow-ups")
    _ = String(localized: "Pending items")
    _ = String(localized: "Emails to send")
    _ = String(localized: "Calls to make")
    _ = String(localized: "Documents to review")
    _ = String(localized: "Tasks to delegate")
    _ = String(localized: "Send updates")
    _ = String(localized: "Schedule follow-ups")
    _ = String(localized: "Confirm pending items")
    _ = String(localized: "Update stakeholders")
    _ = String(localized: "Review open tasks")
    _ = String(localized: "Archive completed work")

    // Home
    _ = String(localized: "Make a plan")
    _ = String(localized: "Check supplies")
    _ = String(localized: "Prepare tools")
    _ = String(localized: "Set priorities")
    _ = String(localized: "Set deadlines")
    _ = String(localized: "Organize materials")
    _ = String(localized: "Cleaning")
    _ = String(localized: "Shopping")
    _ = String(localized: "Maintenance")
    _ = String(localized: "Repairs")
    _ = String(localized: "Organizing")
    _ = String(localized: "Laundry")
    _ = String(localized: "Other tasks")
    _ = String(localized: "Review completed tasks")
    _ = String(localized: "Clean up")
    _ = String(localized: "Put everything away")
    _ = String(localized: "Check remaining tasks")
    _ = String(localized: "Plan next steps")

    // Event
    _ = String(localized: "Set date and time")
    _ = String(localized: "Choose location")
    _ = String(localized: "Create guest list")
    _ = String(localized: "Set budget")
    _ = String(localized: "Plan activities")
    _ = String(localized: "Define schedule")
    _ = String(localized: "Send invitations")
    _ = String(localized: "Prepare materials")
    _ = String(localized: "Arrange catering")
    _ = String(localized: "Confirm arrangements")
    _ = String(localized: "Prepare the location")
    _ = String(localized: "Check guest responses")
    _ = String(localized: "Prepare final details")
    _ = String(localized: "Final check")
    _ = String(localized: "Welcome guests")
    _ = String(localized: "Follow the schedule")
    _ = String(localized: "Complete event")
    _ = String(localized: "Clean up")
    _ = String(localized: "Review remaining tasks")

    // Personal
    _ = String(localized: "Define goals")
    _ = String(localized: "Set priorities")
    _ = String(localized: "Set deadlines")
    _ = String(localized: "Make a plan")
    _ = String(localized: "Define next steps")
    _ = String(localized: "Set reminders")
    _ = String(localized: "Important tasks")
    _ = String(localized: "Things to do")
    _ = String(localized: "Errands")
    _ = String(localized: "Calls")
    _ = String(localized: "Appointments")
    _ = String(localized: "Follow-ups")
    _ = String(localized: "Personal projects")
    _ = String(localized: "Review progress")
    _ = String(localized: "Complete remaining tasks")
    _ = String(localized: "Adjust priorities")
    _ = String(localized: "Review deadlines")
    _ = String(localized: "Archive completed items")

    // Checklist UI
    _ = String(localized: "Search checklists")
    _ = String(localized: "items")
    _ = String(localized: "Delete")
    _ = String(localized: "Cancel")
    _ = String(localized: "Collapse All Sections")
    _ = String(localized: "Expand All Sections")
}
