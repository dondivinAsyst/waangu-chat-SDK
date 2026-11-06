//
//  AppLanguageProtocol.swift
//  AppModules
//
//  Created by Asyst on 4/9/26.
//

public enum AppLanguage: String, CaseIterable {
    case fr
    case en
    case es
    case de

    /// Human-readable display name shown in the language picker.
    public var displayName: String {
        switch self {
        case .fr: return "Français"
        case .en: return "English"
        case .es: return "Español"
        case .de: return "Deutsch"
        }
    }

    /// Native locale flag emoji (cosmetic, always visible regardless of chosen language).
    public var flagEmoji: String {
        switch self {
        case .fr: return "🇫🇷"
        case .en: return "🇬🇧"
        case .es: return "🇪🇸"
        case .de: return "🇩🇪"
        }
    }
}
