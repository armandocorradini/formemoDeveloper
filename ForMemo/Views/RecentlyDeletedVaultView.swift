
import SwiftUI
import SwiftData

struct RecentlyDeletedVaultView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<VaultItem> {
            $0.deletedAt != nil
        },
        sort: \VaultItem.deletedAt,
        order: .reverse
    )
    private var items: [VaultItem]
    @State private var selection = Set<VaultItem.ID>()
    
    var body: some View {

        ZStack {

            AppGlassBackground()

            List {

                if items.isEmpty {

                    ContentUnavailableView(
                        "No Recently Deleted Items",
                        systemImage: "trash",
                        description: Text("Deleted Vault items will appear here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                } else {

                    ForEach(items) { item in

                        HStack(spacing: 12) {
                            Image(
                                systemName: selection.contains(item.id)
                                ? "checkmark.circle.fill"
                                : "circle"
                            )
                            .foregroundStyle(
                                selection.contains(item.id)
                                ? .blue
                                : .secondary
                            )
                            .onTapGesture {

                                if selection.contains(item.id) {
                                    selection.remove(item.id)
                                } else {
                                    selection.insert(item.id)
                                }
                            }
                            Image(systemName: item.icon.rawValue)
                                .font(.title3)
                                .foregroundStyle(item.color.swiftUIColor)
                                .frame(width: 34)

                            VStack(alignment: .leading, spacing: 4) {

                                Text(item.title)

                                if !item.username.isEmpty {

                                    Text(item.username)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let deletedAt = item.deletedAt {

                                    Text(
                                        "Deleted: \(deletedAt.formatted(date: .abbreviated, time: .shortened))"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {

                            Button {

                                try? VaultManager.shared.restoreCredential(
                                    item,
                                    in: modelContext
                                )

                            } label: {

                                Label(
                                    "Restore",
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {

                            Button(
                                role: .destructive
                            ) {

                                try? VaultManager.shared
                                    .deleteCredentialPermanently(
                                        item,
                                        in: modelContext
                                    )

                            } label: {

                                Label(
                                    "Delete Now",
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {

//            ToolbarItem(placement: .topBarLeading) {
//
//                Button {
//
//                    dismiss()
//
//                } label: {
//
//                    Image(systemName: "xmark")
//                }
//            }
            ToolbarItem(placement: .topBarTrailing) {

                Menu {

                    Button(
                        selection.count == items.count
                        ? "Deselect All"
                        : "Select All"
                    ) {

                        if selection.count == items.count {

                            selection.removeAll()

                        } else {

                            selection = Set(items.map(\.id))
                        }
                    }

                    Button {

                        for item in items where selection.contains(item.id) {

                            try? VaultManager.shared.restoreCredential(
                                item,
                                in: modelContext
                            )
                        }

                        selection.removeAll()

                    } label: {

                        Label(
                            "Restore",
                            systemImage: "arrow.uturn.backward"
                        )
                    }

                    Button(role: .destructive) {

                        for item in items where selection.contains(item.id) {

                            try? VaultManager.shared
                                .deleteCredentialPermanently(
                                    item,
                                    in: modelContext
                                )
                        }

                        selection.removeAll()

                    } label: {

                        Label(
                            "Delete",
                            systemImage: "trash"
                        )
                    }

                } label: {

                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
