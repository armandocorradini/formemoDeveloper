import SwiftUI
import UserNotifications

struct ShortList: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 1. IL GRADIENTE (Sotto a tutto)
                LinearGradient(colors: [backColor1, backColor2],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                .ignoresSafeArea()
                
                // 2. IL MATERIAL (Effetto vetro)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "New \(appName)"))
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                
                                Text(String(localized: "Create a new task instantly using Siri."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Search \(appName)"))
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                
                                Text(String(localized: "Search tasks, reminders and notes by text using Siri."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Check \(appName)"))
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                
                                Text(String(localized: "Check upcoming tasks, reminders and due dates with Siri."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(spacing: 12) {
                                Image(systemName: "waveform.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 64))
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            
                            Text(String(localized: "Try saying 'Hey Siri,' followed by:"))
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 12)
                        }
                        .textCase(nil)
                    } footer: {
                        Text(String(localized: "Use simple voice commands with Siri to create, search and check your reminders in seconds."))
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .navigationTitle("Ask to Siri") // SwiftUI localizza automaticamente le stringhe letterali
                .navigationBarTitleDisplayMode(.inline)
                .padding(.top, 8)
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
            }
        }
    }
}
