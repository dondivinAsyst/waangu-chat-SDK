//
//  ChatMessageEnvelopeMapper.swift
//  FeatureChat
//
//  Maps between ChatMessage (backend envelope) and MessageDataItem (UI model)
//

import Foundation
import WaanguCoreKit

/// Mapper between backend ChatMessage envelope and UI MessageDataItem
public struct ChatMessageEnvelopeMapper {
    
    // MARK: - Backend Envelope → UI Model
    
    /// Convert ChatMessage (backend envelope) to MessageDataItem (UI model)
    public static func toMessageDataItem(_ envelope: ChatMessage, currentUserId: String) -> MessageDataItem {
        
        // Map message type
        let messageType = mapMessageType(envelope.messageType)
        
        // Map message content
        let messageContent = mapMessageContent(envelope.payload, messageType: messageType)
        
        // Map status
        let status = mapStatus(envelope.status)
        
        // Map reactions
        let reactions = envelope.reactions?.map { reaction in
            ReactionItem(userId: reaction.userId, reaction: reaction.reaction)
        }
        
        let reply: MessageReply? = {
            guard let replyId = envelope.replyToMessageId, !replyId.isEmpty else { return nil }
            return .message(
                MessageDataItem(
                    codeMessage: replyId,
                    senderId: "",
                    typeMessage: .TEXT,
                    message: MessageContent(),
                    createdAt: envelope.timestamp
                )
            )
        }()

        return MessageDataItem(
            codeMessage: envelope.id,
            senderId: envelope.senderId,
            senderAvatar: nil, // Set from user profile
            senderPhone: "", // Set from user profile
            senderName: "", // Set from user profile
            receiverId: "", // Set from conversation context
            groupId: envelope.conversationId,
            typeMessage: messageType,
            message: messageContent,
            reply: reply,
            isDeleted: envelope.deletedAt != nil,
            forwarded: false, // TODO: Add to envelope if needed
            reactions: reactions,
            status: status,
            isMoney: messageType == .ISMONEY,
            favority: [],
            transactionId: envelope.payload.metadata?["transactionId"],
            createdAt: envelope.timestamp
        )
    }
    
    // MARK: - UI Model → Backend Envelope
    
    /// Convert MessageDataItem (UI model) to ChatMessage (backend envelope)
    /// Used when sending messages to backend
    public static func toChatMessage(
        _ item: MessageDataItem,
        conversationId: String,
        backendSignature: String,
        evidenceRefs: [String],
        version: String,
        correlationId: String
    ) -> ChatMessage {
        
        // Map message type
        let messageType = mapMessageTypeToString(item.typeMessage)
        
        // Map payload
        let payload = mapToPayload(item.message, messageType: item.typeMessage)
        
        // Map status
        let status = mapStatusToString(item.status)
        
        // Map reactions
        let reactions = item.reactions?.map { reaction in
            ReactionDTO(
                userId: reaction.userId,
                reaction: reaction.reaction,
                timestamp: Date()
            )
        }
        
        return ChatMessage(
            id: item.codeMessage,
            conversationId: conversationId,
            groupId: item.groupId,
            senderId: item.senderId,
            messageType: messageType,
            payload: payload,
            timestamp: item.createdAt,
            status: status,
            backendSignature: backendSignature,
            evidenceRefs: evidenceRefs,
            version: version,
            truthSource: "BACKEND",
            correlationId: correlationId,
            traceId: nil,
            replyToMessageId: nil,
            editedAt: nil,
            deletedAt: item.isDeleted ? Date() : nil,
            reactions: reactions
        )
    }
    
    // MARK: - Private Helpers
    
    private static func mapMessageType(_ type: String) -> MessageTypeProps {
        switch type.uppercased() {
        case "TEXT": return .TEXT
        case "IMAGE": return .IMAGE
        case "DOCUMENT": return .DOCUMENT
        case "AUDIO": return .AUDIO
        case "VOICE": return .VOICE
        case "VIDEO": return .VIDEO
        case "VIDEO_NOTE": return .VIDEO_NOTE
        case "CONTACT": return .CONTACT
        case "LOCATION": return .LOCATION
        case "MISSING_CALL_AUDIO": return .MISSING_CALL_AUDIO
        case "MISSING_CALL_VIDEO": return .MISSING_CALL_VIDEO
        case "CALL_AUDIO": return .CALL_AUDIO
        case "CALL_VIDEO": return .CALL_VIDEO
        case "ISMONEY": return .ISMONEY
        case "STATUS": return .STATUS
        default: return .TEXT
        }
    }
    
    private static func mapMessageTypeToString(_ type: MessageTypeProps) -> String {
        return type.rawValue
    }
    
    private static func mapStatus(_ status: String) -> MessageStatus {
        switch status.uppercased() {
        case "PENDING", "QUEUED", "SYNCING": return .PENDING
        case "DELIVERED", "SENT": return .DELIVERED
        case "UNSEEN": return .UNSEEN
        case "SEEN", "READ": return .SEEN
        case "MODIFY": return .MODIFY
        default: return .PENDING
        }
    }
    
    private static func mapStatusToString(_ status: MessageStatus) -> String {
        return status.rawValue
    }
    
    private static func mapMessageContent(_ payload: MessagePayload, messageType: MessageTypeProps) -> MessageContent {
        var content = MessageContent()
        
        // Text
        content.text = payload.text ?? ""
        
        // Media
        content.image = messageType == .IMAGE ? payload.mediaUrl : nil
        content.video = messageType.isVideo ? payload.mediaUrl : nil
        content.audio = messageType == .AUDIO || messageType == .VOICE ? payload.mediaUrl : nil
        content.file = messageType == .DOCUMENT ? payload.mediaUrl : nil
        content.thumbnail = payload.thumbnailUrl
        content.remoteUri = payload.mediaUrl
        
        // File info
        content.fileName = payload.fileName
        content.size = payload.fileSize != nil ? Int(payload.fileSize!) : nil
        content.mimeType = payload.mimeType
        
        // Duration
        content.videoDuration = messageType.isVideo ? payload.duration : nil
        content.audioDuration = (messageType == .AUDIO || messageType == .VOICE) ? payload.duration : nil
        content.waveform = payload.waveform
        
        // Location
        if messageType == .LOCATION, let lat = payload.latitude, let lng = payload.longitude {
            content.location = ChatLocationItem(
                coords: CoordsLocation(lat: lat, lng: lng),
                title: nil,
                address: payload.address,
                duration: nil,
                distance: nil
            )
        }
        
        // Contact
        if messageType == .CONTACT, let name = payload.contactName, let phone = payload.contactPhone {
            content.contact = [ContactItem(
                id: UUID().uuidString,
                idContact: nil,
                userId: "",
                phone: phone,
                name: name,
                avatar: nil
            )]
        }
        
        return content
    }
    
    private static func mapToPayload(_ content: MessageContent, messageType: MessageTypeProps) -> MessagePayload {
        var metadata: [String: String] = [:]
        
        // Add transaction ID if present
        if let transactionId = content.url {
            metadata["transactionId"] = transactionId
        }
        
        return MessagePayload(
            text: content.text.isEmpty ? nil : content.text,
            mediaUrl: content.remoteUri ?? content.image ?? content.video ?? content.audio ?? content.file,
            thumbnailUrl: content.thumbnail,
            fileName: content.fileName,
            fileSize: content.size != nil ? Int64(content.size!) : nil,
            mimeType: content.mimeType,
            duration: content.videoDuration ?? content.audioDuration,
            waveform: content.waveform,
            latitude: content.location?.coords.lat,
            longitude: content.location?.coords.lng,
            address: content.location?.address,
            contactName: content.contact?.first?.name,
            contactPhone: content.contact?.first?.phone,
            metadata: metadata.isEmpty ? nil : metadata
        )
    }
}
