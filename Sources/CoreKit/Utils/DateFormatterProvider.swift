//
//  DateFormatterProvider.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//



import Foundation

public enum DateFormatterProvider {

    // MARK: - Cache thread-safe
    //
    // `nonisolated(unsafe)` : mutation protégée par le lock ci-dessous.
    // Évite de recréer un ISO8601DateFormatter à chaque appel
    // (allocation + configuration non négligeables).
    private nonisolated(unsafe) static var _formatter: ISO8601DateFormatter?
    private static let lock = NSLock()

    private static var formatter: ISO8601DateFormatter {
        lock.withLock {
            if let existing = _formatter { return existing }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _formatter = f
            return f
        }
    }

    // MARK: - Public API

    public static nonisolated func iso8601String(from date: Date) -> String {
        formatter.string(from: date)
    }

 
    public static nonisolated func iso8601Date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
