@preconcurrency import AuthenticationServices
import SwiftUI

struct VaultSettingsView: View {

    @Environment(AppSettings.self) private var settings
    @State private var autoFillEnabled: Bool?

    var body: some View {
        @Bindable var settings = settings
        ZStack {
            AppGlassBackground()
            Form {
                Section(String(localized: "Security")) {
                    Picker(String(localized: "Auto Lock"), selection: $settings.vaultAutoLockInterval) {
                        Text("30 s").tag(30)
                        Text("60 s").tag(60)
                        Text("90 s").tag(90)
                        Text("2 min").tag(120)
                        Text(String(localized: "Never")).tag(0)
                    }

                    Picker(String(localized: "Clear Clipboard"), selection: $settings.vaultClipboardClearInterval) {
                        Text("30 s").tag(30)
                        Text("60 s").tag(60)
                        Text("90 s").tag(90)
                        Text(String(localized: "Never")).tag(0)
                    }
                }

                Section("AutoFill") {
                    HStack {
                        Label("AutoFill", systemImage: "key.fill")
                        Spacer()
                        if let autoFillEnabled {
                            Label(
                                autoFillEnabled ? "Enabled" : "Not Enabled",
                                systemImage: autoFillEnabled ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(autoFillEnabled ? .green : .secondary)
                            .font(.subheadline)
                        } else {
                            ProgressView()
                        }
                    }

                    Button("Check AutoFill Status") {
                        refreshAutoFillStatus()
                    }

                    if autoFillEnabled != true {
                        Text("To use AutoFill, go to Settings > General > AutoFill & Passwords, then turn on ForMemo.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle(String(localized: "Vault"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            refreshAutoFillStatus()
        }
    }

    private func refreshAutoFillStatus() {
        ASCredentialIdentityStore.shared.getState { state in
            let enabled = state.isEnabled
            Task { @MainActor in
                autoFillEnabled = enabled
            }
        }
    }
}
