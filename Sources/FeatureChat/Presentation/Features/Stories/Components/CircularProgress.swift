import SwiftUI
import WaanguSharedUI

struct CircularProgressBar: View {
    @Binding var progress: Double // 0.0 to 1.0
    
    var lineWidth: CGFloat = 20
    var backgroundColor: Color = Color(.systemGray5)
    var foregroundColor: Color = AppColors.primary
    var showPercentage: Bool = true
    var animation: Animation = .easeInOut(duration: 1.0)
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(backgroundColor, lineWidth: lineWidth)
            
            // Progress circle
            Circle()
                .trim(from: 0.0, to: min(progress, 1.0))
                .stroke(
                    foregroundColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(animation, value: progress)
            
            // Optional percentage text in the center
            if showPercentage {
                Text("\(Int(progress * 100))%")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(lineWidth) // Prevents clipping
    }
}
