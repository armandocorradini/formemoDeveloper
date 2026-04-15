import SwiftUI

struct ImportCard<Content: View>: View {
    
    let isSelected: Bool
    let content: Content
    
    init(isSelected: Bool, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.background)
                    .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? .blue : .clear, lineWidth: 2)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
