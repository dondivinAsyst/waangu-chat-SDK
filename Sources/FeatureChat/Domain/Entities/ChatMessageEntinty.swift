//
//  ChatMessageEntinty.swift
//  Waangu Driver
//
//  Created by Asyst on 2/24/26.
//

import Foundation

public struct ChatMessageEntity: Identifiable, Equatable {
    public let id: String
    public let conversationId: String
    public let senderId: String
    public let text: String
    public let timestamp: Date
    
    public init(
        id: String,
        conversationId: String,
        senderId: String,
        text: String,
        timestamp: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
    }
}
