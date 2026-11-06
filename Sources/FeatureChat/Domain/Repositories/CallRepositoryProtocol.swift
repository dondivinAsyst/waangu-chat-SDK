//
//  CallRepositoryProtocol.swift
//  FeatureChat
//

import Foundation

protocol CallRepositoryProtocol {
    /// Newest first. `limit: nil` returns everything.
    func getCallLogs(filter: CallLogFilter, limit: Int?) async throws -> [CallLogEntity]
    func getCallLog(id: String) async throws -> CallLogEntity?
    func getCallLogs(conversationId: String) async throws -> [CallLogEntity]
    /// Insert or update — the id is the call's own id, so re-saving a call that
    /// was logged as ringing upgrades it in place rather than duplicating it.
    func saveCallLog(_ log: CallLogEntity) async throws
    func deleteCallLog(id: String) async throws
    func deleteCallLogs(conversationId: String) async throws
    func clearCallLogs() async throws
    /// Pulls server-side call history changed since the stored cursor.
    /// - Returns: how many call rows were written.
    @discardableResult
    func syncCalls(limit: Int) async throws -> Int
}
