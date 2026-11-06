import Foundation
import WaanguCoreKit

enum ViewStoryPublisher {

    /// Publishes to `waangu-chat/view-story` only after the contact segment is ready on device.
    static func publish(
        storyId: String,
        viewerId: String = CurrentSessionInfo.shared.currentUid,
        tenantId: String = CurrentSessionInfo.shared.tenantId,
        country: String = CurrentSessionInfo.shared.country,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !storyId.isEmpty, !viewerId.isEmpty else { return }

        let dto = OutboundViewStoryDTO(
            storyId: storyId,
            viewerId: viewerId,
            tenantId: tenantId,
            country: country
        )

        try? await outbox.enqueue(ChatOutboxItem.viewStory(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.viewStory,
            qos: .atLeastOnce,
            priority: .normal
        )
    }
}

enum DeleteStoryPublisher {

    static func publish(
        storyId: String,
        deletedBy: String,
        tenantId: String = CurrentSessionInfo.shared.tenantId,
        country: String = CurrentSessionInfo.shared.country,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !storyId.isEmpty, !deletedBy.isEmpty else { return }

        let dto = OutboundDeleteStoryDTO(
            storyId: storyId,
            deletedBy: deletedBy,
            tenantId: tenantId,
            country: country
        )

        try? await outbox.enqueue(ChatOutboxItem.deleteStory(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.deleteStory,
            qos: .atLeastOnce,
            priority: .high
        )
    }
}

enum ReactStoryPublisher {

    static func publish(
        storyId: String,
        userId: String,
        reaction: String,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !storyId.isEmpty, !userId.isEmpty, !reaction.isEmpty else { return }

        let dto = OutboundReactStoryDTO(
            storyId: storyId,
            userId: userId,
            reaction: reaction
        )

        try? await outbox.enqueue(ChatOutboxItem.reactStory(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.reactStory,
            qos: .atLeastOnce,
            priority: .normal
        )
    }
}
