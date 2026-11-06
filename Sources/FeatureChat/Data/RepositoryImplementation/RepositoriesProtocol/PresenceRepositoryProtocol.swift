import Foundation
import WaanguCoreKit

protocol PresenceRepositoryProtocol: Sendable {
    /// Subscribes to the typing topic and pumps it into `TypingStore` until the
    /// subscription ends. Throws when the realtime client is not connected yet,
    /// so the caller can retry — see `ChatPresenceLifecycle`.
    func runTypingFeed() async throws
    func sendTyping(conversationId: String, type: TypingPayloadType) async
    func sendUserPresence(status: PresenceStatus, currentRideId: String?) async
    /// The presence twin of `runTypingFeed`, with the same retry contract.
    func runPresenceFeed() async throws
    func cleanup() async
}
