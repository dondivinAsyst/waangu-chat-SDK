//
//  PendingE2EEQueueProtocol.swift
//  CoreKit
//
//  Created by Refactoring on 6/5/26.
//

import Foundation

/// Protocol item returned when dequeuing E2EE messages
public struct PendingE2EEQueueItem: Sendable {
    public let codeMessage: String        // links to the CoreData record
    public let conversationId: String
    public let recipientUserId: String
    public let localEncryptedText: Data   // AES-GCM sealed with local key
    public let messageType: String
    public let groupId: String
    public let createdAt: Date
    
    public init(
        codeMessage: String,
        conversationId: String,
        recipientUserId: String,
        localEncryptedText: Data,
        messageType: String,
        groupId: String,
        createdAt: Date
    ) {
        self.codeMessage = codeMessage
        self.conversationId = conversationId
        self.recipientUserId = recipientUserId
        self.localEncryptedText = localEncryptedText
        self.messageType = messageType
        self.groupId = groupId
        self.createdAt = createdAt
    }
}

/// Protocol for queuing messages that couldn't be E2EE-encrypted
/// because no session exists yet. Implements secure local storage
/// and batch processing when connectivity is restored.
public protocol PendingE2EEQueueProtocol: Sendable {
    
    /// Enqueues a message that failed to encrypt due to missing E2EE session
    /// - Parameters:
    ///   - codeMessage: Unique message identifier
    ///   - plaintext: Original message text to encrypt later
    ///   - conversationId: Conversation identifier
    ///   - recipientUserId: Target recipient user ID
    ///   - messageType: Type of message (default: "TEXT")
    ///   - groupId: Group identifier for group messages
    func enqueue(
        codeMessage: String,
        plaintext: String,
        conversationId: String,
        recipientUserId: String,
        messageType: String,
        groupId: String
    ) throws
    
    /// Dequeues all pending messages for a specific conversation
    /// - Parameter conversationId: Conversation to flush
    /// - Returns: Array of (plaintext, item) tuples for processing
    func dequeueAll(for conversationId: String) -> [(plaintext: String, item: PendingE2EEQueueItem)]
    
    /// Dequeues all pending messages across all conversations
    /// - Returns: Array of (plaintext, item) tuples for processing
    func dequeueAll() -> [(plaintext: String, item: PendingE2EEQueueItem)]
    
    /// Checks if there are pending items for a conversation
    /// - Parameter conversationId: Conversation to check
    /// - Returns: True if items exist for this conversation
    func hasItems(for conversationId: String) -> Bool
    
    /// Indicates if the queue is completely empty
    var isEmpty: Bool { get }
}

// MARK: - Default parameter convenience

public extension PendingE2EEQueueProtocol {
    func enqueue(
        codeMessage: String,
        plaintext: String,
        conversationId: String,
        recipientUserId: String,
        messageType: String = "TEXT",
        groupId: String = ""
    ) throws {
        try enqueue(
            codeMessage: codeMessage,
            plaintext: plaintext,
            conversationId: conversationId,
            recipientUserId: recipientUserId,
            messageType: messageType,
            groupId: groupId
        )
    }
}