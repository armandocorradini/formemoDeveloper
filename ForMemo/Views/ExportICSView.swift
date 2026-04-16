import SwiftUI

struct ExportICSView: View {
    
    var body: some View {
        NavigationStack {
            AppUnavailableView.empty("ICS export coming soon", systemImage: "doc")
            .navigationTitle("Export ICS")
        }
    }
}
