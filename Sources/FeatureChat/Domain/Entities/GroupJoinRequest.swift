//
//  GroupJoinRequest.swift
//  FeatureChat
//

import Foundation

public struct GroupJoinRequest: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let groupId: String
    public let userId: String
    public var name: String
    public var phone: String?
    public var avatar: String?
    public let requestedAt: Date

    public init(
        id: String,
        groupId: String,
        userId: String,
        name: String,
        phone: String? = nil,
        avatar: String? = nil,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.groupId = groupId
        self.userId = userId
        self.name = name
        self.phone = phone
        self.avatar = avatar
        self.requestedAt = requestedAt
    }
}

// MARK: - Realtime ingest (push / MQTT)

public extension GroupJoinRequest {
    enum NotificationKey {
        public static let groupId = "groupId"
        public static let requestId = "requestId"
        public static let userId = "userId"
        public static let name = "name"
        public static let phone = "phone"
        public static let avatar = "avatar"
        public static let requestedAt = "requestedAt"
    }

    var notificationUserInfo: [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            NotificationKey.groupId: groupId,
            NotificationKey.requestId: id,
            NotificationKey.userId: userId,
            NotificationKey.name: name,
            NotificationKey.requestedAt: requestedAt
        ]
        if let phone { info[NotificationKey.phone] = phone }
        if let avatar { info[NotificationKey.avatar] = avatar }
        return info
    }

    init?(notificationUserInfo: [AnyHashable: Any]) {
        guard
            let groupId = notificationUserInfo[NotificationKey.groupId] as? String,
            let requestId = notificationUserInfo[NotificationKey.requestId] as? String,
            let userId = notificationUserInfo[NotificationKey.userId] as? String,
            let name = notificationUserInfo[NotificationKey.name] as? String
        else {
            return nil
        }

        self.init(
            id: requestId,
            groupId: groupId,
            userId: userId,
            name: name,
            phone: notificationUserInfo[NotificationKey.phone] as? String,
            avatar: notificationUserInfo[NotificationKey.avatar] as? String,
            requestedAt: notificationUserInfo[NotificationKey.requestedAt] as? Date ?? Date()
        )
    }
}
