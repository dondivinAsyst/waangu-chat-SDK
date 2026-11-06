
import Foundation

public protocol GetMessagesUseCaseProtocol {
    func execute(conversationId: String) async throws -> [MessageDataItem]?
}
public protocol CountMediaMessagesWithSameGroupIdUseCaseProtocol {
    func execute(groupId: String) async -> Int?
}
public protocol UpdateMessagesUseCaseProtocol {
    func execute(message: MessageDataItem) async throws
}
public protocol DeleteMessagesUseCaseProtocol {
    func execute(messageId: String) async throws
    func execute(messageId: String, forEveryone: Bool) async throws
}

public protocol FetchRecentSentDocumentsUseCaseProtocol {
    func execute(conversationId: String, limit: Int) async -> [MessageDataItem]
}

public protocol MessagesUseCasesProtocol {
    var getMessages: GetMessagesUseCaseProtocol { get }
    var countMediaMessagesWithSameGroupId: CountMediaMessagesWithSameGroupIdUseCaseProtocol { get }
    var updateMessages: UpdateMessagesUseCaseProtocol { get }
    var deleteMessages: DeleteMessagesUseCaseProtocol { get }
    var fetchRecentSentDocuments: FetchRecentSentDocumentsUseCaseProtocol { get }
}
