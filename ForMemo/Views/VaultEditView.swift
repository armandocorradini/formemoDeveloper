import SwiftUI
import SwiftData
import os

struct VaultEditView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: VaultItem?

    @State private var title = ""
    @State private var category: VaultCategory = .website
    @State private var icon: VaultIcon = .lockShield
    @State private var color: VaultColor = .blue
    @State private var username = ""
    @State private var email = ""
    @State private var website = ""
    @State private var notes = ""
    @State private var password = ""
    @State private var requireBiometricEveryTime =
        VaultLock.hasBiometricAuthentication
    @State private var originalPassword = ""
    @State private var showingPasswordChangeConfirmation = false
    
    init(item: VaultItem? = nil) {
        self.item = item
    }

    var body: some View {
        ZStack {
            AppGlassBackground()
            Form {
                Section("General") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(VaultCategory.allCases, id: \.self) {
                            Text($0.localizedTitle)
                                .tag($0)
                        }
                    }
                    Picker("Icon", selection: $icon) {
                        ForEach(VaultIcon.allCases, id: \.rawValue) { vaultIcon in
                            Image(systemName: vaultIcon.rawValue)
                                .tag(vaultIcon)
                        }
                    }

                    Picker("Color", selection: $color) {
                        ForEach(VaultColor.allCases, id: \.self) { color in
                            Text(color.rawValue.capitalized)
                                .foregroundStyle(color.swiftUIColor)
                                .tag(color)
                        }
                    }
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    VaultPasswordField(
                        password: $password,
                        requireBiometricEveryTime: requireBiometricEveryTime,
                        authenticateBeforeEditing: true,
                        authenticateBeforeGenerating: true
                    )
                }

                Section("Additional") {
                    TextField("Website", text: $website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)

                    Toggle("Require Device Authentication Every Time", isOn: $requireBiometricEveryTime)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle(item == nil ? "New Credential" : "Edit Credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if item != nil && password != originalPassword {
                            showingPasswordChangeConfirmation = true
                        } else {
                            saveConfirmed()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
            .alert("Change Password?", isPresented: $showingPasswordChangeConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Change", role: .destructive) {
                    saveConfirmed()
                }
            } message: {
                Text("The current password will be replaced. Make sure you have updated it for the corresponding account.")
            }
        }
    }

    private func load() {
        guard let item else { return }
        title = item.title
        category = item.category
        icon = item.icon
        color = item.color
        username = item.username
        email = item.email
        website = item.website
        notes = item.notes
        requireBiometricEveryTime = item.requireBiometricEveryTime

        password = (try? VaultManager.shared.decryptedPassword(for: item)) ?? ""
        originalPassword = password
    }

    private func saveConfirmed() {
        if let item {
            do {
                try VaultManager.shared.updateCredential(
                    item,
                    title: title,
                    category: category,
                    username: username,
                    email: email,
                    website: website,
                    notes: notes,
                    password: password,
                    icon: icon,
                    color: color,
                    requireBiometricEveryTime: requireBiometricEveryTime,
                    in: modelContext
                )
            } catch {
                AppLogger.persistence.error(
                    "Vault credential update failed: \(error.localizedDescription)"
                )
                return
            }
        } else {
            do {
                _ = try VaultManager.shared.createCredential(
                    title: title,
                    category: category,
                    username: username,
                    email: email,
                    website: website,
                    notes: notes,
                    password: password,
                    icon: icon,
                    color: color,
                    requireBiometricEveryTime: requireBiometricEveryTime,
                    in: modelContext
                )
            } catch {
                AppLogger.persistence.error(
                    "Vault credential creation failed: \(error.localizedDescription)"
                )
                return
            }
            
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        VaultEditView()
            .modelContainer(for: VaultItem.self, inMemory: true)
    }
}
