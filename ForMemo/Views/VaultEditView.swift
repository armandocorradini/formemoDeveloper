import SwiftUI
import SwiftData
import os

struct VaultEditView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vaultLock = VaultLock.shared
    
    @State private var showingLockCover = false
    @State private var hasLoaded = false
    
    let item: VaultItem?
    @State private var favorite = false
    @State private var title = ""
    @State private var category: VaultCategory = .website
    @State private var icon: VaultIcon = .lockShield
    @State private var color: VaultColor = .blue
    @State private var username = ""
    @State private var email = ""
    @State private var website = ""
    @State private var notes = ""
    @State private var password = ""
    @State private var pin = ""
    
    @State private var secrets: [SecretValue] = []
    
    @State private var passwordExpiresAt = Date()
    @State private var hasPasswordExpiration = false
    
    @State private var originalPassword = ""
    @State private var showingPasswordChangeConfirmation = false
    
    @State private var secretToDelete: Int?
    
    
    init(item: VaultItem? = nil) {
        self.item = item
    }
    
    var body: some View {
        ZStack {
            AppGlassBackground()
            Form {
                Section("General") {
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("Title", text: $title)
                        
                    }
                    
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
                    
                    Toggle("Favorite", isOn: $favorite)
                    
                }
                
                Section("Credentials") {
                    VStack(alignment: .leading, spacing: 4) {
                        
                        Text("Username")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        
                        Text("Email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VaultPasswordField(
                            password: $password,
                            authenticateBeforeEditing: true,
                            authenticateBeforeGenerating: true
                        )
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 4) {
                        
                        Text("PIN")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VaultSecureTextField(
                            title: "",
                            text: $pin,
                            keyboardType: .numberPad
                        )
                    }
                    
                    if !secrets.isEmpty {
                        
                        ForEach(Array(secrets.enumerated()), id: \.element.id) { index, _ in
                            
                            VStack(alignment: .leading, spacing: 8) {
                                
                                TextField(
                                    "Label",
                                    text: $secrets[index].label,
                                    axis: .vertical
                                )
                                
                                VaultSecureTextField(
                                    title: "Value",
                                    text: $secrets[index].value
                                )
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    secretToDelete = index
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                
                                Button(role: .destructive) {
                                    
                                    secretToDelete = index
                                    
                                } label: {
                                    
                                    Label("Delete", systemImage: "trash")
                                    
                                }
                            }
                        }
                    }
                    Button {
                        
                        secrets.append(
                            SecretValue(
                                label: "",
                                value: ""
                            )
                        )
                        
                    } label: {
                        
                        Label("Add Secret", systemImage: "plus")
                        
                    }
                    
                    
                    
                    
                }
                
                
                
                Section("Password Expiration") {
                    Toggle("Set Password Expiration", isOn: $hasPasswordExpiration)
                    if hasPasswordExpiration {
                        DatePicker("Expires", selection: $passwordExpiresAt, displayedComponents: .date)
                    }
                }
                
                Section("Additional") {
                    TextField("Website", text: $website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                    
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle(item == nil ? "New Credential" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
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
            
            .onAppear {
                
                if !hasLoaded {
                    load()
                    hasLoaded = true
                }
                
                showingLockCover = !vaultLock.isUnlocked
            }
            .alert("Change Password?", isPresented: $showingPasswordChangeConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Change", role: .destructive) {
                    saveConfirmed()
                }
            } message: {
                Text("The current password will be replaced. Make sure you have updated it for the corresponding account.")
            }
            
            .alert(
                "Delete this secret?",
                isPresented: Binding(
                    get: { secretToDelete != nil },
                    set: { if !$0 { secretToDelete = nil } }
                )
            ) {
                
                Button("Cancel", role: .cancel) {
                    secretToDelete = nil
                }
                
                Button("Delete", role: .destructive) {
                    
                    if let index = secretToDelete,
                       secrets.indices.contains(index) {
                        
                        secrets.remove(at: index)
                    }
                    
                    secretToDelete = nil
                }
                
            } message: {
                
                Text(
                    "The selected secret, including its label and value, will be permanently removed from this credential. This action cannot be undone."
                )
                
            }
            .fullScreenCover(isPresented: $showingLockCover) {
                
                VaultLockCoverView()
                    .interactiveDismissDisabled()
            }
            
            .onChange(of: vaultLock.isUnlocked) { _, unlocked in
                showingLockCover = !unlocked
            }
        }
    }
    
    private func load() {
        guard let item else { return }
        favorite = item.favorite
        title = item.title
        category = item.category
        icon = item.icon
        color = item.color
        username = item.username
        email = item.email
        website = item.website
        notes = item.notes
        
        
        password = (try? VaultManager.shared.decryptedPassword(for: item)) ?? ""
        originalPassword = password
        let values = try? VaultManager.shared.decryptedSensitiveValues(for: item)
        
        pin = values?.pin ?? ""
        secrets = values?.secrets ?? []
        
        if let expiration = values?.passwordExpiresAt {
            passwordExpiresAt = expiration
            hasPasswordExpiration = true
        }
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
                    favorite: favorite,
                    sensitiveValues: VaultManager.shared.makeSensitiveValues(
                        password: password,
                        pin: pin,
                        passwordExpiresAt: hasPasswordExpiration ? passwordExpiresAt : nil,
                        secrets: secrets
                    ),
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
                    favorite: favorite,
                    sensitiveValues: VaultManager.shared.makeSensitiveValues(
                        password: password,
                        pin: pin,
                        passwordExpiresAt: hasPasswordExpiration ? passwordExpiresAt : nil,
                        secrets: secrets
                    ),
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
