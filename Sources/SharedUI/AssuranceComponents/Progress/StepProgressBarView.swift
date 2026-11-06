//import SwiftUI
//
//struct StepProgressBarView: View {
//    let currentStep: Int
//    let totalSteps: Int
//    let stepLabels: [String]
//
//    var body: some View {
//        VStack(spacing: 8) {
//            HStack(spacing: 0) {
//                ForEach(1...totalSteps, id: \.self) { step in
//                    stepCircle(step: step)
//                    if step < totalSteps {
//                        Rectangle()
//                            .fill(step < currentStep ? Color.brandPrimary : Color.gray.opacity(0.3))
//                            .frame(height: 2)
//                            .frame(maxWidth: .infinity)
//                    }
//                }
//            }
//            .padding(.horizontal, 8)
//            HStack(alignment: .top, spacing: 0) {
//                ForEach(Array(stepLabels.enumerated()), id: \.offset) { index, label in
//                    Text(label)
//                        .font(.system(size: 10, weight: index + 1 == currentStep ? .semibold : .regular))
//                        .foregroundColor(index + 1 == currentStep ? .brandPrimary : Color.appSecondaryText)
//                        .multilineTextAlignment(.center)
//                        .frame(maxWidth: .infinity)
//                }
//            }
//            .padding(.horizontal, 4)
//        }
//        .padding(.top, 16)
//        .padding(.bottom, 8)
//    }
//
//    private func stepCircle(step: Int) -> some View {
//        let isCompleted = step < currentStep
//        let isCurrent = step == currentStep
//        return ZStack {
//            Circle()
//                .fill(isCompleted || isCurrent ? Color.brandPrimary : Color.gray.opacity(0.3))
//                .frame(width: 28, height: 28)
//            if isCompleted {
//                Image(systemName: "checkmark")
//                    .font(.system(size: 12, weight: .bold))
//                    .foregroundColor(.white)
//            } else {
//                Text("\(step)")
//                    .font(.system(size: 13, weight: .semibold))
//                    .foregroundColor(.white)
//            }
//        }
//        .frame(width: 36, height: 36)
//    }
//}
