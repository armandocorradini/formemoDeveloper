import SwiftUI
import SwiftData

struct StartView: View {
    
    @State private var isAnimating = false
    
    @Environment(\.modelContext) private var modelContext

    
    private var activeAttachmentsCount: Int {
        activeTasks.reduce(0) { total, task in
            total + (task.attachments?.count ?? 0)
        }
    }

    private var activeAttachmentBytes: Int64 {
        activeTasks
            .flatMap { $0.attachments ?? [] }
            .reduce(Int64(0)) { total, attachment in
                guard
                    let url = attachment.fileURL,
                    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                else {
                    return total
                }
                return total + Int64(size)
            }
    }
    
    private func updateAttachmentDiagnostic() {
        AppSettings.shared.diagnosticAttachmentFailure =
            activeAttachmentsCount > 0 &&
            activeAttachmentBytes == 0
    }
    
    @Query(filter: #Predicate<TodoTask> { !$0.isCompleted })
    private var activeTasks: [TodoTask]
    
    var body: some View {
        ZStack {
            AppGlassBackground()
            
            ScrollView {
                VStack(spacing: 40) {
                    
                    Text("\(appName)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .padding(.top, 60)
                    
                    // Animated app symbol
                    Image(systemName: "checkmark.circle.dotted")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.cyan, .blue)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(
                            .linear(duration: 0.7),
                            value: isAnimating
                        )
                        .onReceive(
                            NotificationCenter.default.publisher(
                                for: Notification.Name("StartStartIconRotationFast")
                            )
                        ) { _ in
                            isAnimating = true
                        }
                        .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Text("Manage your tasks with ease.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer(minLength: 100)
                    
                    // Footer
                    VStack(spacing: 2) {
//                        Text("from")
//                            .font(.subheadline)
//                            .tracking(2)
//                            .foregroundStyle(.secondary)
                        Text("armando ♾️ corradini")
                            .font(.system(.body, design: .serif))
                            .italic()
                        Text(appVersionString)
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.8))
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 60)
                }
                .frame(maxWidth: .infinity)
            }
            .background {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ], colors: [
                    .cyan.opacity(0.1), .blue.opacity(0.05), .blue.opacity(0.1),
                    .clear, .clear, .clear,
                    .blue.opacity(0.1), .clear, .cyan.opacity(0.1)
                ])
                .ignoresSafeArea()
            }
        }
        
        .task {
            updateAttachmentDiagnostic()
        }
    }
    private var appVersionString: String {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build =
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}
