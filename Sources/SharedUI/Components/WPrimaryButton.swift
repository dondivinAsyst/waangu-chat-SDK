// MARK: - SharedUI/Components/WPrimaryButton.swift

import SwiftUI

public struct WPrimaryButton: View {
    public let title: String
    public let isEnabled: Bool
    public let action: () -> Void

    public init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: {
            if isEnabled { action() }
        }) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(isEnabled ? .white : Color(.systemGray))
                .background(isEnabled ? AppColors.primary : Color(.systemGray5))
                .cornerRadius(20)
        }
        .disabled(!isEnabled)
        .padding(.top, 10)
    }
}
