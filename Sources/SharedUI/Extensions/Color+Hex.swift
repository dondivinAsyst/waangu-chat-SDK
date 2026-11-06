// MARK: - SharedUI/Extensions/Color+Hex.swift

import SwiftUI
import UIKit

public extension Color {
    // MARK: - UInt-based initializers
    init(hex: UInt, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(light lightHex: UInt, dark darkHex: UInt, alpha: Double = 1.0) {
        let uiColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex, alpha: alpha)
                : UIColor(hex: lightHex, alpha: alpha)
        }
        self.init(uiColor)
    }
}

public extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        let red   = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let blue  = CGFloat(hex & 0xFF)          / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - App Colors and Hex String utilities
public extension Color {
    // MARK: - Brand
    static let appPrimary = Color("AppPrimary", bundle: nil)
    static let appSecondary = Color("AppSecondary", bundle: nil)
    static let appAccent = Color("AppAccent", bundle: nil)

    // MARK: - Fallback brand colors (used until asset catalog colors are added)
    static let brandPrimary = Color(hex: "#08569e")
    static let brandSecondary = Color(hex: "#5856D6")
    static let brandAccent = Color(hex: "#FF9500")

    // MARK: - Semantic
    static let appBackground = Color(.systemBackground)
    static let appSecondaryBackground = Color(.secondarySystemBackground)
    static let appGroupedBackground = Color(.systemGroupedBackground)

    static let appText = Color(.label)
    static let appSecondaryText = Color(.secondaryLabel)
    static let appTertiaryText = Color(.tertiaryLabel)
    static let appPlaceholder = Color(.placeholderText)

    // MARK: - Status
    static let appSuccess = Color(hex: "#34C759")
    static let appWarning = Color(hex: "#FF9500")
    static let appError = Color(hex: "#FF3B30")
    static let appInfo = Color(hex: "#007AFF")

    // MARK: - Surface
    static let appCard = Color(.secondarySystemBackground)
    static let appDivider = Color(.separator)
    static let appBorder = Color(.systemGray4)
    static let appDisabled = Color(.systemGray3)

    // MARK: - Hex String Initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Hex String Export
    func toHex() -> String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
