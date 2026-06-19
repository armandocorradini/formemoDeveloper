import SwiftUI

struct StartView: View {
    
    @State private var isAnimating = false
    
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
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(
                            .linear(duration: 2),
                            value: isAnimating
                        )
                        .foregroundStyle(
                            LinearGradient(
                                stops: [
                                    .init(color: .purple,    location: 0.00),

                                    .init(color: .red,    location: 0.12),
                                    
                                    .init(color: .red,    location: 0.25),
                                    
                                    .init(color: .orange, location: 0.35),

                                    .init(color: .yellow, location: 0.40),

                                    .init(color: .green,  location: 0.45),

                                    .init(color: .cyan,   location: 0.50),

                                    .init(color: .blue,   location: 0.60),

                                    .init(color: .purple, location: 0.70),

                                    .init(color: .red, location: 1.00)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .fontWeight(.bold)
                        .symbolEffect(
                            .pulse,
                            options: .repeat(nil).speed(0.35),
                            value: isAnimating
                        )
//                        .symbolEffect(
//                            .bounce,
//                            options: .repeat(nil).speed(0.20),
//                            value: isAnimating
//                        )
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isAnimating = true
                            }
                        }
                        .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Text("Manage your tasks with ease.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer(minLength: 100)
                    
                    // Footer
                    VStack(spacing: 2) {
                        Text("from")
                            .font(.subheadline)
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        Text("armando ♾️ corradini")
                            .font(.system(.body, design: .serif))
                            .italic()
                        Text(appVersionString)
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.7))
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
