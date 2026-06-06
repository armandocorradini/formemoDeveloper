import SwiftUI
import UIKit
import SwiftData

// MARK: - Main View

struct TravelKitListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    @Query(sort: \TripList.sortOrder)
    private var categories: [TripList]
    
    @State private var showNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var selectedIcon = "suitcase.rolling"
    @State private var showNewCategorySheet = false
    @State private var editingCategory: TripList?
    @State private var isEditingCategory = false
    @State private var searchText = ""

    private var visibleCategories: [TripList] {

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return categories
        }

        return categories.filter {
            localizedTripText($0.name)
                .localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {

        ZStack {

            LinearGradient(
                colors: [backColor1, backColor2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            NavigationStack {
            
            List {
                
                if visibleCategories.isEmpty {
                    
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Trip Types"),
                            systemImage: "suitcase.rolling"
                        )
                    } description: {
                        Text(
                            String(localized: "Tap + to start with a template or create your own trip type")
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                
                ForEach(visibleCategories) { category in
                    
                    NavigationLink {
                        TripChecklistView(category: category)
                    } label: {
                        
                        HStack(spacing: 14) {
                            
                            Image(systemName: category.icon)
                                .font(.title2)
                                .frame(width: 34)
                                .foregroundStyle(.tint)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                
                                Text(localizedTripText(category.name))
                                    .font(.headline)

                                let totalItems = category.sections.reduce(0) { $0 + $1.items.count }

                                let checkedItems = category.sections.reduce(0) {
                                    partialResult,
                                    section in
                                    partialResult + section.items.filter(\.isChecked).count
                                }

                                let remainingItems = max(totalItems - checkedItems, 0)

                                Text(
                                    "\(totalItems) \(String(localized: "items")) • \(remainingItems) \(String(localized: "remaining"))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contextMenu {

                            if sizeClass == .regular {

                                Button {
                                    editingCategory = category
                                    newCategoryName = localizedTripText(category.name)
                                    selectedIcon = category.icon
                                    isEditingCategory = true
                                    showNewCategorySheet = true
                                } label: {
                                    Label(String(localized: "Edit"), systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteTrip(category, in: modelContext)
                                    }
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
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
                }

                .onDelete { indexSet in

                    for index in indexSet {
                        deleteTrip(
                            categories[index],
                            in: modelContext
                        )
                    }
                }
                .onMove { source, destination in
                    
                    var reordered = categories
                    reordered.move(fromOffsets: source, toOffset: destination)
                    
                    withAnimation(.none) {
                        for (index, category) in reordered.enumerated() {
                            category.sortOrder = index
                        }
                    }
                    
                    try? modelContext.save()
                }
            }
            .contentMargins(.bottom, 70, for: .scrollContent)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
//            .onAppear {
//                preloadTripLocalizationKeys()
//            }
            .navigationTitle(String(localized: "Trips"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("Search trips")
            )
            .task {
                // Backfill old categories created before templates existed.
                for category in categories {
                    
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
                        
                    default:
                        break
                    }
                }
            }
            .toolbar {
                
                ToolbarItem(placement: .topBarTrailing) {
                    
                    Button {
                        editingCategory = nil
                        isEditingCategory = false
                        newCategoryName = ""
                        selectedIcon = "suitcase.rolling"
                        showNewCategorySheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewCategorySheet) {
                
                NavigationStack {
                    
                    ScrollView {
                        
                        VStack(alignment: .leading, spacing: 24) {

                            Text(String(localized: "Start with a template or create your own trip type"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Menu {
                                
                                ForEach(TripTemplates.allCategories) { template in
                                    
                                    Button {
                                        
                                        let newCategory = TripList(
                                            name: template.name,
                                            icon: template.icon,
                                            systemTemplate: template.systemTemplate,
                                            sections: template.sections.map { section in
                                                TripSectionData(
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
                                
                                Text(String(localized: "Trip Name"))
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
                        ? String(localized: "Edit Trip Type")
                        : String(localized: "New Trip Type")
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        
                        ToolbarItem(placement: .topBarLeading) {
                            
                            Button(String(localized: "Cancel")) {
                                newCategoryName = ""
                                selectedIcon = "suitcase.rolling"
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
                                        print("Trip category updated:", trimmedName)
                                    } else {
                                        let category = TripList(
                                            name: trimmedName,
                                            icon: selectedIcon,
                                            sections: TripTemplates.makeBaseSections()
                                        )

                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makeTravelSections()
                                        )
                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makeCarSections()
                                        )
                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makeMotorbikeSections()
                                        )
                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makeCamperSections()
                                        )
                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makeBicycleSections()
                                        )
                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makeBoatSections()
                                        )
                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makeHikingSections()
                                        )
                                        TripTemplates.mergeSections(
                                            into: category,
                                            newSections: TripTemplates.makePhotographySections()
                                        )

                                        withAnimation {
                                            modelContext.insert(category)
                                        }

                                        print("Trip category created:", trimmedName)
                                    }
                                    
                                    try modelContext.save()
                                } catch {
                                    print("Failed to save trip category:", error)
                                }
                                
                                newCategoryName = ""
                                selectedIcon = "suitcase.rolling"
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
            }
        }
    }
}

// MARK: - Checklist View

import SwiftData
import SwiftUI

struct TripChecklistView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Bindable var category: TripList
    
    @State private var newSectionTitle = ""
    @State private var showNewSectionAlert = false
    @State private var editingSectionID: UUID?
    @State private var sectionTitleDraft = ""
    @State private var showRenameSectionAlert = false
    @FocusState private var isEditingTextField: Bool
    
    var body: some View {
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
                                .focused($isEditingTextField)
                                .strikethrough(itemBinding.isChecked.wrappedValue)
                                .foregroundStyle(
                                    itemBinding.isChecked.wrappedValue
                                    ? AnyShapeStyle(.secondary)
                                    : AnyShapeStyle(.primary)
                                )
                            }
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

                        Button {
                            section.items.append(
                                TripItemData(title: String(localized: "New Item"))
                            )
                        } label: {
                            Label(String(localized: "Add Item"), systemImage: "plus")
                        }
                    }
                } header: {

                    let totalItems = section.items.count
                    let checkedItems = section.items.filter(\.isChecked).count
                    let remainingItems = max(totalItems - checkedItems, 0)

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
                            isEditingTextField = false

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
                                        .foregroundColor(.primary)
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
                    }
                }
            }
            .onMove { source, destination in
                category.sections.move(fromOffsets: source, toOffset: destination)
            }
        }
        .contentMargins(.bottom, 70, for: .scrollContent)
        .navigationTitle(localizedTripText(category.name))
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    for sectionIndex in category.sections.indices {
                        for itemIndex in category.sections[sectionIndex].items.indices {
                            category.sections[sectionIndex].items[itemIndex].isChecked = false
                        }
                    }
                } label: {
                    Label(String(localized: "Reset Checks"), systemImage: "arrow.counterclockwise")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewSectionAlert = true
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
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
        "airplane",
        "car",
        "motorcycle",
        "bicycle",
        "tram",
        "ferry",
        "bus",
        "sailboat",
        "figure",
        "tent",
        "backpack",
        "suitcase.rolling",
        "camera",
        "beach.umbrella",
        "globe.europe.africa"
    ]
    
    static let featuredCategories: [TripList] = [
        TripList(
            name: "Travel",
            icon: "airplane",
            systemTemplate: "travel",
            sections: makeTravelSections()
        ),
        TripList(
            name: "Car",
            icon: "car",
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
        )
    ]

    static var allCategories: [TripList] {
        featuredCategories + additionalCategories
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
    _ = String(localized: "New Trip Type")
    _ = String(localized: "No Trip Types")
    _ = String(localized: "Tap + to start with a template or create your own trip type")
    _ = String(localized: "Edit")
    _ = String(localized: "Edit Trip Type")
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
    _ = String(localized: "Start with a template or create your own trip type")
    _ = String(localized: "Tickets")
    _ = String(localized: "Toothbrush")
    _ = String(localized: "Trail Snacks")
    _ = String(localized: "Travel")
    _ = String(localized: "Travel Pillow")
    _ = String(localized: "Trip Name")
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
    _ = String(localized: "Neck Pillow")
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
}
#Preview {
    TravelKitListView()
}
