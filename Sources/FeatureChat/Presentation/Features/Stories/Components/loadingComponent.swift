import SwiftUI

struct AnimatedSpinner: View {
    @State private var isAnimating = false
    @State private var rotation = 0.0
     var StrokeColor : Color = .black
     var lineWidth : CGFloat = 2
    var size : CGFloat = 60
    
    
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: isAnimating ? 0.45 : 0.005)
                .stroke(
                    StrokeColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                    ) {
                        isAnimating = true
                    }
                    
                    withAnimation(
                        .linear(duration: 1)
                        .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360
                    }
                }
        }
        .frame(width: 72, height: 72)
     
    }
}



