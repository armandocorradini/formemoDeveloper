import SwiftUI

struct DisclaimerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let  disclaimer_title = String(localized:"Disclaimer")
    
    let disclaimer_button = String(localized:"View Disclaimer")
    
    let disclaimer_text = String(localized:"Disclaimer and Terms of Use\n\nThe \(appName) App (\"App\") is designed for personal task management and productivity purposes.\n\nBy using the App, you acknowledge and agree to the following:\n\n1. Purpose of the App: The App is intended solely for personal organization. All information, suggestions, and features are provided for informational purposes only and do not constitute any guarantee of execution or outcome.\n\n2. User Responsibility: The App is provided \"as is\", without warranties of any kind, express or implied. You are solely responsible for your decisions, actions, and activities based on the use of the App.\n\n3. Notifications, Badges, and Reminders: Notifications, app icon badges, reminders, and snooze functions are provided for informational purposes only. Their delivery and accuracy depend on system-level services, device settings, and external factors. The App does not guarantee their timely delivery, accuracy, or proper functioning. You should not rely exclusively on these features for critical or time-sensitive tasks.\n\n4. Data and Storage: Data may be stored locally on your device or synchronized via iCloud. You are responsible for managing and backing up your data. The developers are not responsible for any data loss, corruption, unauthorized access, or issues related to iCloud synchronization delays or failures.\n\n5. Third-Party Services: The App may rely on third-party services (such as iCloud) for certain features. The developers are not responsible for the availability, performance, compatibility, or privacy practices of such services.\n\n6. Feature Availability: The functionality of the App may depend on device conditions, system settings, granted permissions, and network connectivity. Continuous availability or correct operation of all features is not guaranteed.\n\n7. Import and Export Features: Import and export functionalities are provided for convenience. The App does not guarantee full data fidelity, completeness, or compatibility with third-party formats or services. Attachments are not included in import or export operations.\n\n8. Updates and Changes: The App and this Disclaimer may be updated or modified over time without prior notice. Continued use of the App constitutes acceptance of such changes.\n\n9. Limitation of Liability: To the maximum extent permitted by applicable law, the developers shall not be liable for any damages arising from the use of, or inability to use, the App.\n\nBy using \(appName), you confirm that you have read, understood, and fully accepted this Disclaimer.")
    
    var body: some View {
        NavigationStack {
            Text(LocalizedStringKey(disclaimer_title))
                .font(.title3).bold()
            ScrollView {
                Text(LocalizedStringKey(disclaimer_text))
                    .padding()
                    .font(.body)
                    .multilineTextAlignment(.leading)
            }
            //            .navigationTitle(LocalizedStringKey(disclaimer_title))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
