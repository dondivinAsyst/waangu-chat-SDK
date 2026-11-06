// MARK: - SharedUI/Tokens/DesignTokens.swift

import SwiftUI

public enum DesignTokens {

    // MARK: Spacing
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32

    // MARK: Radii
    public static let cornerRadiusSmall: CGFloat = 6
    public static let cornerRadiusDefault: CGFloat = 8
    public static let circleSizeSmall: CGFloat = 32

    // MARK: Heights
    public static let inputHeight: CGFloat = 48
    public static let buttonHeight: CGFloat = 48

    // MARK: Typography
    public static let titleFont = Font.system(size: 18, weight: .semibold)
    public static let bodyFont = Font.system(size: 14)

    // MARK: Shadows
    public static let cardShadow = Color.black.opacity(0.06)
}
