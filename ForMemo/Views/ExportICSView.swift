import SwiftUI

struct ExportICSView: View {
    
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "ICS export coming soon",
                systemImage: "doc"
            )
            .navigationTitle("Export ICS")
        }
    }
}
