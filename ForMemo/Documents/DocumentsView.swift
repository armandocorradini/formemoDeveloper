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
            || $0.storageLocation.localizedCaseInsensitiveContains(searchText)
            || $0.documentNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {

            AppGlassBackground()

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
                            .onAppear {
                                document.lastOpenedAt = Date()
                                try? modelContext.save()
                            }
                    } label: {

                        HStack(spacing: 12) {

                            Image(systemName: document.documentType.systemImage)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    iconPrimaryColor(for: document),
                                    iconSecondaryColor(for: document)
                                )
                                .font(.title3)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 4) {

                                Text(document.name)
                                    .font(.headline)

//                                if !document.storageLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//                                    Label(document.storageLocation, systemImage: "archivebox")
//                                        .font(.caption)
//                                        .foregroundStyle(.secondary)
//                                }

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
                        
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteDocument(
                                    document,
                                    in: modelContext
                                )
                            } label: {
                                Label(
                                    "Delete",
                                    systemImage: "trash"
                                )
                            }
                        }
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
            .background(Color.clear)
            .navigationTitle(String(localized: "Document Expiry"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("Search documents")
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Documents")
                            .font(.headline)

                        Text(
                            "\(documents.count) documents"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newDocument = DocumentItem(name: "")
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                            .padding(.trailing, 5)
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

    private func iconPrimaryColor(for document: DocumentItem) -> Color {
        switch document.documentType {
        case .idCard:
            return .indigo
        case .passport:
            return .blue
        case .drivingLicence:
            return .orange
        case .healthCard:
            return .red
        case .carInsurance:
            return .green
        case .motorbikeInsurance:
            return .mint
        case .homeInsurance:
            return .teal
        case .lifeInsurance:
            return .pink
        case .medicalCertificate:
            return .cyan
        case .vaccinationCertificate:
            return .green
        default:
            return .accentColor
        }
    }

    private func iconSecondaryColor(for document: DocumentItem) -> Color {
        switch document.documentType {
        case .idCard:
            return .blue
        case .passport:
            return .cyan
        case .drivingLicence:
            return .yellow
        case .healthCard:
            return .pink
        case .carInsurance:
            return .mint
        case .motorbikeInsurance:
            return .blue
        case .homeInsurance:
            return .green
        case .lifeInsurance:
            return .red
        case .medicalCertificate:
            return .teal
        case .vaccinationCertificate:
            return .mint
        default:
            return .secondary
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


