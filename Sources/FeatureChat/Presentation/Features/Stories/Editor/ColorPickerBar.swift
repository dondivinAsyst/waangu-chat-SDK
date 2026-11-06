import SwiftUI
// MARK: - ColorPickerBar.swift
struct ColorPickerBar: View {
    let colors: [Color]
    @Binding var selectedColor: Color
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(colors.indices, id: \.self) { index in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedColor = colors[index]
                        }
                    }) {
                        Circle()
                            .fill(colors[index])
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColor == colors[index] ? 3 : 0)
                            )
                            .scaleEffect(selectedColor == colors[index] ? 0.9 : 1.0)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16).frame(height: 55)
    }
}

