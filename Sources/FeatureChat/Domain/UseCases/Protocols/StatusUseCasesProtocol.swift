import Foundation
import Combine

protocol UserPostNewStatusUseCasesProtocol {
    func execute() async throws -> StatusItem
}
protocol myUserSeenStatusUseCasesProtocol {
    func execute() async throws -> SeenUser
}
// MARK: - Get Own Status
protocol GetOwnStatusUseCaseProtocol {
    func execute(userId: String) async throws -> Status?
}

// MARK: - Get Contact Statuses
protocol GetContactStatusesUseCaseProtocol {
    func execute() async throws -> [Status]
}

// MARK: - Add Own Status
protocol AddOwnStatusUseCaseProtocol {
    func execute(storie: StoryToSend) async throws
}

// MARK: - Delete Status Item
protocol DeleteOwnStatusItemUseCaseProtocol {
    func execute(statusID: String, syncStatus: SyncStatus, codeStatus: String) async throws
}
// MARK: - Delete all expired Status Item
protocol DeleteAllExpiredStatusItemUseCaseProtocol {
    func execute() async throws
}

// MARK: - Add Contact Status
protocol AddContactStatusUseCaseProtocol {
    func execute(status: Status) async throws
}

// MARK: - Mark as Seen
protocol MarkAsSeenUseCaseProtocol {
    func execute(contactUserId: String, statusId: String, liked: Bool,isStatusItem:Bool) async throws
}

// MARK: - React to Status
protocol ReactToStatusUseCaseProtocol {
    func execute(storyId: String, reaction: String) async
}

// MARK: - Clear All
protocol ClearAllStatusesUseCaseProtocol {
    func execute() async throws
}

// MARK: - Get Status by User ID
protocol GetStatusByUserIdUseCaseProtocol {
    func execute(userId: String) async throws -> [Status]
}

// MARK: - Retry Failed Status
protocol RetryFailedStatusesUseCaseProtocol {
    func execute() async throws
}
protocol RetryFailedStatusUseCaseProtocol {
    func execute(statusId:String) async throws
}
protocol RetryFailedUploadUseCaseProtocol {
    func execute(statusItemId:String) async
}



// MARK: - Get Status From Server
protocol GetStatusFromServerUseCaseProtocol {
    func execute() async throws
}

// MARK: - Get Status Item by segment code
protocol GetStatusItemByCodeUseCaseProtocol {
    func execute(codeStatus: String) async throws -> StatusItem?
}

// MARK: - UseCase Container
protocol StatusUseCasesProtocol {
    var statusUpdatedPublisher: Published<Status?>.Publisher { get }
    var getOwnStatus: GetOwnStatusUseCase { get }
    var getContactStatuses: GetContactStatusesUseCase { get }
    var addOwnStatus: AddOwnStatusUseCase { get }
    var deleteOwnStatusItem: DeleteOwnStatusItemUseCase { get }
    var deleteAllExpiredStatusItem: DeleteAllExpiredStatusItemUseCase { get }
    var addContactStatus: AddContactStatusUseCase { get }
    var markAsSeen: MarkAsSeenUseCase { get }
    var reactToStatus: ReactToStatusUseCase { get }
    var clearAllStatuses: ClearAllStatusesUseCase { get }
    var getStatusByUserId: GetStatusByUserIdUseCase { get }
    var retryFailedStatusUseCase: RetryFailedStatusUseCase { get }
    var retryFailedUploadStatusUseCase: RetryFailedUploadUseCase { get }
    var retryFailedStatusesUseCase: RetryFailedStatusesUseCase { get }
    var getStatusFromServerUseCase: GetStatusFromServerUseCase { get }
    var getStatusItemByCode: GetStatusItemByCodeUseCase { get }
}
