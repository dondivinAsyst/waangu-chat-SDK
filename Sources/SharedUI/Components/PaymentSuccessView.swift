import SwiftUI

public struct PaymentSuccessView: View {
    public let amount: Int
    public let onDone: () -> Void

    public init(amount: Int, onDone: @escaping () -> Void) {
        self.amount = amount
        self.onDone = onDone
    }

    private func formatted(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "0"
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            ZStack {
                Circle()
                    .fill(AppColors.sendMoney.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(AppColors.sendMoney)
            }

            Text("Bill Payment Successful")
                .font(.headline)

            Text("\(formatted(amount)) BIF")
                .font(.title)
                .foregroundColor(AppColors.primary)

            Text("Your transaction of \(amount)BIF was successfully done")
                .font(.subheadline)
                .foregroundColor(AppColors.iconLabel.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            Button(action: {
                onDone()
            }) {
                Text("Go To Home Screen")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AppColors.primary))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
    }
}
