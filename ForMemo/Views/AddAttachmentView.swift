import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

struct AddAttachmentView: View {
    
    @Environment(\.dismiss)
    private var dismiss
    
    @Environment(\.modelContext)
    private var modelContext
    
    let task: TodoTask
    
    @State private var showImporter = false
    
    var body: some View {
        
        NavigationStack {
            
            VStack(spacing: 24) {
                
                Button {
                    showImporter = true
                } label: {
                    Label("Import file", systemImage: "doc.badge.plus")
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add attachment")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        
        Task {
            
            guard let url = try? result.get().first else { return }
            
            do {
                
                try AttachmentImporter.addAttachment(
                    from: url,
                    to: task,
                    in: modelContext
                )
                
                dismiss()
                
            } catch {
                AppLogger.app.error("Attachment import failed:\(error)")
            }
        }
    }
}
