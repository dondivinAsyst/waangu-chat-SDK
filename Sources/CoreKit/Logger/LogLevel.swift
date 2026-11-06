//
//  LogLevel.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

//
// Niveaux de log de l'application.
// Zéro dépendance externe — pas de SentryLevel ici.
//
// Le mapping LogLevel → SentryLevel vit dans ObservabilityKit/Providers/SentryProvider.swift
// car c'est Sentry qui dépend de CoreKit, pas l'inverse.

import Foundation

public enum LogLevel: Int, Comparable, Sendable {
    case debug    = 0
    case info     = 1
    case warning  = 2
    case error    = 3
    case critical = 4

    // MARK: - Comparable
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Display

    public var description: String {
        switch self {
        case .debug:    return "DEBUG"
        case .info:     return "INFO"
        case .warning:  return "WARNING"
        case .error:    return "ERROR"
        case .critical: return "CRITICAL"
        }
    }

    public var emoji: String {
        switch self {
        case .debug:    return "🔍"
        case .info:     return "ℹ️"
        case .warning:  return "⚠️"
        case .error:    return "❌"
        case .critical: return "🔥"
        }
    }
}
