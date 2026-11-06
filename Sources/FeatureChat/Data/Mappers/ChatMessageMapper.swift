//
//  ChatMessageMapper.swift
//  Waangu
//

import Foundation

struct ChatMessageMapper {

    static func toEntity(_ dto: InboundMessageDTO) -> ChatMessageEntity {
        ChatMessageEntity(
            id: dto.codeMessage,
            conversationId: dto.conversationId ?? "",  // Handle optional conversationId
            senderId: dto.senderId,
            text: dto.messageContent.text ?? dto.content,
            timestamp: Date(timeIntervalSince1970: dto.resolvedTimestamp)
        )
    }
}
