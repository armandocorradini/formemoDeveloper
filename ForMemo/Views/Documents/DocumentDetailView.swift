import SwiftUI
import SwiftData

struct DocumentDetailView: View {

    @Bindable var document: DocumentItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {

        Form {

            Section {

                TextField(
                    String(localized: "Name"),
                    text: $document.name
                )

                Picker(
                    String(localized: "Document Type"),
                    selection: $document.documentTypeRaw
                ) {

                    ForEach(DocumentType.allCases, id: \.rawValue) { type in
                        Label(
                            String(localized: type.localizedTitle),
                            systemImage: type.systemImage
                        )
                        .tag(type.rawValue)
                    }
                }
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
            } header: {
                Text(String(localized: "Information"))
            }

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
                            document.expiryDate = $0
                        }
                    ),
                    displayedComponents: .date
                )

            } header: {
                Text(String(localized: "Dates"))
            }

            Section {

                TextEditor(text: $document.notes)
                    .frame(minHeight: 120)

            } header: {
                Text(String(localized: "Notes"))
            }

            if let days = document.daysRemaining {

                Section {

                    HStack {
                        Text(String(localized: "Days Remaining"))
                        Spacer()
                        Text("\(days)")
                            .foregroundStyle(.secondary)
                    }

                } header: {
                    Text(String(localized: "Status"))
                }
            }
        }
        .navigationTitle(document.name.isEmpty ? String(localized: "Document") : document.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {

            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Save")) {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DocumentDetailView(
            document: DocumentItem(name: "Passport")
        )
    }
}
