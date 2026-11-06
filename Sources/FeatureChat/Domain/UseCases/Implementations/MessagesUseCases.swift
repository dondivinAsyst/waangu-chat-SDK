import Foundation

class GetMessagesUseCase: GetMessagesUseCaseProtocol {

    private let repository: MessagesRepositoryProtocol

    init(repository: MessagesRepositoryProtocol) {
        self.repository = repository
    }

    func execute(conversationId: String) async throws -> [MessageDataItem]? {
        try await repository.fetchMessages(conversationId)
    }
}

class countMediaMessagesWithGroupIdUseCase: CountMediaMessagesWithSameGroupIdUseCaseProtocol {

    private let repository: MessagesRepositoryProtocol

    init(repository: MessagesRepositoryProtocol) {
        self.repository = repository
    }

    func execute(groupId: String) async -> Int? {
        await repository.countMediaMessagesWithGroupId(groupId: groupId)
    }
}

class UpdateMessageUseCase: UpdateMessagesUseCaseProtocol {

    private let repository: MessagesRepositoryProtocol

    init(repository: MessagesRepositoryProtocol) {
        self.repository = repository
    }

    func execute(message: MessageDataItem) async throws {
        try await repository.updateMessage(message: message)
    }
}

class DeleteMessageUseCase: DeleteMessagesUseCaseProtocol {

    private let repository: MessagesRepositoryProtocol

    init(repository: MessagesRepositoryProtocol) {
        self.repository = repository
    }

    func execute(messageId: String) async throws {
        try await execute(messageId: messageId, forEveryone: false)
    }

    func execute(messageId: String, forEveryone: Bool) async throws {
        try await repository.deleteMessage(messageId: messageId, forEveryone: forEveryone)
    }
}

class FetchRecentSentDocumentsUseCase: FetchRecentSentDocumentsUseCaseProtocol {

    private let repository: MessagesRepositoryProtocol

    init(repository: MessagesRepositoryProtocol) {
        self.repository = repository
    }

    func execute(conversationId: String, limit: Int = 20) async -> [MessageDataItem] {
        let senderId = CurrentSessionInfo.shared.currentUid
        guard !senderId.isEmpty else { return [] }
        return (try? await repository.fetchRecentSentDocuments(
            conversationId: conversationId,
            senderId: senderId,
            limit: limit
        )) ?? []
    }
}

class MessagesUseCases: MessagesUseCasesProtocol {
    var countMediaMessagesWithSameGroupId: CountMediaMessagesWithSameGroupIdUseCaseProtocol
    var getMessages: GetMessagesUseCaseProtocol
    var updateMessages: any UpdateMessagesUseCaseProtocol
    var deleteMessages: any DeleteMessagesUseCaseProtocol
    var fetchRecentSentDocuments: any FetchRecentSentDocumentsUseCaseProtocol

    init(repository: MessagesRepositoryProtocol) {
        self.getMessages = GetMessagesUseCase(repository: repository)
        self.updateMessages = UpdateMessageUseCase(repository: repository)
        self.deleteMessages = DeleteMessageUseCase(repository: repository)
        self.countMediaMessagesWithSameGroupId = countMediaMessagesWithGroupIdUseCase(repository: repository)
        self.fetchRecentSentDocuments = FetchRecentSentDocumentsUseCase(repository: repository)
    }
}
