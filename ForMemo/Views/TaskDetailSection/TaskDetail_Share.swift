import SwiftUI
import UniformTypeIdentifiers
import CoreLocation


// MARK: - ShareSheet
struct ShareSheet: View {
    
    let task: TodoTask
    let attachments: [TaskAttachment]
    let onShare: ([Any]) -> Void
    let onCancel: () -> Void
    
    @State private var includeText = true
    @State private var includeDescription = true
    @State private var includeDeadline = false
    @State private var includeLocation = false
    
    @State private var selectedAttachments: Set<UUID> = []
    
    @AppStorage("navigationApp") private var navigationAppRaw = NavigationApp.appleMaps.rawValue
    private var navigationApp: NavigationApp {
        NavigationApp(rawValue: navigationAppRaw) ?? .appleMaps
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Toggle("Include title", isOn: $includeText)
                    
                    if !task.taskDescription.isEmpty {
                        Toggle("Include description", isOn: $includeDescription)
                    }
                    
                    if task.deadLine != nil {
                        Toggle("Include deadline", isOn: $includeDeadline)
                    }
                    
                    if task.locationCoordinate != nil {
                        Toggle("Include location", isOn: $includeLocation)
                    }
                }
                
                if !attachments.isEmpty {
                    Section("Attachments") {
                        HStack {
                            Button("Select All") {
                                selectedAttachments = Set(attachments.map { $0.id })
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            Spacer()
                            Button("Deselect All") {
                                selectedAttachments.removeAll()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                        
                        // Lista allegati: riga cliccabile per selezione/deselezione
                        ForEach(attachments) { att in
                            HStack(spacing: 12) {
                                if isImage(att), let url = att.fileURL,
                                   let image = UIImage(contentsOfFile: url.path) {                                        Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                } else {
                                    Image(systemName: iconName(for: att))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text(att.originalName)
                                Spacer()
                                
                                // ✅ Toggle direttamente legato allo Set globale
                                Toggle("", isOn: Binding(
                                    get: { selectedAttachments.contains(att.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedAttachments.insert(att.id)
                                        } else {
                                            selectedAttachments.remove(att.id)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share Task")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        onShare(buildShareItems())
                    }
                    .disabled(!canShare)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
    
    private var canShare: Bool {
        includeText || includeDescription || includeDeadline || includeLocation || !selectedAttachments.isEmpty
    }
    
    private func buildShareItems() -> [Any] {
        var items: [Any] = []
        
        // --- Testo principale
        var text = ""
        if includeText { text += task.title }
        if includeDescription, !task.taskDescription.isEmpty {
            if !text.isEmpty { text += "\n\n" }
            text += task.taskDescription
        }
        if includeDeadline, let deadline = task.deadLine {
            if !text.isEmpty { text += "\n\n" }
            text += String(localized:"Deadline: \(deadline.formatted(date: .long, time: .shortened))")
        }
        if !text.isEmpty { items.append(text) }
        // --- Location come link
        if includeLocation, let coordinate = task.locationCoordinate {
            let locationText = String(localized:"\nLocation: \(task.locationName ?? "no location set")\n")// Riga vuota prima
            items.append(locationText)
            
            let url: URL?
            switch navigationApp {
            case .appleMaps:
                url = URL(string: "http://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)")
            case .googleMaps:
                url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)")
            }
            //                }
            if let url { items.append(url) } // link cliccabile
        }
        
        // --- Allegati selezionati
        for att in attachments where selectedAttachments.contains(att.id) {
            
            guard let url = att.fileURL else { continue }
            
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }
        
        
        return items
    }
    
    // MARK: - Helpers
    private func isImage(_ attachment: TaskAttachment) -> Bool {
        guard let type = UTType(mimeType: attachment.contentType) ?? UTType(attachment.contentType) else { return false }
        return type.conforms(to: .image)
    }
    
    private func iconName(for attachment: TaskAttachment) -> String {
        guard let type = UTType(mimeType: attachment.contentType) ?? UTType(attachment.contentType) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .movie) { return "film" }
        return "doc"
    }
    
    @State private var imageCache: [UUID: UIImage] = [:]
    
    private func loadImageAsync(for attachment: TaskAttachment) async {
        
        guard imageCache[attachment.id] == nil else { return }
        
        if let data = await attachment.loadDataAsync(),
           let image = UIImage(data: data) {
            
            imageCache[attachment.id] = image
        }
    }
    
    
    func temporaryCopy(
        of url: URL
    ) throws -> URL {
        
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        
        try FileManager.default.copyItem(
            at: url,
            to: temp
        )
        
        return temp
    }
}


// MARK: - ActivityView

struct ActivityView: UIViewControllerRepresentable {
    
    let items: [Any]
    
    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }
    
    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
