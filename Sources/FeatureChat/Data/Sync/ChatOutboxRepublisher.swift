//
//  ChatOutboxRepublisher.swift
//  FeatureChat
//
//  Replays a queued action over MQTT — the same topic, QoS and priority its
//  original publisher used, so the server cannot tell a replay from a first
//  attempt and answers it with the same acknowledgement.
//
//  The stored payload is already-encoded JSON, and `publish` is generic over
//  `Encodable`: handing it `Data` would base64 the body. So each action is
//  decoded back into its DTO before going out.
//

import Foundation
import WaanguCoreKit

enum ChatOutboxRepublishError: Error {
    /// The payload no longer decodes into the DTO its action type calls for.
    case undecodablePayload(actionType: String)
    /// An action type with no outbound topic — never enqueued today.
    case unsupportedAction(actionType: String)
}

enum ChatOutboxRepublisher {

    static func republish(
        _ item: ChatOutboxItem,
        realtime: any RealtimeClientProtocol
    ) async throws {
        switch item.actionType {

        case .sendMessage:
            try await publish(item, as: OutboundMessageDTO.self,
                              to: ChatMQTTTopics.In.sendMessage, priority: .high, realtime: realtime)

        case .modifyMessage:
            try await publish(item, as: OutboundModifyMessageDTO.self,
                              to: ChatMQTTTopics.In.modifyMessage, priority: .high, realtime: realtime)

        case .deleteMessage:
            try await publish(item, as: OutboundMessageDeleteDTO.self,
                              to: ChatMQTTTopics.In.deleteMessage, priority: .high, realtime: realtime)

        case .reaction:
            // One action type, two payload shapes. The key's trailing verb is what
            // separates them — the DTOs themselves are too close to tell apart.
            if item.idempotencyKey.hasSuffix(":remove") {
                try await publish(item, as: OutboundRemoveReactionDTO.self,
                                  to: ChatMQTTTopics.In.removeReaction, priority: .high, realtime: realtime)
            } else {
                try await publish(item, as: OutboundReactMessageDTO.self,
                                  to: ChatMQTTTopics.In.reactMessage, priority: .high, realtime: realtime)
            }

        case .pollVote:
            try await publish(item, as: OutboundVotePollDTO.self,
                              to: ChatMQTTTopics.In.votePoll, priority: .high, realtime: realtime)

        case .deliveryReceipt:
            try await publish(item, as: OutboundMarkDeliveredDTO.self,
                              to: ChatMQTTTopics.In.markDelivered, priority: .normal, realtime: realtime)

        case .readReceipt:
            try await publish(item, as: OutboundMarkAsReadDTO.self,
                              to: ChatMQTTTopics.In.markAsRead, priority: .normal, realtime: realtime)

        case .viewStory:
            try await publish(item, as: OutboundViewStoryDTO.self,
                              to: ChatMQTTTopics.In.viewStory, priority: .normal, realtime: realtime)

        case .deleteStory:
            try await publish(item, as: OutboundDeleteStoryDTO.self,
                              to: ChatMQTTTopics.In.deleteStory, priority: .high, realtime: realtime)

        case .reactStory:
            try await publish(item, as: OutboundReactStoryDTO.self,
                              to: ChatMQTTTopics.In.reactStory, priority: .normal, realtime: realtime)

        case .participantEvent, .conversationEvent, .statusEvent:
            // No publisher ever enqueues these, so no topic was ever chosen for
            // them. Replaying a guess would send the server something no first
            // attempt ever sends.
            throw ChatOutboxRepublishError.unsupportedAction(actionType: item.actionTypeString)
        }
    }

    // MARK: - Private

    private static func publish<T: Decodable & Encodable & Sendable>(
        _ item: ChatOutboxItem,
        as type: T.Type,
        to topic: RealtimeTopic,
        priority: MessagePriority,
        realtime: any RealtimeClientProtocol
    ) async throws {
        guard let dto = try? JSONDecoder().decode(type, from: item.payload) else {
            throw ChatOutboxRepublishError.undecodablePayload(actionType: item.actionTypeString)
        }
        try await realtime.publish(dto, to: topic, qos: .atLeastOnce, priority: priority)
    }
}
