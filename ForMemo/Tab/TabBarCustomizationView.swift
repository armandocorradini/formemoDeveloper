
import SwiftUI

struct TabBarCustomizationView: View {
    @Environment(AppSettings.self) private var settings
    @State private var tabs: [AppTab] = []

    var body: some View {
        ZStack{
            AppGlassBackground()
            List {
                
                Section {
                    HStack(alignment: .center, spacing: 15){
                        Text(String(localized: "Icon color"))

                        ColorPicker(
                            "",
                            selection: Binding(
                                get: {
                                    Color(hex: settings.tabBarCustomizationIconColorHex) ?? .blue
                                },
                                set: { newColor in
                                    settings.tabBarCustomizationIconColorHex =
                                        newColor.toHex() ?? settings.tabBarCustomizationIconColorHex
                                }
                            )
                        )
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(tabs) { tab in
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .foregroundStyle(
                                    Color(hex: settings.tabBarCustomizationIconColorHex) ?? .blue
                                )
                                .frame(width: 22)

                            Text(tab.title(using: settings))
                                .foregroundStyle(.primary)
                                .font(.body)

                            Spacer()

                            if !tab.isVisible(using: settings) {
                                Text("Hidden")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 10)
                        .frame(height: 40)
                        .opacity(tab.isVisible(using: settings) ? 1 : 0.55)
                        .background(
                            Color.secondary.opacity(0.6),
                            in: .rect(cornerRadius: 12)
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                    .onMove(perform: moveTabs)

                    Text("Drag sections to choose their order. Hidden sections keep their position and return there when enabled again.")
                        .font(.footnote)
                        .padding(.top,10)
                    
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Tab order")
                }
            }
            
        }
        .listStyle(.plain)
        .listRowSpacing(-8)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .background(Color.clear)
            .contentMargins(.bottom, 70, for: .scrollContent)
            .navigationTitle("Customize Tab Bar")
            .scrollEdgeEffectHidden(true, for: .top)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        tabs = AppTab.defaultOrder
                        settings.tabOrder = tabs.map(\.rawValue)
                        settings.tabBarCustomizationIconColorHex = Color.blue.toHex() ?? ""
                    }            }
                
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
