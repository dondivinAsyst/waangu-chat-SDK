import SwiftUI

// MARK: - EmptyStateView

public struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
   public init(icon: String, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
  public  var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(Color.appDisabled)

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

            if let actionTitle, let action {
                CustomButton(
                    title: actionTitle,
                    style: .primary,
                    size: .medium,
                    isFullWidth: false,
                    action: action
                )
            }
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("EmptyState") {
    EmptyStateView(
        icon: AppIcons.empty,
        title: "No items yet",
        message: "Start by adding your first item.",
        actionTitle: "Add Item"
    ) {}
}
