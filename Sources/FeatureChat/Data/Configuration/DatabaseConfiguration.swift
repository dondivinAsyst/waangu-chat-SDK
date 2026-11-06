//
//  DatabaseConfiguration.swift
//  FeatureChat
//
//  Chat persistence is GRDB-only (SQLite via StorageKit).
//

import Foundation

/// Reserved for future chat-specific database tuning (WAL mode, batch sizes, etc.).
public struct ChatConfiguration: Sendable {
    public init() {}

    public static let `default` = ChatConfiguration()
}
