//
//  CallUseCasesProtocol.swift
//  FeatureChat
//

import Foundation

public protocol GetCallLogsUseCaseProtocol {
    /// Newest first.
    func execute(filter: CallLogFilter, limit: Int?) async throws -> [CallLogEntity]
}

public protocol GetCallLogsForConversationUseCaseProtocol {
    func execute(conversationId: String) async throws -> [CallLogEntity]
}

public protocol SaveCallLogUseCaseProtocol {
    /// Records a finished call. Re-saving the same id updates the entry, so a
    /// call logged while ringing is upgraded on hang-up instead of duplicated.
    func execute(_ log: CallLogEntity) async throws
}

public protocol DeleteCallLogUseCaseProtocol {
    func execute(id: String) async throws
}

public protocol ClearCallLogsUseCaseProtocol {
    func execute() async throws
}

public protocol SyncCallsUseCaseProtocol {
    /// Pulls server-side call history since the last sync.
    /// - Returns: how many call rows were written.
    @discardableResult
    func execute(limit: Int) async throws -> Int
}

public protocol CallUseCasesProtocol {
    var getCallLogs: GetCallLogsUseCaseProtocol { get }
    var getCallLogsForConversation: GetCallLogsForConversationUseCaseProtocol { get }
    var saveCallLog: SaveCallLogUseCaseProtocol { get }
    var deleteCallLog: DeleteCallLogUseCaseProtocol { get }
    var clearCallLogs: ClearCallLogsUseCaseProtocol { get }
    var syncCalls: SyncCallsUseCaseProtocol { get }
}
