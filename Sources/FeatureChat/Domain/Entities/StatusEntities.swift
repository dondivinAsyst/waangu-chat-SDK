//
//  Entities.swift
//  Pods
//
//  Created by Asyst on 11/17/25.
//

import Foundation

public enum StoryType: String, CaseIterable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"

    /// Wire value for chat-story API (`TEXT`, `IMAGE`, …).
    public var apiValue: String {
        rawValue.uppercased()
    }

    public static func fromAPI(_ value: String) -> StoryType {
        switch value.uppercased() {
        case "TEXT": return .text
        case "IMAGE": return .image
        case "VIDEO": return .video
        case "AUDIO": return .audio
        default:
            return StoryType(rawValue: value.lowercased()) ?? .text
        }
    }
}

public enum StoryPrivacy: String, CaseIterable {
    case contacts = "contacts"
    case closeFriends = "close_friends"
    case except = "except"
}

/// Locally generated status segment ids (`codeStatus` / GRDB primary key).
/// Server-provided ids are never normalized here.
public enum StatusIDGenerator {
    public static func newCode() -> String {
        UUID().uuidString.lowercased()
    }
}

public struct SeenUser:Identifiable, Equatable,Hashable {
    public  let id:String = UUID().uuidString
    let userId: String
    let username: String
    let image: String?
    let viewedAt: Date
    let liked: Bool
    let reaction: String?
}



public struct StatusItem: Identifiable, Equatable,Hashable {
    public  let id: String
    let userId: String
    let codeStatus: String
    let userImage: String?
    let userName: String?
    let type: StoryType
    var content: String?
    let caption: String?
    let thumbnail: String?
    let background: String?
    let fontText: String?
    let fontSize: Int?
    let fontWeight: String?
    let lastStatusTime: Date?
    let seenUsers: [SeenUser]
    let unseenUsers: [String]
    let viewCount: Int
    let likeCount: Int
    let shareCount: Int
    let isActive: Bool
    let isPinned: Bool
    var uploaded: Bool
    var uploadedUrl: String?
    let isPublished: Bool
    let createdAt: Date
    var expiresAt: Date?
    var duration: Double
    var viewed: Bool
    
    // État de synchronisation
    let syncStatus: SyncStatus
    let syncError: String?
    let retryCount: Int
    let lastSyncAttempt: Date?
    
    // MARK: media info
    let filename: String?
    let mimeType:String?
    let fileSize: Int
    /// Relative disk-cache path used to re-read the file for upload retry.
    /// Nil once the item is successfully uploaded (remote URL in content/uploadedUrl).
    let localPath: String?
    
    public init(id: String = StatusIDGenerator.newCode(),
         userId: String,
         codeStatus: String,
         userImage: String? = nil,
         userName: String? = nil,
         type: StoryType,
         content: String? = nil,
         caption: String? = nil,
         thumbnail: String? = nil,
         background: String? = nil,
         fontText: String? = nil,
         fontSize: Int? = 32,
         fontWeight: String? = nil,
         lastStatusTime: Date? = nil,
         seenUsers: [SeenUser] = [],
         unseenUsers: [String] = [],
         viewCount: Int = 0,
         likeCount: Int = 0,
         shareCount: Int = 0,
         isActive: Bool = true,
         isPinned: Bool = false,
         uploaded: Bool = false,
         uploadedUrl: String? = nil,
         isPublished: Bool = false,
         createdAt: Date = Date(),
         expiresAt: Date? = nil,
         duration:Double = 5.0,
         viewed: Bool = false,
         syncStatus: SyncStatus = .pending,
         syncError: String? = nil,
         retryCount: Int = 0,
         lastSyncAttempt: Date? = nil,
          filename: String? = nil,
          mimeType:String? = nil,
          fileSize:Int = 0,
          localPath: String? = nil
    ) {
        
        self.id = id
        self.userId = userId
        self.codeStatus = codeStatus
        self.userImage = userImage
        self.userName = userName
        self.type = type
        self.content = content
        self.caption = caption
        self.thumbnail = thumbnail
        self.background = background
        self.fontText = fontText
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lastStatusTime = lastStatusTime
        self.seenUsers = seenUsers
        self.unseenUsers = unseenUsers
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.shareCount = shareCount
        self.isActive = isActive
        self.isPinned = isPinned
        self.uploaded = uploaded
        self.uploadedUrl = uploadedUrl
        self.isPublished = isPublished
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.duration = duration
        self.viewed = viewed
        self.syncStatus = syncStatus
        self.syncError = syncError
        self.retryCount = retryCount
        self.lastSyncAttempt = lastSyncAttempt
        self.filename = filename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.localPath = localPath
    }
}


public enum SyncStatus: String, Codable {
    case pending     // En attente de synchronisation
    case syncing     // Synchronisation en cours
    case synced      // Synchronisé avec succès
    case failed      // Échec de synchronisation (non récupérable)
    case retrying    // En cours de retentative
}



public struct Status: Identifiable,Hashable {
    let userId: String
    let userName: String?
    let userImage: String?
    let lastStatusTime: Date?
    var viewed: Bool
    var currentIndex: Int
    var status: [StatusItem]
    
    public var id: String { userId }
    
    public init(userId: String, userName: String? = nil, userImage: String? = nil,
         lastStatusTime: Date? = nil, viewed: Bool = false,currentIndex:Int = 0, status: [StatusItem] = []) {
        self.userId = userId
        self.userName = userName
        self.userImage = userImage
        self.lastStatusTime = lastStatusTime
        self.viewed = viewed
        self.currentIndex = currentIndex
        self.status = status
    }

    /// WhatsApp-style open position: first unviewed segment, or `0` when all are seen.
    public static func resumeIndex(for items: [StatusItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        return items.firstIndex(where: { !$0.viewed }) ?? 0
    }

    public mutating func applyResumeIndex() {
        currentIndex = Self.resumeIndex(for: status)
    }
}

// DTOs pour la création
public struct StoryToSend {
    var id:String
    let userId: String
    let type: StoryType
    var content: String?
    let caption: String?
    let background: String?
    let fontText: String?
    let fontWeight: String?
    let fontSize: Int
    let expiresInHours: Int
    let PHMedia:GalleryMedia?
    let thumbnail:String?
    let userName:String?
    let userImage:String?
    let fileSize:Int
    
  public  init(id:String,userId: String, type: StoryType, content: String? = nil, caption: String? = nil,
         background: String? = nil, fontText: String? = nil, fontWeight: String? = nil,fontSize:Int = 32,
         expiresInHours: Int = 24,
         PHMedia:GalleryMedia? = nil,
         thumbnail:String? = nil, userName:String? = nil, userImage:String? = nil,fileSize:Int = 0) {
        self.id = id
        self.userId = userId
        self.type = type
        self.content = content
        self.caption = caption
        self.background = background
        self.fontText = fontText
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.expiresInHours = expiresInHours
        self.PHMedia = PHMedia
        self.thumbnail = thumbnail
        self.userName = userName
        self.userImage = userImage
        self.fileSize = fileSize
    }
}


public struct ViewStory {
    let myId: String
    let username: String
    let image: String
    let userId: String
    let storyId: String
    let liked: Bool
    let time: Date?
}
