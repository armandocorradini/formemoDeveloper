import SwiftUI
import SwiftData

struct VaultView: View {

    init() {}

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @Query(sort: \VaultItem.title)
    private var items: [VaultItem]

    @State private var searchText = ""
    @State private var showingAddItem = false
    @State private var selectedItem: VaultItem?

    private var filteredItems: [VaultItem] {
        guard !searchText.isEmpty else {
            return items.filter { $0.deletedAt == nil }
        }

        return items.filter {
            $0.deletedAt == nil && (
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                $0.email.localizedCaseInsensitiveContains(searchText) ||
                $0.website.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            )
        }
    }

    var body: some View {
        ZStack {
            AppGlassBackground()

            List(filteredItems) { item in
                NavigationLink {
                    VaultDetailView(item: item)
                } label: {
                    VaultRow(item: item)
                }
                .listRowBackground(
                    Color(.systemBackground).opacity(0.3)
                )
                .listRowInsets(
                    EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        selectedItem = item
                    } label: {
                        Label(String(localized: "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)

                    Button {
                        item.favorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(
                            item.favorite ? String(localized: "Remove Favorite") : String(localized: "Favorite"),
                            systemImage: item.favorite ? "star.slash" : "star"
                        )
                    }
                    .tint(.yellow)
                }

                .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                    Button(role: .destructive) {
                        try? VaultManager.shared.deleteCredential(
                            item,
                            in: modelContext
                        )
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        selectedItem = item
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        item.favorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(
                            item.favorite ? String(localized: "Remove Favorite") : String(localized: "Favorite"),
                            systemImage: item.favorite ? "star.slash" : "star"
                        )
                    }
                    Divider()

                    Button(role: .destructive) {
                        try? VaultManager.shared.deleteCredential(
                            item,
                            in: modelContext
                        )
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle(String(localized: "Vault"))
      
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 70, for: .scrollContent)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {

                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        VaultSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RecentlyDeletedVaultView()
                    } label: {
                        Image(systemName: "trash.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                            .padding(.trailing,0)
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                NavigationStack {
                    VaultEditView()
                }
            }
            .sheet(item: $selectedItem) { item in
                NavigationStack {
                    VaultEditView(item: item)
                }
            }
            .overlay {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Credentials"),
                        systemImage: "lock.shield",
                        description: Text(String(localized: "Your secure credentials will appear here."))
                    )
                }
            }
        }
    }
}

#Preview {
    VaultView()
        .modelContainer(for: VaultItem.self, inMemory: true)
}
