import SwiftUI

struct VaultSettingsView: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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

//            Section(String(localized: "Privacy")) {
////                Toggle(String(localized: "Require Face ID"), isOn: $settings.vaultRequireFaceID)
////                Toggle(String(localized: "Hide passwords automatically"), isOn: $settings.vaultAutoHidePasswords)
//            }
        }
        .navigationTitle(String(localized: "Vault"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

