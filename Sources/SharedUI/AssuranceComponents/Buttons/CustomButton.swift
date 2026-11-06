import SwiftUI

// MARK: - Button Style

public enum AppButtonStyle {
    case primary
    case secondary
    case outline
    case destructive
    case ghost
}

// MARK: - Button Size

public enum AppButtonSize {
    case large
    case medium
    case small

    var height: CGFloat {
        switch self {
        case .large: return 52
        case .medium: return 44
        case .small: return 36
        }
    }

    var font: Font {
        switch self {
        case .large: return .appButtonLarge
        case .medium: return .appButtonMedium
        case .small: return .appButtonSmall
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .large: return AppSpacing.xl
        case .medium: return AppSpacing.md
        case .small: return AppSpacing.sm
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .large: return 20
        case .medium: return 18
        case .small: return 14
        }
    }
}

// MARK: - AppButton

public struct CustomButton: View {
    let title: String
    var icon: String? = nil
    var iconPosition: IconPosition = .leading
    var style: AppButtonStyle = .primary
    var size: AppButtonSize = .large
    var isFullWidth: Bool = true
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    public enum IconPosition {
        case leading, trailing
    }

    private var isInteractionDisabled: Bool {
        isDisabled || isLoading
    }
    public init(title: String, icon: String? = nil, iconPosition: IconPosition = .leading, style: AppButtonStyle = .primary, size: AppButtonSize = .large, isFullWidth: Bool = true, isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.iconPosition = iconPosition
        self.style = style
        self.size = size
        self.isFullWidth = isFullWidth
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .scaleEffect(size == .small ? 0.7 : 0.85)
                } else {
                    if let icon, iconPosition == .leading {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize, weight: .semibold))
                    }

                    Text(title)
                        .font(size.font)

                    if let icon, iconPosition == .trailing {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize, weight: .semibold))
                    }
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, isFullWidth ? 0 : size.horizontalPadding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.lg)
                    .stroke(borderColor, lineWidth: style == .outline ? 1.5 : 0)
            )
        }
        .disabled(isInteractionDisabled)
        .opacity(isInteractionDisabled ? 0.5 : 1.0)
    }

    // MARK: - Colors

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return .brandPrimary
        case .outline: return .brandPrimary
        case .destructive: return .white
        case .ghost: return .brandPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return .brandPrimary
        case .secondary: return .brandPrimary.opacity(0.12)
        case .outline: return .clear
        case .destructive: return .appError
        case .ghost: return .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .outline: return .brandPrimary
        default: return .clear
        }
    }
}

// MARK: - Icon-Only Button

struct AppIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    var tint: Color = .appText
    var background: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
        }
    }
}

