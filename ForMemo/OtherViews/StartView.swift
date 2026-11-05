import SwiftUI
import SwiftData

struct StartView: View {
    
    @State private var isAnimating = false
    @State private var isDeveloperPopoverPresented = false

    
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
                            .linear(duration: 0.9),
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
                        Button {
                            isDeveloperPopoverPresented = true
                        } label: {
                            Text("armando ♾️ corradini")
                                .font(.system(.body, design: .serif))
                                .italic()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "About the developer"))
                        .popover(isPresented: $isDeveloperPopoverPresented) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("A note from the developer")
                                    .font(.headline)

                                Text("Hi, I'm Armando. I created ForMemo to build something useful, starting from a personal need and with the help of artificial intelligence.")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)

                                Text("There are no ads, subscriptions, or in-app purchases. Just the pleasure of sharing a tool that may be useful to others.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("ForMemo is driven by curiosity, a passion for technology, and the joy of learning by creating.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(20)
                            .frame(width: 300, alignment: .leading)
                            .presentationCompactAdaptation(.popover)
                        }
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
        
    }
    private var appVersionString: String {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build =
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}
