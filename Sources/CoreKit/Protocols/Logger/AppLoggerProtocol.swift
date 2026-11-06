//
//  AppLoggerProtocol.swift
//  CoreKit
//
//  Protocol abstraction for AppLogger

import Foundation

public protocol AppLoggerProtocol: Sendable {
    
    /// Log a message
    func log(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) async
    
    /// Add log observer
    func addObserver(_ observer: any LogObserverProtocol) async
    
    /// Remove all observers
    func removeAllObservers() async
    
    /// Minimum log level
    var minLevel: LogLevel { get async }
}

/// Default parameter overloads for convenience
public extension AppLoggerProtocol {
    func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(message, level: level, file: file, function: function, line: line)
    }
}