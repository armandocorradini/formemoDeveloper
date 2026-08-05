import SwiftUI

struct TabBarCustomizationView: View {
    @Environment(AppSettings.self) private var settings
    @State private var tabs: [AppTab] = []

    var body: some View {
        List {
            Section {
                ForEach(tabs) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        Text(tab.title(using: settings))

                        Spacer()

                        if !tab.isVisible(using: settings) {
                            Text("Hidden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(tab.isVisible(using: settings) ? 1 : 0.55)
                }
                .onMove(perform: moveTabs)
            } header: {
                Text("Tab order")
            } footer: {
                Text("Drag sections to choose their order. Hidden sections keep their position and return there when enabled again.")
            }
        }
        .contentMargins(.bottom, 70, for: .scrollContent)
        .navigationTitle("Customize Tab Bar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Reset") {
                    tabs = AppTab.defaultOrder
                    settings.tabOrder = tabs.map(\.rawValue)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onAppear {
            tabs = settings.orderedTabs
        }
        .onChange(of: settings.tabOrder) { _, _ in
            tabs = settings.orderedTabs
        }
    }

    private func moveTabs(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        settings.tabOrder = tabs.map(\.rawValue)
    }
}
