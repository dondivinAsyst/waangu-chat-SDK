//
//  ConstantColors.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//


import SwiftUI
public struct ConstantColors {
    public  static let customColors: [Color] = [
        // Original Colors
        Color(red: 0.4, green: 0.2, blue: 0.6),  // Deep Purple
        Color(red: 0.5, green: 0.4, blue: 0.6),  // Muted Purple
        Color(red: 0.6, green: 0.5, blue: 0.7),  // Light Purple
        Color(red: 0.4, green: 0.6, blue: 0.8),  // Sky Blue
        Color(red: 0.5, green: 0.6, blue: 0.6),  // Teal Gray
        Color(red: 0.2, green: 0.3, blue: 0.3),  // Dark Teal
        Color(red: 0.7, green: 0.6, blue: 0.5),  // Sand
        Color(red: 0.5, green: 0.5, blue: 0.5),  // Medium Gray
        
        // Vibrant Colors
        Color(red: 0.9, green: 0.2, blue: 0.2),  // Red
        Color(red: 0.9, green: 0.5, blue: 0.1),  // Orange
        Color(red: 0.9, green: 0.8, blue: 0.1),  // Yellow
        Color(red: 0.3, green: 0.7, blue: 0.3),  // Green
        Color(red: 0.1, green: 0.6, blue: 0.8),  // Blue
        Color(red: 0.5, green: 0.2, blue: 0.7),  // Purple
        Color(red: 0.8, green: 0.2, blue: 0.5),  // Pink
        
        // Pastel Colors
        Color(red: 1.0, green: 0.8, blue: 0.8),  // Light Pink
        Color(red: 0.8, green: 1.0, blue: 0.8),  // Light Green
        Color(red: 0.8, green: 0.9, blue: 1.0),  // Light Blue
        Color(red: 1.0, green: 1.0, blue: 0.8),  // Light Yellow
        Color(red: 0.9, green: 0.8, blue: 1.0),  // Light Purple
        
        // Earth Tones
        Color(red: 0.4, green: 0.3, blue: 0.2),  // Brown
        Color(red: 0.6, green: 0.5, blue: 0.4),  // Tan
        Color(red: 0.3, green: 0.4, blue: 0.2),  // Olive Green
        Color(red: 0.5, green: 0.4, blue: 0.3),  // Taupe
        
        // Cool Colors
        Color(red: 0.2, green: 0.4, blue: 0.6),  // Steel Blue
        Color(red: 0.3, green: 0.5, blue: 0.7),  // Light Steel Blue
        Color(red: 0.1, green: 0.3, blue: 0.5),  // Navy Blue
        Color(red: 0.6, green: 0.8, blue: 0.9),  // Ice Blue
        
        // Warm Colors
        Color(red: 0.8, green: 0.4, blue: 0.3),  // Terracotta
        Color(red: 0.9, green: 0.6, blue: 0.4),  // Peach
        Color(red: 0.7, green: 0.3, blue: 0.2),  // Rust
        Color(red: 0.8, green: 0.7, blue: 0.6),  // Beige
        
        // Jewel Tones
        Color(red: 0.3, green: 0.2, blue: 0.5),  // Royal Purple
        Color(red: 0.1, green: 0.4, blue: 0.6),  // Sapphire
        Color(red: 0.2, green: 0.6, blue: 0.3),  // Emerald
        Color(red: 0.7, green: 0.1, blue: 0.2),  // Ruby
        
        // Grayscale
        Color(red: 0.9, green: 0.9, blue: 0.9),  // Light Gray
        Color(red: 0.7, green: 0.7, blue: 0.7),  // Silver
        Color(red: 0.3, green: 0.3, blue: 0.3),  // Dark Gray
        Color(red: 0.1, green: 0.1, blue: 0.1),  // Almost Black
        
        // Special Colors
        Color(red: 0.0, green: 0.8, blue: 0.8),  // Cyan
        Color(red: 0.6, green: 0.4, blue: 0.8),  // Amethyst
        Color(red: 0.8, green: 0.4, blue: 0.0),  // Amber
        Color(red: 0.2, green: 0.8, blue: 0.6)   // Mint
    ]
    
    // Color categories for organization
    static func getColorCategories() -> [String: [Int]] {
        return [
            "Original": Array(0...7),
            "Vibrant": Array(8...14),
            "Pastel": Array(15...19),
            "Earth Tones": Array(20...23),
            "Cool Colors": Array(24...27),
            "Warm Colors": Array(28...31),
            "Jewel Tones": Array(32...35),
            "Grayscale": Array(36...39),
            "Special": Array(40...43)
        ]
    }
    
    // Get color name for index (optional helper)
    static func getColorName(for index: Int) -> String {
        let colorNames = [
            "Deep Purple", "Muted Purple", "Light Purple", "Sky Blue", "Teal Gray", "Dark Teal", "Sand", "Medium Gray",
            "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink",
            "Light Pink", "Light Green", "Light Blue", "Light Yellow", "Light Purple",
            "Brown", "Tan", "Olive Green", "Taupe",
            "Steel Blue", "Light Steel Blue", "Navy Blue", "Ice Blue",
            "Terracotta", "Peach", "Rust", "Beige",
            "Royal Purple", "Sapphire", "Emerald", "Ruby",
            "Light Gray", "Silver", "Dark Gray", "Almost Black",
            "Cyan", "Amethyst", "Amber", "Mint"
        ]
        
        guard index >= 0 && index < colorNames.count else {
            return "Unknown Color"
        }
        return colorNames[index]
    }
}
public struct FontDescriptor {
    public  let id: Int
    public let family: String
    public let weight: String
    public let design: String?
    public  let size: CGFloat
}
public struct ConstantFont {
    public  static let shared = ConstantFont()
    let AllFonts: [FontDescriptor] = [
        FontDescriptor(id: 0, family: "system", weight: "regular", design: "default", size: 22),
        FontDescriptor(id: 1, family: "systemBold", weight: "bold", design: "default", size: 22),
        FontDescriptor(id: 2, family: "systemLight", weight: "light", design: "default", size: 22),
        FontDescriptor(id: 3, family: "systemMidum", weight: "medium", design: "default", size: 22),
        FontDescriptor(id: 4, family: "systemSemi", weight: "semibold", design: "default", size: 22),
        FontDescriptor(id: 5, family: "serif", weight: "regular", design: "serif", size: 22),
        FontDescriptor(id: 6, family: "monospace", weight: "regular", design: "monospaced", size: 22),
//        FontDescriptor(id: 7, family: "system", weight: "regular", design: "rounded", size: 22),

        FontDescriptor(id: 8, family: "Snell Roundhand", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 9, family: "Brush Script MT", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 10, family: "Chalkboard SE", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 11, family: "Noteworthy", weight: "regular", design: nil, size: 22),

        FontDescriptor(id: 12, family: "Times New Roman", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 13, family: "Georgia", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 14, family: "Palatino", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 15, family: "Baskerville", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 16, family: "Courier New", weight: "regular", design: nil, size: 22),

        FontDescriptor(id: 17, family: "Avenir", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 18, family: "Avenir Next", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 19, family: "Helvetica Neue", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 20, family: "Futura", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 21, family: "Gill Sans", weight: "regular", design: nil, size: 22),

        FontDescriptor(id: 22, family: "Papyrus", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 23, family: "Herculanum", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 24, family: "Optima", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 25, family: "Marker Felt", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 26, family: "American Typewriter", weight: "regular", design: nil, size: 22),

        FontDescriptor(id: 27, family: "Menlo", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 28, family: "Courier", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 29, family: "SF Mono", weight: "regular", design: nil, size: 22),
        FontDescriptor(id: 30, family: "Andale Mono", weight: "regular", design: nil, size: 22)
    ]
 
}
public extension Font {
    public static func applyFontCustom(_ fontData: FontDescriptor, size: CGFloat? = nil) -> Font {
        .system(
            size: size ?? fontData.size,
            weight: fontData.weight.asFontWeight
        )
    }
}
public extension String {
    var asFontWeight: Font.Weight {
        switch self.lowercased() {
        case "100", "ultralight": return .ultraLight
        case "200", "thin":       return .thin
        case "300", "light":      return .light
        case "400", "regular":    return .regular
        case "500", "medium":     return .medium
        case "600", "semibold":   return .semibold
        case "700", "bold":       return .bold
        case "800", "heavy":      return .heavy
        case "900", "black":      return .black
        default:                  return .regular
        }
    }
}
