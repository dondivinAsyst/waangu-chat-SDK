// MARK: - SharedUI/Modifiers/PermissionSettingsAlertModifier.swift

import SwiftUI

public struct PermissionSettingsAlertModifier: ViewModifier {

    @Binding public var isPresented: Bool
    public let title: String
    public let message: String

    public init(isPresented: Binding<Bool>, title: String, message: String) {
        self._isPresented = isPresented
        self.title = title
        self.message = message
    }

    public func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Settings") { openSettings() }
            } message: {
                Text(message)
            }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
