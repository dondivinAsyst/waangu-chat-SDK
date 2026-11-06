import Foundation
import SwiftUI
import Combine
import WaanguCoreKit
import WaanguNetworkKit


class GetOwnStatusUseCase:GetOwnStatusUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    
    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(userId: String) async throws -> Status? {
        return try await repository.fetchOwnStatus(userId: userId)
    }
}

// MARK: - Get Contact Statuses

class GetContactStatusesUseCase:GetContactStatusesUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    
    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws -> [Status] {
        return try await repository.fetchContactStatuses()
    }
}

// MARK: - Add Own Status

class AddOwnStatusUseCase: AddOwnStatusUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    private let publisher: StatusStoryPublisher

    init(repository: StatusRepositoryProtocol, publisher: StatusStoryPublisher) {
        self.repository = repository
        self.publisher = publisher
    }

    func execute(storie: StoryToSend) async throws {
        let story = storie
        let localDiskPath = publisher.saveToDisk(story: story)

        // id == story.id so the GRDB primary key UUID == codeStatus.
        let pendingItem = StatusItem(
            id:          story.id,
            userId:      story.userId,
            codeStatus:  story.id,
            type:        story.type,
            content:     story.content,
            caption:     story.caption,
            thumbnail:   story.thumbnail,
            background:  story.background,
            fontText:    story.fontText,
            fontWeight:  story.fontWeight,
            uploaded:    false,
            expiresAt:   Calendar.current.date(byAdding: .hour, value: story.expiresInHours, to: Date()),
            syncStatus:  .pending,
            filename:    story.type == .video ? "VID-\(story.id).mp4" : story.PHMedia?.fileName,
            mimeType:    story.type == .video ? "video/mp4" : story.PHMedia?.mimeType,
            fileSize:    story.fileSize,
            localPath:   localDiskPath
        )

        let existingStatus = try await repository.fetchOwnStatus(userId: story.userId)
        let updatedStatus: Status
        if let existing = existingStatus {
            var items = existing.status
            items.insert(pendingItem, at: 0)
            updatedStatus = Status(
                userId:         existing.userId,
                userName:       existing.userName,
                userImage:      existing.userImage,
                lastStatusTime: Date(),
                status:         items
            )
        } else {
            updatedStatus = Status(
                userId:         story.userId,
                lastStatusTime: Date(),
                status:         [pendingItem]
            )
        }

        try await repository.saveStatus(updatedStatus)

        // Show in UI immediately; upload + API post continue in the background.
        // Claimed for its whole run, so a resume triggered meanwhile skips it.
        Task { [publisher] in
            await publisher.exclusively(for: pendingItem.codeStatus) {
                await publisher.uploadAndPublish(story: story, item: pendingItem)
            }
        }
    }
}

class RetryFailedUploadUseCase: RetryFailedUploadUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    private let publisher: StatusStoryPublisher

    init(repository: StatusRepositoryProtocol, publisher: StatusStoryPublisher) {
        self.repository = repository
        self.publisher = publisher
    }

    func execute(statusItemId: String) async {
        await publisher.exclusively(for: statusItemId) {
            guard let statusItem = try? await repository.getPendingSyncStatus(statusId: statusItemId) else {
                return
            }

            try? await repository.updateSyncStatus(for: statusItemId, to: .retrying, errorMessage: nil)
            await publisher.uploadAndPublish(story: publisher.story(from: statusItem), item: statusItem)
        }
    }
}

// MARK: - Delete Status Item

class DeleteOwnStatusItemUseCase:DeleteOwnStatusItemUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    private let outbox: (any ChatOutboxEnqueuing)?
    private let realtime: (any RealtimeClientProtocol)?

    init(
        repository: StatusRepositoryProtocol,
        outbox: (any ChatOutboxEnqueuing)? = nil,
        realtime: (any RealtimeClientProtocol)? = nil
    ) {
        self.repository = repository
        self.outbox = outbox
        self.realtime = realtime
    }

    /// statusID = StatusItem.id (UUID string, DB primary key)
    /// syncStatus = current sync state of the item
    /// codeStatus = the story's own ID used as the server-side identifier
    func execute(statusID: String, syncStatus: SyncStatus, codeStatus: String) async throws {
        try await repository.deleteStatusItemSmart(statusID, syncStatus: syncStatus, codeStatus: codeStatus)

        // Only broadcast delete for stories that existed on the server.
        guard syncStatus == .synced, let outbox, let realtime else { return }
        let deletedBy = CurrentSessionInfo.shared.currentUid
        guard !codeStatus.isEmpty, !deletedBy.isEmpty else { return }

        await DeleteStoryPublisher.publish(
            storyId: codeStatus,
            deletedBy: deletedBy,
            outbox: outbox,
            realtime: realtime
        )
    }
}

// MARK: - Delete all expired Status Item

class DeleteAllExpiredStatusItemUseCase: DeleteAllExpiredStatusItemUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    
    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws {
        return try await repository.deleteExpiredStatuses()
    }
}
// MARK: - Add Contact Status

class AddContactStatusUseCase :AddContactStatusUseCaseProtocol{
    private let repository: StatusRepositoryProtocol
    
    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(status: Status) async throws {
        try await repository.saveStatus(status)
    }
}

// MARK: - Mark as Seen

class MarkAsSeenUseCase:MarkAsSeenUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    private let outbox: (any ChatOutboxEnqueuing)?
    private let realtime: (any RealtimeClientProtocol)?

    init(
        repository: StatusRepositoryProtocol,
        outbox: (any ChatOutboxEnqueuing)? = nil,
        realtime: (any RealtimeClientProtocol)? = nil
    ) {
        self.repository = repository
        self.outbox = outbox
        self.realtime = realtime
    }
    
    func execute(contactUserId: String, statusId: String, liked: Bool = false, isStatusItem: Bool) async throws {
        let viewStory = ViewStory(
            myId: CurrentSessionInfo.shared.currentUid,
            username: CurrentSessionInfo.shared.userName,
            image: "",
            userId: contactUserId,
            storyId: statusId,
            liked: liked,
            time: Date()
        )
        if isStatusItem {
            try await repository.markStatusItemAsSeen(viewStory: viewStory)
        } else {
            try await repository.markStatusAsSeen(viewStory: viewStory)
        }

        guard let outbox, let realtime else { return }
        let viewerId = CurrentSessionInfo.shared.currentUid
        guard !statusId.isEmpty, !viewerId.isEmpty else { return }

        await ViewStoryPublisher.publish(
            storyId: statusId,
            viewerId: viewerId,
            outbox: outbox,
            realtime: realtime
        )
    }
}

// MARK: - React to Status

class ReactToStatusUseCase: ReactToStatusUseCaseProtocol {
    private let outbox: (any ChatOutboxEnqueuing)?
    private let realtime: (any RealtimeClientProtocol)?

    init(
        outbox: (any ChatOutboxEnqueuing)? = nil,
        realtime: (any RealtimeClientProtocol)? = nil
    ) {
        self.outbox = outbox
        self.realtime = realtime
    }

    func execute(storyId: String, reaction: String) async {
        guard let outbox, let realtime else { return }
        let userId = CurrentSessionInfo.shared.currentUid
        guard !storyId.isEmpty, !userId.isEmpty, !reaction.isEmpty else { return }

        await ReactStoryPublisher.publish(
            storyId: storyId,
            userId: userId,
            reaction: reaction,
            outbox: outbox,
            realtime: realtime
        )
    }
}

// MARK: - Clear All

class ClearAllStatusesUseCase : ClearAllStatusesUseCaseProtocol{
    private let repository: StatusRepositoryProtocol
    
    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws {
        try await repository.clearAllStatuses()
    }
}

// MARK: - Get Status by User ID

class GetStatusByUserIdUseCase:GetStatusByUserIdUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    
    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(userId: String) async throws -> [Status] {
        let status = try await repository.fetchOwnStatus(userId: userId)
        return status.map { [$0] } ?? []
    }
}

class RetryFailedStatusesUseCase: RetryFailedStatusesUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    private let publisher: StatusStoryPublisher

    init(repository: StatusRepositoryProtocol, publisher: StatusStoryPublisher) {
        self.repository = repository
        self.publisher = publisher
    }

    func execute() async throws {
        let pending = try await repository.getPendingSyncStatuses(inBackground: false)
        for item in pending {
            await publisher.exclusively(for: item.codeStatus) {
                if item.type != StoryType.text && !item.uploaded {
                    await publisher.uploadAndPublish(story: publisher.story(from: item), item: item)
                } else {
                    await publisher.publishExisting(item: item)
                }
            }
        }
    }
}

class RetryFailedStatusUseCase: RetryFailedStatusUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    private let publisher: StatusStoryPublisher

    init(repository: StatusRepositoryProtocol, publisher: StatusStoryPublisher) {
        self.repository = repository
        self.publisher = publisher
    }

    func execute(statusId: String) async throws {
        try await publisher.exclusively(for: statusId) {
            guard let statusItem = try await repository.getPendingSyncStatus(statusId: statusId) else {
                return
            }

            try await repository.updateSyncStatus(for: statusId, to: .retrying, errorMessage: nil)

            if statusItem.type != StoryType.text && !statusItem.uploaded {
                await publisher.uploadAndPublish(story: publisher.story(from: statusItem), item: statusItem)
            } else {
                await publisher.publishExisting(item: statusItem)
            }
        }
    }
}
class GetStatusFromServerUseCase: GetStatusFromServerUseCaseProtocol {
    private let repository: StatusRepositoryProtocol
    
    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute() async throws {
      try await repository.getStatusFromServer()
    }
}

class GetStatusItemByCodeUseCase: GetStatusItemByCodeUseCaseProtocol {
    private let repository: StatusRepositoryProtocol

    init(repository: StatusRepositoryProtocol) {
        self.repository = repository
    }

    func execute(codeStatus: String) async throws -> StatusItem? {
        try await repository.getPendingSyncStatus(statusId: codeStatus)
    }
}



// MARK: - UseCase Container

public class StatusUseCases: StatusUseCasesProtocol {
    private let repository: StatusRepositoryProtocol
    // 🟢 Forward the repository publisher
     var statusUpdatedPublisher: Published<Status?>.Publisher {
         repository.statusUpdatedPublisher
     }
    let getOwnStatus: GetOwnStatusUseCase
    let getContactStatuses: GetContactStatusesUseCase
    let addOwnStatus: AddOwnStatusUseCase
    let deleteOwnStatusItem: DeleteOwnStatusItemUseCase
    let deleteAllExpiredStatusItem: DeleteAllExpiredStatusItemUseCase
    let addContactStatus: AddContactStatusUseCase
    let markAsSeen: MarkAsSeenUseCase
    let reactToStatus: ReactToStatusUseCase
    let clearAllStatuses: ClearAllStatusesUseCase
    let getStatusByUserId: GetStatusByUserIdUseCase
    let retryFailedStatusUseCase: RetryFailedStatusUseCase
    let retryFailedUploadStatusUseCase: RetryFailedUploadUseCase
    let retryFailedStatusesUseCase: RetryFailedStatusesUseCase
    let getStatusFromServerUseCase: GetStatusFromServerUseCase
    let getStatusItemByCode: GetStatusItemByCodeUseCase
   
    
    public init(
        repository: StatusRepositoryProtocol,
        uploadFileUseCase: UploadFileUseCaseProtocol,
        outbox: (any ChatOutboxEnqueuing)? = nil,
        realtime: (any RealtimeClientProtocol)? = nil
    ) {
        self.repository = repository
        let publisher = StatusStoryPublisher(
            repository: repository,
            uploadFileUseCase: uploadFileUseCase
        )
        self.getOwnStatus = GetOwnStatusUseCase(repository: repository)
        self.getContactStatuses = GetContactStatusesUseCase(repository: repository)
        self.addOwnStatus = AddOwnStatusUseCase(repository: repository, publisher: publisher)
        self.deleteOwnStatusItem = DeleteOwnStatusItemUseCase(
            repository: repository,
            outbox: outbox,
            realtime: realtime
        )
        self.deleteAllExpiredStatusItem = DeleteAllExpiredStatusItemUseCase(repository: repository)
        self.addContactStatus = AddContactStatusUseCase(repository: repository)
        self.markAsSeen = MarkAsSeenUseCase(
            repository: repository,
            outbox: outbox,
            realtime: realtime
        )
        self.reactToStatus = ReactToStatusUseCase(
            outbox: outbox,
            realtime: realtime
        )
        self.clearAllStatuses = ClearAllStatusesUseCase(repository: repository)
        self.getStatusByUserId = GetStatusByUserIdUseCase(repository: repository)
        self.retryFailedStatusUseCase = RetryFailedStatusUseCase(repository: repository, publisher: publisher)
        self.retryFailedUploadStatusUseCase = RetryFailedUploadUseCase(repository: repository, publisher: publisher)
        self.retryFailedStatusesUseCase = RetryFailedStatusesUseCase(repository: repository, publisher: publisher)
        self.getStatusFromServerUseCase = GetStatusFromServerUseCase(repository: repository)
        self.getStatusItemByCode = GetStatusItemByCodeUseCase(repository: repository)
    }
    
    // MARK: - Stories Sync
    
    public func syncStories(limit: Int) async throws -> Int {
        return try await repository.syncStories(limit: limit)
    }
}
