//
//  LogFormatter.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//
// Formatage des messages de log.
// Utilisé par AppLogger pour construire le message final
// avant envoi à os.Logger ou toute autre destination.

import Foundation

public struct LogFormatter: Sendable {

    public init() {}

    /// Formate un message de log avec timestamp, niveau, fichier, fonction et ligne.
    ///
    /// Format : `[2024-01-15T10:30:00Z] [ℹ️ INFO] [AuthRepository.swift:42] login() - Message`
    public static func format(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) -> String {
        let timestamp = Date().ISO8601Format()
        let fileName = (file as NSString).lastPathComponent
        return "[\(timestamp)] [\(level.emoji) \(level.description)] [\(fileName):\(line)] \(function) - \(message)"
    }

    /// Format court — sans timestamp, pour os.Logger qui horodate lui-même.
    /// Évite le doublon de timestamp dans Console.app.
    public static func formatShort(
        _ message: String,
        file: String,
        function: String,
        line: Int
    ) -> String {
        let fileName = (file as NSString).lastPathComponent
        return "[\(fileName):\(line)] \(function) - \(message)"
    }
}
