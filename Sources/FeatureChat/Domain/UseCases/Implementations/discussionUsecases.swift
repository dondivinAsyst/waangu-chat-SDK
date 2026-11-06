import Foundation

class GetDiscussionUseCase: GetDiscussionUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [DiscussionChatItem]? {
        try await repository.fetchDiscussions()
    }
}

class GetDiscussionMessagesUseCase: GetDiscussionMessagesUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func execute(conversationId: String) async throws -> [MessageDataItem]? {
        try await repository.fetchMessages(conversationId)
    }
}

class GetDiscussionMessagesWithPaginationUseCase: GetDiscussionMessagesWithPaginationUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func execute(conversationId: String, before cursor: Date?, pageSize: Int) async throws -> [MessageDataItem]? {
        try await repository.fetchMessagesWithPagination(
            conversationId: conversationId,
            before: cursor,
            pageSize: pageSize
        )
    }
}

class CreateDiscussionUseCase: CreateDiscussionUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func execute(discussion: DiscussionChatItem) async throws {
        try await repository.saveDiscussion(discussion)
    }
}

class UpdateDiscussionSettingUseCase: UpdateDiscussionSettingUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func execute(discussion: DiscussionChatItem) async throws {
        try await repository.updateDiscussionSetting(discussion)
    }
}

class DeleteDiscussionUseCase: DeleteDiscussionUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func execute(converationId: String) async throws {
        try await repository.deleteDiscussion(conversationId: converationId)
    }
}

class DeleteAllDiscussionMessagesUseCase: DeleteAllDiscussionMessagesUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func execute(converationId: String) async throws {
        try await repository.deleteAllDiscussionMessages(conversationId: converationId)
    }
}

class DiscussionDraftUseCase: DiscussionDraftUseCaseProtocol {

    private let repository: DiscussionRepositoryProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.repository = repository
    }

    func save(conversationId: String, text: String) async throws {
        guard !conversationId.isEmpty else { return }
        try await repository.saveDraft(conversationId: conversationId, text: text)
    }

    func fetch(conversationId: String) async throws -> String? {
        guard !conversationId.isEmpty else { return nil }
        return try await repository.fetchDraft(conversationId: conversationId)
    }
}

class DiscussionUseCases: DiscussionUseCasesProtocol {
    var getMessagesWithPagination: GetDiscussionMessagesWithPaginationUseCaseProtocol
    var getMessages: GetDiscussionMessagesUseCaseProtocol
    var createDiscussion: CreateDiscussionUseCaseProtocol
    var getDiscussions: GetDiscussionUseCaseProtocol
    var updateDiscussionSetting: UpdateDiscussionSettingUseCaseProtocol
    var deleteDiscussion: DeleteDiscussionUseCaseProtocol
    var deleteAllDiscussionMessages: DeleteAllDiscussionMessagesUseCaseProtocol
    var draft: DiscussionDraftUseCaseProtocol

    init(repository: DiscussionRepositoryProtocol) {
        self.getMessages = GetDiscussionMessagesUseCase(repository: repository)
        self.getMessagesWithPagination = GetDiscussionMessagesWithPaginationUseCase(repository: repository)
        self.getDiscussions = GetDiscussionUseCase(repository: repository)
        self.createDiscussion = CreateDiscussionUseCase(repository: repository)
        self.updateDiscussionSetting = UpdateDiscussionSettingUseCase(repository: repository)
        self.deleteDiscussion = DeleteDiscussionUseCase(repository: repository)
        self.deleteAllDiscussionMessages = DeleteAllDiscussionMessagesUseCase(repository: repository)
        self.draft = DiscussionDraftUseCase(repository: repository)
    }
}
