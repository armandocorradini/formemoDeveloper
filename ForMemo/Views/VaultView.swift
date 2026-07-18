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
    @State private var selectedDetailItem: VaultItem?
    @State private var selectedEditItem: VaultItem?

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
                Button {
                    Task {
                        do {
                            try await VaultLock.shared.authenticate(
                                reason: String(localized: "View Credential")
                            )

                            await MainActor.run {
                                selectedDetailItem = item
                            }

                        } catch {
                            return
                        }
                    }
                } label: {
                    VaultRow(item: item)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    Color(.systemBackground).opacity(0.3)
                )
                .listRowInsets(
                    EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        Task {
                            do {
                                try await VaultLock.shared.authenticate(
                                    reason: String(localized: "Edit Credential")
                                )

                                await MainActor.run {
                                    selectedEditItem = item
                                }

                            } catch {
                                return
                            }
                        }
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
                        Task {
                            do {
                                try await VaultLock.shared.authenticate(
                                    reason: String(localized: "Edit Credential")
                                )

                                await MainActor.run {
                                    selectedEditItem = item
                                }

                            } catch {
                                return
                            }
                        }
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
            .modifier(
                VaultSearchModifier(
                    enabled: !filteredItems.isEmpty,
                    searchText: $searchText
                )
            )
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
            .navigationDestination(item: $selectedDetailItem) { item in
                VaultDetailView(item: item)
            }
            .sheet(isPresented: $showingAddItem) {
                NavigationStack {
                    VaultEditView()
                }
            }
            .sheet(item: $selectedEditItem) { item in
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



private struct VaultSearchModifier: ViewModifier {

    let enabled: Bool
    @Binding var searchText: String

    @ViewBuilder
    func body(content: Content) -> some View {

        if enabled {
            content.searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always)
            )
        } else {
            content
        }
    }
}
