import Foundation
import WaanguCoreKit

/// Publishes the three live location signals: start, tick, stop.
///
/// None of them touch the outbox, which is the difference from every other
/// publisher in this feature. The outbox exists to replay what must not be
/// lost; a live position is the opposite — it is true for a few seconds and
/// then it is a lie. Only the anchor message is durable, and that goes out on
/// the ordinary message path.
enum LiveLocationPublisher {

    /// Maps the share to its conversation, once, after the anchor is acked.
    ///
    /// Realtime drops ticks for a share it has never seen, so nothing else can
    /// usefully happen until this lands.
    static func publishStart(
        shareId: String,
        conversationId: String,
        codeMessage: String,
        durationMinutes: Int,
        expiresAt: Date,
        userId: String = CurrentSessionInfo.shared.currentUid,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !shareId.isEmpty, !userId.isEmpty, !conversationId.isEmpty else { return }
        guard expiresAt > Date() else { return }

        let dto = OutboundLiveLocationStartDTO(
            shareId: shareId,
            userId: userId,
            conversationId: conversationId,
            codeMessage: codeMessage,
            durationMinutes: durationMinutes,
            expiresAt: expiresAt.epochMilliseconds
        )

        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.liveLocationStart,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    /// One GPS position.
    ///
    /// Skipped entirely while the connection is down rather than published and
    /// queued: `publish` hands anything it cannot send to the offline queue,
    /// and a tick flushed after a reconnect would move a watcher's pin to where
    /// the sender was minutes ago. The next tick is only seconds away.
    static func publishTick(
        shareId: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double?,
        expiresAt: Date,
        bootstrap: (conversationId: String, codeMessage: String)? = nil,
        measuredAt: Date = Date(),
        userId: String = CurrentSessionInfo.shared.currentUid,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !shareId.isEmpty, !userId.isEmpty else { return }
        guard await realtime.connectionState.isConnected else { return }

        let dto = OutboundLiveLocationTickDTO(
            shareId: shareId,
            userId: userId,
            lat: latitude,
            lng: longitude,
            accuracy: accuracy,
            timestamp: measuredAt.epochMilliseconds,
            expiresAt: expiresAt.epochMilliseconds,
            conversationId: bootstrap?.conversationId,
            codeMessage: bootstrap?.codeMessage
        )

        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.LiveShare.location(shareId: shareId),
            qos: .fireAndForget,
            priority: .low
        )
    }

    /// Ends the share, carrying the final position when one is known.
    ///
    /// Published at `atLeastOnce` and left to the offline queue if the
    /// connection is down: unlike a tick, a stop that arrives late still says
    /// something true — the share is over.
    static func publishStop(
        shareId: String,
        latitude: Double?,
        longitude: Double?,
        accuracy: Double?,
        userId: String = CurrentSessionInfo.shared.currentUid,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !shareId.isEmpty, !userId.isEmpty else { return }

        let dto = OutboundLiveLocationStopDTO(
            shareId: shareId,
            userId: userId,
            lat: latitude,
            lng: longitude,
            accuracy: accuracy
        )

        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.LiveShare.stop(shareId: shareId),
            qos: .atLeastOnce,
            priority: .high
        )
    }
}

extension Date {
    /// Epoch milliseconds, which is what every timestamp on this wire uses.
    var epochMilliseconds: Double {
        (timeIntervalSince1970 * 1000).rounded()
    }
}
