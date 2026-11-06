import SwiftUI

// MARK: - Alternative gradient backgrounds
struct StatusEditorView1 {
    
    let colors: [Color]
    @Binding var selectedColor: Color

    var gradientBackground: some View {
        LinearGradient(
            colors: [selectedColor, selectedColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

