import SwiftUI
import SwiftData

struct DocumentsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentItem.expiryDate)
    private var documents: [DocumentItem]

    @State private var searchText = ""
    @State private var newDocument: DocumentItem?

    var filteredDocuments: [DocumentItem] {

        guard !searchText.isEmpty else {
            return documents
        }

        return documents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {

        List {

            if filteredDocuments.isEmpty {

                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc.text.fill",
                    description: Text("Tap + to add a document")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(filteredDocuments) { document in

                NavigationLink {
                    DocumentDetailView(document: document)
                } label: {

                    HStack(spacing: 12) {

                        Image(systemName: document.documentType.systemImage)
                            .font(.title3)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {

                            Text(document.name)
                                .font(.headline)

                            if let expiryDate = document.expiryDate {
                                Text(expiryDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Circle()
                            .fill(statusColor(for: document))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    deleteDocument(
                        filteredDocuments[index],
                        in: modelContext
                    )
                }
            }
        }
        .contentMargins(.bottom, 70, for: .scrollContent)
        .navigationTitle(String(localized: "Documents"))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always)
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let document = DocumentItem(name: "")
                    modelContext.insert(document)
                    try? modelContext.save()
                    newDocument = document
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $newDocument) { document in
            NavigationStack {
                DocumentDetailView(document: document)
            }
        }
    }

    private func statusColor(for document: DocumentItem) -> Color {

        switch document.expiryStatus {
        case .expired:
            return .red
        case .warning:
            return .orange
        case .upcoming:
            return .yellow
        case .valid:
            return .green
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsView()
    }
}
