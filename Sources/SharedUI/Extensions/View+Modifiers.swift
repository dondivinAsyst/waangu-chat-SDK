// MARK: - SharedUI/Extensions/View+Modifiers.swift

import SwiftUI

public extension View {

    func loading(_ isLoading: Bool) -> some View {
        modifier(LoadingModifier(isLoading: isLoading))
    }

    func permissionSettingsAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String
    ) -> some View {
        modifier(
            PermissionSettingsAlertModifier(
                isPresented: isPresented,
                title: title,
                message: message
            )
        )
    }

    func popup(show: Binding<Bool>, popup: InfoPopup) -> some View {
        modifier(
            InfoPopupContainerModifier(show: show, popup: popup)
        )
    }

    /// Bottom-sheet style numeric PIN pad with dimmed backdrop (see ``PinEntryOverlay``).
    func pinEntryOverlay(
        show: Binding<Bool>,
        pin: Binding<String>,
        title: String = "Please Enter Your Password",
        digitCount: Int = 6,
        clearPinOnDismiss: Bool = true,
        sheetHeightFraction: CGFloat = 0.58,
        onComplete: @escaping (String) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            PinEntryOverlayModifier(
                show: show,
                pin: pin,
                title: title,
                digitCount: digitCount,
                clearPinOnDismiss: clearPinOnDismiss,
                onComplete: onComplete,
                onDismiss: onDismiss,
                sheetHeightFraction: sheetHeightFraction
            )
        )
    }

    func shimmer(phase: CGFloat) -> some View {
        modifier(ShimmerModifier(phase: phase))
    }

    func presentationDetentsDynamic(itemsCount: Int) -> some View {
        modifier(PresentationDetentsDynamicModifier(itemsCount: itemsCount))
    }
}
