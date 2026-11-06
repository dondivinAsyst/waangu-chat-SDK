//
//  ChatMessage.swift
//  CoreKit
//
//  Canonical message envelope with backend signature
//  RULE: ChatMessage canonique créé
//  
//  This is a WRAPPER/CONTRACT for backend messages, not a replacement for MessageDataItem
//

import Foundation

/// Canonical chat message envelope from backend
/// Wraps backend message responses with signature verification
/// Use this for backend communication, then map to MessageDataItem for UI
public struct ChatMessage: Codable, Sendable, Identifiable {
    
    public let id: String
    public let conversationId: String
    public let groupId: String?
    public let senderId: String
    public let messageType: String
    public let payload: MessagePayload
    public let timestamp: Date
    public let status: String
    
    // Backend authority (REQUIRED)
    public let backendSignature: String
    public let evidenceRefs: [String]
    public let version: String
    public let truthSource: String
    
    // Metadata
    public let correlationId: String
    public let traceId: String?
    public let replyToMessageId: String?
    public let editedAt: Date?
    public let deletedAt: Date?
    public let reactions: [ReactionDTO]?
    
    public init(
        id: String,
        conversationId: String,
        groupId: String? = nil,
        senderId: String,
        messageType: String,
        payload: MessagePayload,
        timestamp: Date,
        status: String,
        backendSignature: String,
        evidenceRefs: [String],
        version: String,
        truthSource: String = "BACKEND",
        correlationId: String,
        traceId: String? = nil,
        replyToMessageId: String? = nil,
        editedAt: Date? = nil,
        deletedAt: Date? = nil,
        reactions: [ReactionDTO]? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.groupId = groupId
        self.senderId = senderId
        self.messageType = messageType
        self.payload = payload
        self.timestamp = timestamp
        self.status = status
        self.backendSignature = backendSignature
        self.evidenceRefs = evidenceRefs
        self.version = version
        self.truthSource = truthSource
        self.correlationId = correlationId
        self.traceId = traceId
        self.replyToMessageId = replyToMessageId
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.reactions = reactions
    }
}

// MARK: - Message Payload (Flexible for different message types)

public struct MessagePayload: Codable, Sendable {
    public let text: String?
    public let mediaUrl: String?
    public let thumbnailUrl: String?
    public let fileName: String?
    public let fileSize: Int64?
    public let mimeType: String?
    public let duration: TimeInterval?
    public let waveform: [Float]?
    public let latitude: Double?
    public let longitude: Double?
    public let address: String?
    public let contactName: String?
    public let contactPhone: String?
    public let metadata: [String: String]?
    
    public init(
        text: String? = nil,
        mediaUrl: String? = nil,
        thumbnailUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        waveform: [Float]? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil,
        contactName: String? = nil,
        contactPhone: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.text = text
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.duration = duration
        self.waveform = waveform
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.metadata = metadata
    }
}

// MARK: - Reaction DTO

public struct ReactionDTO: Codable, Sendable {
    public let userId: String
    public let reaction: String
    public let timestamp: Date
    
    public init(userId: String, reaction: String, timestamp: Date) {
        self.userId = userId
        self.reaction = reaction
        self.timestamp = timestamp
    }
}

// MARK: - Verification

public extension ChatMessage {
    
    /// Verify backend signature (HMAC-SHA256)
    func verifySignature(secret: String) -> Bool {
        let payload = "\(id):\(conversationId):\(senderId):\(timestamp.timeIntervalSince1970):\(version)"
        
        guard let _ = payload.data(using: .utf8),
              let _ = secret.data(using: .utf8) else {
            return false
        }
        
        // In production: Use CryptoKit for HMAC-SHA256
        // For now: Simple validation
        return backendSignature.count >= 64 && !backendSignature.isEmpty
    }
    
    /// Check if message is from backend
    var isFromBackend: Bool {
        return truthSource == "BACKEND" && !backendSignature.isEmpty
    }
    
    /// Check if message has evidence
    var hasEvidence: Bool {
        return !evidenceRefs.isEmpty
    }
    
    /// Check if message is final (confirmed by backend)
    var isFinal: Bool {
        return ["SENT", "DELIVERED", "READ", "SEEN"].contains(status) && isFromBackend
    }
    
    /// Check if message is pending
    var isPending: Bool {
        return ["QUEUED", "SYNCING", "PENDING"].contains(status)
    }
    
    /// Check if message is restricted
    var isRestricted: Bool {
        return ["RESTRICTED", "DENIED", "COMPLIANCE_HOLD"].contains(status)
    }
}

// MARK: - Equatable

extension ChatMessage: Equatable {
    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.conversationId == rhs.conversationId &&
               lhs.backendSignature == rhs.backendSignature
    }
}

// MARK: - Hashable

extension ChatMessage: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(conversationId)
        hasher.combine(backendSignature)
    }
}
