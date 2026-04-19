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
                    Section{
                        VStack(alignment: .leading, spacing: 24) {
                            
                            Text(String(localized: "Add a task in \(appName)"))
                                .padding(.top, 15)
                            Divider()
                            
                            Text(String(localized: "Create a task in \(appName)"))
                            Divider()
                            
                            Text(String(localized: "Remind me using \(appName)"))
                            Divider()
                            
                            Text(String(localized: "New \(appName)"))
                                .padding(.bottom, 15)
                        }
                    }
                    header: {
                        Text("Try saying 'Hey Siri,' followed by:")
                    } footer: {
                        Text("Siri will ask for the activity title and due date, then create the record with an automatic reminder.")
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Ask to Siri") // SwiftUI localizza automaticamente le stringhe letterali
                .navigationBarTitleDisplayMode(.inline)
                .padding(.top,30)
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
