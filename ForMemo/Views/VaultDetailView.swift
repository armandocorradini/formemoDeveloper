import SwiftUI
import SwiftData

struct VaultDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var showCopiedToast = false
    
    let item: VaultItem

    @State private var showingPassword = false
    @State private var decryptedPassword = ""
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
                            SecureClipboard.copy(item.username)
                            showCopied()
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
                            SecureClipboard.copy(item.email)
                            showCopied()
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
                            SecureClipboard.copy(decryptedPassword)
                            showCopied()
                        } label: {
                            Label("Copy Password", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .listRowBackground(Color(.systemBackground).opacity(0.3))

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
    
    
}
