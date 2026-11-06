import SwiftUI

// MARK: - ErrorStateView

public struct ErrorStateView: View {
    var icon: String = AppIcons.noConnection
    var title: String = "Something went wrong"
    var message: String? = "Please check your connection and try again."
    var retryTitle: String = "Retry"
    var onRetry: (() -> Void)? = nil
    
    public init(message: String? = nil, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(Color.appError.opacity(0.7))

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(.appTitle3)
                    .foregroundStyle(Color.appText)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.appSubheadline)
                        .foregroundStyle(Color.appSecondaryText)
                        .multilineTextAlignment(.center)
                }
            }

            if let onRetry {
                CustomButton(
                    title: retryTitle,
                    icon: AppIcons.refresh,
                    style: .outline,
                    size: .medium,
                    isFullWidth: false,
                    action: onRetry
                )
            }
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("ErrorState") {
    ErrorStateView {
        #if DEBUG
        print("Retry tapped")
        #endif
    }
}
