import SwiftUI

struct HomeView: View {
    
    @State private var isAnimating = false
    
    var body: some View {
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
            
            ScrollView {
                VStack(spacing: 40) {
                    
                    Text("\(appName)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .padding(.top, 60)
                    
                    // Icona con animazione continua (Standard 2026)
                    Image(systemName: "checkmark.circle.dotted")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.cyan, .blue)
                    
                        .symbolEffect(.rotate.clockwise, options: .repeat(1).speed(1), value: isAnimating)
                        .symbolEffect(.pulse, options: .repeat(nil).speed(0.3), value: isAnimating)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isAnimating = true
                            }
                        }
                        .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    
                    // Contenuto riempitivo per forzare lo scroll (opzionale)
                    // Se la vista è corto, la barra non si minimizzerà
                    Text("Manage your tasks with ease.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer(minLength: 100)
                    
                    // Footer con stile minimal
                    VStack(spacing: 2) {
                        Text("from")
                            .font(.subheadline)
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        Text("armando ♾️ corradini")
                            .font(.system(.body, design: .serif))
                            .italic()
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }
            // Background Mesh: il tocco di classe 2026
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
}
