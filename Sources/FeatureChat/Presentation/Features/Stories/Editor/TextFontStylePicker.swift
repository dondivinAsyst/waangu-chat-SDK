import SwiftUI

// MARK: - FontStylePickerBar.swift
struct FontStylePickerBar: View {
//    private let fontData = FontData.shared
    private let fontData = ConstantFont.shared.AllFonts
    @Binding var selectedIndex: Int
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
//                ForEach(fontData.fontStyles.indices, id: \.self) { index in
                ForEach(fontData.indices, id: \.self) { index in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex = index
                        }
                    }) {
                        Text(fontData[index].family)
                            .font(.applyFontCustom(fontData[index]))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(selectedIndex == index ? Color.white.opacity(0.2) : Color.clear)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white, lineWidth: selectedIndex == index ? 2 : 0)
                            )
                            .scaleEffect(selectedIndex == index ? 0.95 : 1.0)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
        .frame(height: 55)
    }
}

#Preview {
    FontStylePickerBar(selectedIndex: .constant(0))
        .background(Color.black)
}
