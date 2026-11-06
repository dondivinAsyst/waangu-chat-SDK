import SwiftUI

public struct WizardProgressBar: View {
    let progress: Double
    let stepLabel: String
    let totalSteps: Int
    let currentStep: Int
    let lastAutosaveDate: Date?
    var onJump: ((Int) -> Void)?

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(stepLabel)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.appText)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.appCaption1)
                    .foregroundStyle(Color.appSecondaryText)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.appBorder.opacity(0.3))
                        .frame(height: 8)
                        .onTapGesture { location in
                            handleTap(at: location, in: geometry.size.width)
                        }

                    // Progress fill
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(
                            width: geometry.size.width * max(0, min(1, CGFloat(progress))),
                            height: 8
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)
                    
                    // Step indicators (Dots)
                    HStack(spacing: 0) {
                        ForEach(0..<totalSteps, id: \.self) { index in
                            Circle()
                                .fill(index <= currentStep ? Color.white : Color.clear)
                                .frame(width: 4, height: 4)
                                .frame(maxWidth: .infinity)
                                .onTapGesture {
                                    onJump?(index)
                                }
                        }
                    }
                }
            }
            .frame(height: 8)

            if let date = lastAutosaveDate {
                HStack(spacing: AppSpacing.xxxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appSuccess)
                    Text("Brouillon enregistré \(date.formatted(.relative(presentation: .named)))")
                        .font(.appCaption2)
                        .foregroundStyle(Color.appTertiaryText)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.sm)
    }
    
    private func handleTap(at location: CGPoint, in totalWidth: CGFloat) {
        let percentage = location.x / totalWidth
        let targetStep = Int(round(percentage * CGFloat(totalSteps - 1)))
        onJump?(targetStep)
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
