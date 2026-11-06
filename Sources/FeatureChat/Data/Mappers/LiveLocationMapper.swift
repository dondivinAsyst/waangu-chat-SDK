import Foundation

/// Inbound live location DTO → domain tick.
enum LiveLocationMapper {

    /// Builds a tick from a fanned-out live location event.
    ///
    /// Returns nil when the event carried no position: a stop is allowed to
    /// arrive bare, and the caller freezes the pin it already holds instead.
    ///
    /// - Parameters:
    ///   - dto: the normalised event payload.
    ///   - at: when the position was measured, from the envelope timestamp.
    ///   - isLive: false for a stop, which keeps the position but ends the share.
    static func toTick(
        from dto: InboundLiveLocationDTO,
        at: Date,
        isLive: Bool
    ) -> LiveLocationTick? {
        guard let location = dto.location else { return nil }
        return LiveLocationTick(
            shareId: dto.shareId,
            conversationId: dto.conversationId,
            senderId: dto.senderId,
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy,
            expiresAt: dto.expiresAt.map { Date(timeIntervalSince1970: $0) },
            at: at,
            isLive: isLive
        )
    }
}
