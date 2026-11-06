import SwiftUI

// MARK: - Card Modifier

public struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppCornerRadius.md
    var shadow: AppShadow = .sm

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.appCard)
            )
            .appShadow(shadow)
    }
}

// MARK: - Rounded Border Modifier

public struct RoundedBorderModifier: ViewModifier {
    var color: Color = .appBorder
    var cornerRadius: CGFloat = AppCornerRadius.md
    var lineWidth: CGFloat = 1

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: lineWidth)
            )
    }
}


// MARK: - Conditional Modifier

public extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func cardStyle(cornerRadius: CGFloat = AppCornerRadius.md, shadow: AppShadow = .sm) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, shadow: shadow))
    }

    func roundedBorder(color: Color = .appBorder, cornerRadius: CGFloat = AppCornerRadius.md, lineWidth: CGFloat = 1) -> some View {
        modifier(RoundedBorderModifier(color: color, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }

    /// Dismisses the keyboard when the user taps anywhere outside a text field.
    func onTapDismissKeyboard() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
