import SwiftUI
import SwiftData

struct VaultDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var showCopiedToast = false
    
    let item: VaultItem

    @State private var showingPassword = false
    @State private var decryptedPassword = ""
    @State private var sensitiveValues = VaultManager.SensitiveValues()
    @State private var revealedFields = Set<String>()
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var autoHideTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            AppGlassBackground()
            List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: item.icon.rawValue)
                        .font(.system(size: 42))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.color.swiftUIColor)
                        .padding(16)
                        .background(.regularMaterial, in: Circle())

                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .minimumScaleFactor(0.8)
                    Text(item.category.localizedTitle)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())

                    if !item.website.isEmpty {
                        Text(item.website)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                if !item.username.isEmpty {
                    HStack {
                        LabeledContent("Username", value: item.username)
                        Button {
                            copy(item.username)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                    .textSelection(.enabled)
                }

                if !item.email.isEmpty {
                    HStack {
                        LabeledContent("Email", value: item.email)
                        Button {
                            copy(item.email)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                    .textSelection(.enabled)
                }
            }
            .listRowBackground(Color(.systemBackground).opacity(0.3))

            Section("Password") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(showingPassword ? decryptedPassword : "••••••••••")
                        .font(.body.monospaced())
                        .textSelection(.enabled)

                    Button(showingPassword ? "Hide Password" : "Show Password") {
                        Task {
                            await togglePassword()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if showingPassword {
                        Button {
                            copy(decryptedPassword)
                        } label: {
                            Label("Copy Password", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .listRowBackground(Color(.systemBackground).opacity(0.3))

            if item.encryptedPIN != nil || item.encryptedCustomerNumber != nil || item.encryptedRecoveryCode != nil {
                Section("Sensitive Information") {
                    if item.encryptedPIN != nil { sensitiveRow("PIN", value: sensitiveValues.pin, id: "pin") }
                    if item.encryptedCustomerNumber != nil { sensitiveRow("Customer Number", value: sensitiveValues.customerNumber, id: "customerNumber") }
                    if item.encryptedRecoveryCode != nil { sensitiveRow("Recovery Code", value: sensitiveValues.recoveryCode, id: "recoveryCode") }
                }
                .listRowBackground(Color(.systemBackground).opacity(0.3))
            }

            if item.encryptedSecurityQuestion != nil || item.encryptedSecurityAnswer != nil {
                Section("Security Questions") {
                    if item.encryptedSecurityQuestion != nil { sensitiveRow("Security Question", value: sensitiveValues.securityQuestion, id: "securityQuestion") }
                    if item.encryptedSecurityAnswer != nil { sensitiveRow("Security Answer", value: sensitiveValues.securityAnswer, id: "securityAnswer") }
                }
                .listRowBackground(Color(.systemBackground).opacity(0.3))
            }

            if item.encryptedOTPSecret != nil {
                Section("One-Time Password") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let code = VaultManager.shared.currentTOTP(for: sensitiveValues.otpSecret, at: context.date) ?? "Invalid secret"
                        let remaining = max(0, 30 - Int(context.date.timeIntervalSince1970) % 30)
                        HStack {
                            VStack(alignment: .leading) {
                                Text(code).font(.title3.monospacedDigit().weight(.semibold))
                                Text("Refreshes in \(remaining)s").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { copy(code) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.plain)
                        }
                    }
                    sensitiveRow("OTP Secret", value: sensitiveValues.otpSecret, id: "otpSecret")
                }
                .listRowBackground(Color(.systemBackground).opacity(0.3))
            }

            if !item.website.isEmpty {
                Section("Website") {
                    if let url = URL(string: item.website.hasPrefix("http") ? item.website : "https://\(item.website)") {
                        Link(destination: url) {
                            Label("Open Website", systemImage: "safari")
                        }
                    }
                }
                .listRowBackground(Color(.systemBackground).opacity(0.3))
            }

            if !item.notes.isEmpty {
                Section("Notes") {
                    Text(item.notes)
                        .textSelection(.enabled)
                }
                .listRowBackground(Color(.systemBackground).opacity(0.3))
            }

            Section("Information") {
                LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Modified", value: item.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                if let changed = item.passwordUpdatedAt {
                    LabeledContent(
                        "Password Updated",
                        value: changed.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                if let expires = item.passwordExpiresAt {
                    LabeledContent("Password Expires", value: expires.formatted(date: .abbreviated, time: .omitted))
                }
                if let viewed = item.lastViewedAt {
                    LabeledContent("Last Viewed", value: viewed.formatted(date: .abbreviated, time: .shortened))
                }
                if let copied = item.lastCopiedAt {
                    LabeledContent("Last Copied", value: copied.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .listRowBackground(Color(.systemBackground).opacity(0.3))
            }
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 30)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onDisappear {

                autoHideTask?.cancel()
                autoHideTask = nil

            }
            .task {
                sensitiveValues = (try? VaultManager.shared.decryptedSensitiveValues(for: item)) ?? .init()
                try? VaultManager.shared.registerView(of: item, in: modelContext)
            }
            
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 70, for: .scrollContent)
            .alert(errorMessage, isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func togglePassword() async {
        if showingPassword {
            autoHideTask?.cancel()
            autoHideTask = nil
            decryptedPassword = ""
            showingPassword = false
            return
        }

        guard let encrypted = item.encryptedPassword,
              !encrypted.isEmpty else {
            errorMessage = "No password saved"
            showingError = true
            return
        }

        do {
           
            decryptedPassword = try VaultManager.shared.decryptedPassword(for: item)
            showingPassword = true
            
            autoHideTask?.cancel()

            autoHideTask = Task {

                try? await Task.sleep(for: .seconds(15))

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {

                    decryptedPassword = ""
                    showingPassword = false
                    autoHideTask = nil

                }
            }
            try? VaultManager.shared.registerView(of: item, in: modelContext)
            VaultLock.shared.userDidAccessVault()
        } catch {
            errorMessage = "Unable to decrypt the password"
            showingError = true
        }
    }
    
    private func showCopied() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedToast = true
        }

        Task {
            try? await Task.sleep(for: .seconds(1.2))

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    showCopiedToast = false
                }
            }
        }
    }

    @ViewBuilder
    private func sensitiveRow(_ label: String, value: String, id: String) -> some View {
        HStack {
            LabeledContent(label, value: revealedFields.contains(id) ? value : String(repeating: "•", count: 10))
                .font(.body.monospaced())
            Button {
                if revealedFields.contains(id) { revealedFields.remove(id) } else { revealedFields.insert(id) }
            } label: { Image(systemName: revealedFields.contains(id) ? "eye.slash" : "eye") }
                .buttonStyle(.plain)
            Button { copy(value) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain)
        }
    }

    private func copy(_ value: String) {
        SecureClipboard.copy(value)
        try? VaultManager.shared.registerCopy(of: item, in: modelContext)
        showCopied()
    }
    
    
}
