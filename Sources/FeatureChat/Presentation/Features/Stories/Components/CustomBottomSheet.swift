import SwiftUI

struct CustomBottomSheet<Content: View>: View {
    @Binding var isOpen: Bool
    let maxHeight: CGFloat
    let minHeight: CGFloat
    let content: Content
    
    @GestureState private var translation: CGFloat = 0
    
    private var offset: CGFloat {
        isOpen ? 0 : maxHeight - minHeight
    }
    
    init(isOpen: Binding<Bool>, maxHeight: CGFloat, minHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self._isOpen = isOpen
        self.maxHeight = maxHeight
        self.minHeight = minHeight
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                VStack {
                    Capsule()
                        .frame(width: 40, height: 6)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.top, 8)
                    
                    content
                }
                .frame(width: geometry.size.width, height: maxHeight, alignment: .top)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .offset(y: max(offset + translation, 0))
                .animation(.interactiveSpring(), value: isOpen)
                .gesture(
                    DragGesture().updating($translation) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let snapDistance = maxHeight * 0.25
                        if value.translation.height > snapDistance {
                            isOpen = false
                        } else {
                            isOpen = true
                        }
                    }
                )
            }
            .edgesIgnoringSafeArea(.bottom)
        }
    }
}

//#Preview{
//    ContentView()
//}
