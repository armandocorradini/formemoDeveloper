import SwiftUI
import PhotosUI

struct PhotoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPickerPresented = false // Stato per l'apertura automatica
    @State private var items: [PhotosPickerItem] = []
    
    let onPhotos: ([PhotosPickerItem]) async -> Void
    
    var body: some View {
        Color.clear // Una vista vuota come contenitore
            .photosPicker(
                isPresented: $isPickerPresented,
                selection: $items,
                maxSelectionCount: 10,
                matching: .images,
                preferredItemEncoding: .automatic
            )
            .onAppear {
                // Appena lo sheet appare, attiva il picker
                isPickerPresented = true
            }
            .onChange(of: isPickerPresented) { _, newValue in
                // Se isPickerPresented diventa false e non sono state scelte foto, chiudi lo sheet
                if newValue == false && items.isEmpty {
                    dismiss()
                }
            }
            .onChange(of: items) { _, newValue in
                if !newValue.isEmpty {
                    Task {
                        await onPhotos(newValue)
                        dismiss()
                    }
                }
            }
        
    }
}

