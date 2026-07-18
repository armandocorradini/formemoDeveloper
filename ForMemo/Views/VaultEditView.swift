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
    @State private var customerNumber = ""
    @State private var recoveryCode = ""
    @State private var securityQuestion = ""
    @State private var securityAnswer = ""
    @State private var otpSecret = ""
    @State private var passwordExpiresAt = Date()
    @State private var hasPasswordExpiration = false
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

                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                    TextField("Customer Number", text: $customerNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Recovery & Security") {
                    SecureField("Recovery Code", text: $recoveryCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Security Question", text: $securityQuestion)
                    SecureField("Security Answer", text: $securityAnswer)
                    SecureField("OTP Secret", text: $otpSecret)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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

                    Toggle("Require Device Authentication Every Time", isOn: $requireBiometricEveryTime)
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
        let values = (try? VaultManager.shared.decryptedSensitiveValues(for: item))
        pin = values?.pin ?? ""
        customerNumber = values?.customerNumber ?? ""
        recoveryCode = values?.recoveryCode ?? ""
        securityQuestion = values?.securityQuestion ?? ""
        securityAnswer = values?.securityAnswer ?? ""
        otpSecret = values?.otpSecret ?? ""
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
                    requireBiometricEveryTime: requireBiometricEveryTime,
                    sensitiveValues: sensitiveValues,
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
                    sensitiveValues: sensitiveValues,
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

    private var sensitiveValues: VaultManager.SensitiveValues {
        .init(
            pin: pin,
            customerNumber: customerNumber,
            recoveryCode: recoveryCode,
            securityQuestion: securityQuestion,
            securityAnswer: securityAnswer,
            otpSecret: otpSecret,
            passwordExpiresAt: hasPasswordExpiration ? passwordExpiresAt : nil
        )
    }
}
