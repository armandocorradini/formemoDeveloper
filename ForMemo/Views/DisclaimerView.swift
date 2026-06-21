import SwiftUI

struct DisclaimerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let  disclaimer_title = String(localized:"Disclaimer")
    
    let disclaimer_button = String(localized:"View Disclaimer")
    
    let disclaimer_text = String(localized:"Disclaimer and Terms of Use\n\nThe \(appName) App (\"App\") is designed for personal task management, organization, and productivity purposes.\n\nBy using the App, you acknowledge and agree to the following:\n\n1. Purpose of the App: The App is intended solely for personal organization. All information, suggestions, forecasts, and features are provided for informational purposes only and do not constitute any guarantee of execution, accuracy, or outcome.\n\n2. User Responsibility: The App is provided \"as is\", without warranties of any kind, express or implied. You are solely responsible for your decisions, actions, activities, and use of the information provided by the App.\n\n3. Notifications, Badges, and Reminders: Notifications, app icon badges, reminders, and snooze functions are provided for informational purposes only. While the App is designed to schedule notifications at the appropriate time, their delivery and accuracy depend on system-level services, device settings, connectivity, and external factors. The App does not guarantee their timely delivery, accuracy, or proper functioning. You should not rely exclusively on these features for critical or time-sensitive tasks.\n\n4. Location-Based Reminders: Location-based reminders depend on system permissions, device conditions, GPS availability, and external factors, and may not always trigger as expected.\n\n5. Voice Assistant (Siri): Voice commands and Siri integrations rely on Apple services and may not always interpret user input accurately or consistently.\n\n6. Map and Location Features: Map visualization and location-based features depend on device location services, GPS accuracy, network connectivity, and system conditions. The App does not guarantee the accuracy, precision, availability, or real-time reliability of location data or map-based interactions.\n\n7. Weather Information: Weather forecasts and weather-related information are provided for informational purposes only and may depend on third-party services, device location, network connectivity, and external data providers. Hourly forecasts, daily forecasts, and weather conditions may vary from other weather services. The App does not guarantee the accuracy, completeness, availability, or reliability of weather information and such information should not be relied upon for safety-critical or professional decisions.\n\n8. Loyalty Cards, Logos, and Barcodes: Loyalty cards, tickets, barcode information, QR code information, card logos, ticket images, and related data are stored for user convenience only. The App does not guarantee compatibility with external scanners, retail systems, stores, or third-party services. Users are responsible for verifying the validity and usability of stored barcode information.\n\n9. Data and Storage: Data may be stored locally on your device or synchronized via iCloud. You are responsible for managing and backing up your data. The developers are not responsible for any data loss, corruption, unauthorized access, synchronization issues, delays, or failures related to local storage or cloud services.\n\n10. Backups and Synchronization: Backup, restore, and synchronization features depend on device conditions, storage availability, iCloud services, and external factors. Backups may include tasks, reminders, recurrence rules, tags, priorities, locations, attachments, loyalty cards, tickets, logos, trip lists, documents, app settings, and related data. Restore operations may allow selective restoration of supported data categories and settings. The App does not guarantee that backups or synchronized data will always be available, complete, accurate, or recoverable.\n\n11. Third-Party Services: The App may rely on third-party services (such as iCloud, Maps services, weather providers, or Siri) for certain features. The developers are not responsible for the availability, performance, compatibility, reliability, or privacy practices of such services.\n\n12. Feature Availability: The functionality of the App may depend on device conditions, system settings, granted permissions, software versions, and network connectivity. Continuous availability or correct operation of all features is not guaranteed.\n\n13. Import and Export Features: Import and export functionalities are provided for convenience. The App does not guarantee full data fidelity, completeness, compatibility, or preservation of all information when interacting with third-party formats or services. Data availability during import and export operations depends on the selected format and supported features.\n\n14. No Critical Use: The App is not intended for emergency, medical, legal, safety-critical, or mission-critical purposes. Users should not rely on the App in situations where delays, inaccuracies, failures, or missing information could result in harm, injury, damages, or significant losses.\n\n15. Updates and Changes: The App and this Disclaimer may be updated, modified, suspended, or changed over time without prior notice. Continued use of the App constitutes acceptance of such changes.\n\n16. Limitation of Liability: To the maximum extent permitted by applicable law, the developers shall not be liable for any damages arising from the use of, inability to use, or reliance upon the App or any information provided within it.\n\nBy using \(appName), you confirm that you have read, understood, and fully accepted this Disclaimer.")
    
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
