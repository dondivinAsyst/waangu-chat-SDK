//
//  CallUseCases.swift
//  FeatureChat
//

import Foundation

// MARK: - Read

final class GetCallLogsUseCase: GetCallLogsUseCaseProtocol {
    private let repository: CallRepositoryProtocol

    init(repository: CallRepositoryProtocol) {
        self.repository = repository
    }

    func execute(filter: CallLogFilter, limit: Int?) async throws -> [CallLogEntity] {
        try await repository.getCallLogs(filter: filter, limit: limit)
    }
}

final class GetCallLogsForConversationUseCase: GetCallLogsForConversationUseCaseProtocol {
    private let repository: CallRepositoryProtocol

    init(repository: CallRepositoryProtocol) {
        self.repository = repository
    }

    func execute(conversationId: String) async throws -> [CallLogEntity] {
        try await repository.getCallLogs(conversationId: conversationId)
    }
}

// MARK: - Write

final class SaveCallLogUseCase: SaveCallLogUseCaseProtocol {
    private let repository: CallRepositoryProtocol

    init(repository: CallRepositoryProtocol) {
        self.repository = repository
    }

    func execute(_ log: CallLogEntity) async throws {
        try await repository.saveCallLog(log)
    }
}

final class DeleteCallLogUseCase: DeleteCallLogUseCaseProtocol {
    private let repository: CallRepositoryProtocol

    init(repository: CallRepositoryProtocol) {
        self.repository = repository
    }

    func execute(id: String) async throws {
        try await repository.deleteCallLog(id: id)
    }
}

final class ClearCallLogsUseCase: ClearCallLogsUseCaseProtocol {
    private let repository: CallRepositoryProtocol

    init(repository: CallRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws {
        try await repository.clearCallLogs()
    }
}

final class SyncCallsUseCase: SyncCallsUseCaseProtocol {
    private let repository: CallRepositoryProtocol

    init(repository: CallRepositoryProtocol) {
        self.repository = repository
    }

    @discardableResult
    func execute(limit: Int) async throws -> Int {
        try await repository.syncCalls(limit: limit)
    }
}

// MARK: - Container

final class CallUseCases: CallUseCasesProtocol {
    let getCallLogs: GetCallLogsUseCaseProtocol
    let getCallLogsForConversation: GetCallLogsForConversationUseCaseProtocol
    let saveCallLog: SaveCallLogUseCaseProtocol
    let deleteCallLog: DeleteCallLogUseCaseProtocol
    let clearCallLogs: ClearCallLogsUseCaseProtocol
    let syncCalls: SyncCallsUseCaseProtocol

    init(repository: CallRepositoryProtocol) {
        self.getCallLogs = GetCallLogsUseCase(repository: repository)
        self.getCallLogsForConversation = GetCallLogsForConversationUseCase(repository: repository)
        self.saveCallLog = SaveCallLogUseCase(repository: repository)
        self.deleteCallLog = DeleteCallLogUseCase(repository: repository)
        self.clearCallLogs = ClearCallLogsUseCase(repository: repository)
        self.syncCalls = SyncCallsUseCase(repository: repository)
    }
}
