import SwiftUI

public struct WizardNavigationBar: View {
    let canGoBack: Bool
    let isSubmitting: Bool
    let nextTitle: String
    let nextIcon: String?
    let onBack: () -> Void
    let onNext: () -> Void

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if canGoBack {
                CustomButton(
                    title: "Retour",
                    icon: AppIcons.back,
                    style: .outline,
                    size: .large,
                    action: onBack
                )
            }

            CustomButton(
                title: nextTitle,
                icon: nextIcon,
                iconPosition: .trailing,
                style: .primary,
                size: .large,
                isLoading: isSubmitting,
                action: onNext
            )
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.sm)
        .background(
            Color.appBackground
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
