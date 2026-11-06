import Foundation
import WaanguCoreKit

/// MQTT topic names for chat — aligned with Android `ChatTopics`.
///
/// IN  = topics the client publishes to (backend listens)
/// OUT = topics the client subscribes to (backend publishes to us)
public enum ChatMQTTTopics {

    private static let prefix = "waangu-chat"

    public static func topic(_ path: String) -> RealtimeTopic {
        RealtimeTopic("\(prefix)/\(path)")
    }

    /// Per-user inbox — all inbound message events land here: `waangu-chat/{userId}`.
    public static func userInbox(userId: String) -> RealtimeTopic {
        topic(userId)
    }

    /// Registration pattern for any user inbox: `waangu-chat/+`.
    public static let userInboxPattern = topic("+")

    /// Live location ticks, which are the only chat traffic outside the
    /// `waangu-chat/` tree: one topic per share, `live-shares/{shareId}/…`.
    ///
    /// Separate from `In` because those are all static paths and these are
    /// built per share — and because a tick must never be treated like the
    /// durable messages listed there.
    public enum LiveShare {
        /// A GPS position for a running share.
        public static func location(shareId: String) -> RealtimeTopic {
            RealtimeTopic("live-shares/\(shareId)/location")
        }

        /// Ends a share, optionally carrying its final position.
        public static func stop(shareId: String) -> RealtimeTopic {
            RealtimeTopic("live-shares/\(shareId)/stop")
        }
    }

    /// Notifications d'évolution d'objet financier.
    ///
    /// **Sens unique : aucun topic `In`.** Le Chat ne publie jamais d'ordre de
    /// paiement sur MQTT. Toute écriture financière passe par HTTP, le pipeline
    /// `TransactionStep` et une clé d'idempotence — un message MQTT n'offre ni
    /// réponse corrélée, ni garantie d'unicité, ni statut d'erreur exploitable.
    ///
    /// Le payload reçu ne porte **jamais** de statut exploitable : uniquement la
    /// référence à requêter côté serveur. Un statut transporté par le fil serait
    /// une vérité financière circulant hors du canal qui fait autorité.
    ///
    /// **BACKEND CONTRACT REQUIRED** — contrat #7.
    public enum Finance {
        /// Un objet financier de cet utilisateur a changé : `waangu-chat/{userId}/finance-object-changed`.
        public static func objectChanged(userId: String) -> RealtimeTopic {
            topic("\(userId)/finance-object-changed")
        }
    }

    public enum In {
        public static let sendMessage = topic("send-message")
        /// Maps a share to its conversation in Redis. Published once, after the
        /// anchor message is acknowledged — a tick for an unknown share is
        /// dropped by Realtime.
        public static let liveLocationStart = topic("live-location/start")
        public static let modifyMessage = topic("modify-message")
        public static let reactMessage = topic("react-message")
        public static let deleteMessage = topic("delete-message")
        public static let removeReaction = topic("remove-reaction")
        public static let forwardMessage = topic("forward-message")
        public static let reportMessage = topic("report-message")
        public static let typing = topic("typing")
        public static let starMessage = topic("star-message")
        public static let unstarMessage = topic("unstar-message")
        public static let pinMessage = topic("pin-message")
        public static let unpinMessage = topic("unpin-message")
        public static let markAsRead = topic("mark-as-read")
        public static let markDelivered = topic("mark-delivered")
        public static let createPoll = topic("create-poll")
        public static let votePoll = topic("vote-poll")
        public static let createConversation = topic("create-conversation")
        public static let presence = topic("presence")
        public static let viewStory = topic("view-story")
        public static let deleteStory = topic("delete-story")
        public static let reactStory = topic("react-story")

        // ── Calls ─────────────────────────────────────────────
        // Signaling only; media rides the SFU. Every payload carries sessionId
        // (and deviceId where known) per the call integration contract.
        public static let callOffer = topic("call-offer")
        public static let callJoin = topic("call-join")
        public static let callReject = topic("call-reject")
        public static let callIce = topic("call-ice")
        public static let callProduce = topic("call-produce")
        public static let callConsume = topic("call-consume")
        public static let callMute = topic("call-mute")
        public static let callVideo = topic("call-video")
        public static let callScreenShareStart = topic("call-screen-share-start")
        public static let callScreenShareStop = topic("call-screen-share-stop")
        public static let callHeartbeat = topic("call-heartbeat")
        public static let callPing = topic("call-ping")
        public static let callReconnect = topic("call-reconnect")
        public static let callTransferDevice = topic("call-transfer-device")
        public static let callInvitePeers = topic("call-invite-peers")
        public static let callDisconnect = topic("call-disconnect")
        public static let callUserDisconnect = topic("call-user-disconnect")

        // ── Call conference features (CALL-INTEGRATION V3 §16) ────────
        // Additive: they act inside a call that already exists and never
        // start one.
        public static let callHandRaise = topic("call-hand-raise")
        public static let callHandLower = topic("call-hand-lower")
        public static let callHandAck = topic("call-hand-ack")
        public static let callReaction = topic("call-reaction")

        public static let allCallTopics: [RealtimeTopic] = [
            callOffer,
            callJoin,
            callReject,
            callIce,
            callProduce,
            callConsume,
            callMute,
            callVideo,
            callScreenShareStart,
            callScreenShareStop,
            callHeartbeat,
            callPing,
            callReconnect,
            callTransferDevice,
            callInvitePeers,
            callDisconnect,
            callUserDisconnect,
            callHandRaise,
            callHandLower,
            callHandAck,
            callReaction
        ]

        public static let allPublishTopics: [RealtimeTopic] = [
            sendMessage,
            liveLocationStart,
            modifyMessage,
            reactMessage,
            deleteMessage,
            removeReaction,
            forwardMessage,
            reportMessage,
            typing,
            starMessage,
            unstarMessage,
            pinMessage,
            unpinMessage,
            markAsRead,
            markDelivered,
            createPoll,
            votePoll,
            createConversation,
            presence,
            viewStory,
            deleteStory,
            reactStory
        ] + allCallTopics
    }

    public enum Out {
        /// Typing broadcasts, handled by `PresenceRepository` and fanned out per
        /// conversation by the backend: `waangu-chat/typing/{conversationId}`.
        ///
        /// `#` rather than `+` on purpose. A subscription to `waangu-chat/typing`
        /// receives nothing once the backend appends the conversation id, and a
        /// `+` subscription receives nothing if it ever publishes flat again —
        /// `#` matches the parent level and everything under it, so the client
        /// keeps working through the switch either way.
        public static let typing = topic("typing/#")
        /// Presence stays on its dedicated topic (handled by PresenceRepository).
        public static let presence = topic("presence")
    }
}
