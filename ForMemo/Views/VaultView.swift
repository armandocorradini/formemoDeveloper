import SwiftUI
import SwiftData

struct VaultView: View {

    init() {}

    @Environment(\.modelContext) private var modelContext

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
        NavigationStack {
#if os(iOS)
            Color.clear
                .frame(height: 0)
#endif
            List(filteredItems) { item in
                NavigationLink {
                    VaultDetailView(item: item)
                } label: {
                    VaultRow(item: item)
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
            .navigationTitle(String(localized: "Vault"))
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
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.green)
                            .clipShape(Circle())
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
