//
//  StatusLocalMapper.swift
//  FeatureChat
//
//  Single source of truth for StatusModel ↔ StatusItem GRDB conversions.
//

import Foundation
import WaanguCoreKit

struct StatusLocalMapper {

    // MARK: - StatusModel → StatusItem

    static func toDomain(
        segment: StatusModel,
        seenUsers: [SeenUser]
    ) -> StatusItem {
        StatusItem(
            id: segment.id,
            userId: segment.userId,
            codeStatus: segment.id,
            userImage: segment.avatarURL,
            userName: segment.userName,
            type: mapMediaType(segment.mediaType),
            content: segment.mediaURL ?? segment.text,
            caption: segment.caption,
            thumbnail: segment.thumbnailURL,
            background: segment.backgroundColor,
            fontText: segment.fontStyle,
            fontSize: segment.fontSize,
            fontWeight: segment.fontWeight,
            lastStatusTime: segment.postedAt,
            seenUsers: seenUsers,
            unseenUsers: [],
            viewCount: segment.viewCount,
            likeCount: 0,
            shareCount: 0,
            isActive: !segment.isExpired,
            isPinned: false,
            uploaded: segment.syncStatus == .synced,
            uploadedUrl: segment.syncStatus == .synced ? segment.mediaURL : nil,
            isPublished: segment.syncStatus == .synced,
            createdAt: segment.postedAt,
            expiresAt: segment.expiresAt,
            duration: segment.durationSeconds ?? 5.0,
            viewed: segment.viewed,
            syncStatus: mapSyncStatus(segment.syncStatus),
            syncError: nil,
            retryCount: 0,
            lastSyncAttempt: segment.updatedAt,
            filename: segment.filename,
            mimeType: segment.mimeType,
            fileSize: segment.fileSize,
            localPath: segment.localPath
        )
    }

    // MARK: - StatusViewerModel ↔ SeenUser

    static func toSeenUser(
        _ viewer: StatusViewerModel,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> SeenUser {
        let reaction = viewer.reaction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasReaction = !(reaction?.isEmpty ?? true)
        return SeenUser(
            userId: viewer.userId,
            username: fieldCrypto.decrypt(viewer.userName),
            image: viewer.avatarURL,
            viewedAt: viewer.viewedAt,
            liked: hasReaction,
            reaction: hasReaction ? reaction : nil
        )
    }

    static func toViewerModel(
        from seenUser: SeenUser,
        statusId: String,
        fieldCrypto: any FieldEncryptionServiceProtocol,
        id: String = UUID().uuidString.lowercased(),
        contactId: String? = nil
    ) -> StatusViewerModel {
        StatusViewerModel(
            id: id,
            statusId: statusId,
            userId: seenUser.userId,
            contactId: contactId,
            userName: fieldCrypto.encrypt(seenUser.username),
            avatarURL: seenUser.image,
            viewedAt: seenUser.viewedAt,
            reaction: seenUser.reaction
        )
    }

    // MARK: - StatusItem → StatusModel

    static func toGRDB(_ item: StatusItem) -> StatusModel {
        let mediaType = mapToMediaType(item.type)
        return StatusModel(
            id: item.id,
            userId: item.userId,
            contactId: nil,
            userName: item.userName ?? "",
            avatarURL: item.userImage,
            segmentIndex: 0,
            totalSegments: 1,
            mediaType: mediaType,
            text: mediaType == .text ? item.content : item.caption,
            caption: item.caption,
            linkURL: nil,
            mediaURL: item.uploadedUrl ?? item.content,
            thumbnailURL: item.thumbnail,
            localPath: item.localPath,
            mimeType: item.mimeType,
            backgroundColor: item.background,
            fontStyle: item.fontText,
            fontSize: item.fontSize,
            fontWeight:item.fontWeight,
            width: nil,
            height: nil,
            durationSeconds: item.duration,
            privacy: .allContacts,
            allowedUserIds: nil,
            excludedUserIds: nil,
            viewCount: item.viewCount,
            viewed: item.viewed,
            postedAt: item.createdAt,
            expiresAt: item.expiresAt,
            deletedAt: nil,
            syncStatus: mapToSyncStatusModel(item.syncStatus),
            filename: item.filename,
            fileSize: item.fileSize,
            createdAt: item.createdAt,
            updatedAt: Date()
        )
    }

    // MARK: - Enum mapping

    static func mapMediaType(_ type: StatusMediaTypeModel) -> StoryType {
        switch type {
        case .text:  return .text
        case .image: return .image
        case .video: return .video
        }
    }

    static func mapToMediaType(_ type: StoryType) -> StatusMediaTypeModel {
        switch type {
        case .text:  return .text
        case .image: return .image
        case .video: return .video
        case .audio: return .video
        }
    }

    static func mapSyncStatus(_ status: SyncStatusModel) -> SyncStatus {
        switch status {
        case .pending:  return .pending
        case .syncing:  return .retrying
        case .synced:   return .synced
        case .failed:   return .failed
        }
    }

    static func mapToSyncStatusModel(_ status: SyncStatus) -> SyncStatusModel {
        switch status {
        case .pending:   return .pending
        case .syncing:   return .syncing
        case .synced:    return .synced
        case .failed:    return .failed
        case .retrying:  return .syncing
        }
    }
}
