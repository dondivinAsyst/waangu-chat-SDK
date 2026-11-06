//
//  ChatRealtimeRegistration.swift
//  AppModules
//
//  Created by Asyst on 7/2/26.
//
import Foundation
import WaanguCoreKit

public enum ChatRealtimeRegistration: RealtimeRegistrable {
    public static var topicRegistrations: [TopicRegistration] {
        var registrations: [TopicRegistration] = []

        // Per-user message inbox: waangu-chat/{userId}
        // maintainBriefly: VoIP / CallKit wakes need the inbox while backgrounded
        // so call-join answers and CALL_* events are not dropped on suspend.
        registrations.append(
            TopicRegistration(
                topicPattern: ChatMQTTTopics.userInboxPattern,
                qos: .atLeastOnce,
                backgroundPolicy: .maintainBriefly,
                bufferingPolicy: .unbounded,
                priority: .high,
                description: "Inbound chat MQTT: user inbox (waangu-chat/{userId})"
            )
        )

        // Typing + presence remain on dedicated topics
        for topic in [ChatMQTTTopics.Out.typing, ChatMQTTTopics.Out.presence] {
            registrations.append(
                TopicRegistration(
                    topicPattern: topic,
                    qos: .fireAndForget,
                    backgroundPolicy: .disconnect,
                    bufferingPolicy: .bufferNewest(8),
                    priority: .low,
                    description: "Inbound chat MQTT: \(topic.path)"
                )
            )
        }

        for topic in ChatMQTTTopics.In.allPublishTopics {
            let isTyping = topic == ChatMQTTTopics.In.typing || topic == ChatMQTTTopics.In.presence
            registrations.append(
                TopicRegistration(
                    topicPattern: topic,
                    qos: isTyping ? .fireAndForget : .atLeastOnce,
                    backgroundPolicy: isTyping ? .disconnect : .keepAlive,
                    bufferingPolicy: .unbounded,
                    priority: isTyping ? .low : .high,
                    description: "Outbound chat MQTT: \(topic.path)"
                )
            )
        }

        return registrations
    }
}
