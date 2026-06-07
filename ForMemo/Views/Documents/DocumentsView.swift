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
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(iconColor(for: document))
                                .font(.title3)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 4) {

                                Text(document.name)
                                    .font(.headline)

                                if let expiryDate = document.expiryDate {

                                    HStack(spacing: 6) {

                                        Text(
                                            expiryDate.formatted(
                                                date: .abbreviated,
                                                time: .omitted
                                            )
                                        )
                                        .font(.caption2)

                                        if document.notificationEnabled,
                                           let reminderDate = Calendar.current.date(
                                                byAdding: .day,
                                                value: -document.notificationDaysBefore,
                                                to: expiryDate
                                           ) {

                                            Image(systemName: "bell.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                                .padding(.leading, 4)

                                            Text(
                                                reminderDate.formatted(
                                                    date: .abbreviated,
                                                    time: .omitted
                                                )
                                            )
                                            .font(.caption2)
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Circle()
                                .fill(statusColor(for: document))
                                .frame(width: 10, height: 10)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        Color(.systemBackground).opacity(0.3)
                    )
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(String(localized: "Document Expiry"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("Search documents")
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newDocument = DocumentItem(name: "")
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
    }

    private func iconColor(for document: DocumentItem) -> Color {
        switch document.documentType {

        case .idCard:
            return .indigo

        case .passport:
            return .blue

        case .drivingLicence:
            return .orange

        case .healthCard:
            return .red

        case .carInsurance,
             .motorbikeInsurance,
             .homeInsurance,
             .lifeInsurance:
            return .green

        case .medicalCertificate,
             .vaccinationCertificate:
            return .teal

        default:
            return .accentColor
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
