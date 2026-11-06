import Foundation

/// Event type strings inside MQTT payloads — aligned with Android `ChatMqttEvents`.
enum ChatMqttEvents {
    static let typing = "TYPING"

    /// Identity revoked this session; Realtime forwards it on the user's inbox. The payload shape
    /// is not documented yet (asked of Chat Core), so only the event type is read.
    static let sessionRevoked = "SESSION_REVOKED"
    static let ack = "ACK"
    static let messageSent = "MESSAGE_SENT"
    static let messageDelivered = "MESSAGE_DELIVERED"
    static let messageRead = "MESSAGE_READ"
    static let messageDeleted = "MESSAGE_DELETED"
    static let messageModified = "MESSAGE_MODIFIED"
    static let messageReactionAdded = "MESSAGE_REACTION_ADDED"
    static let messageReactionRemoved = "MESSAGE_REACTION_REMOVED"

    /// A vote cast on a poll message. The contract names neither the event nor
    /// its payload shape, so both spellings seen so far are accepted until it
    /// does — a vote that parses as nothing would be lost in silence.
    static let pollVoted = "POLL_VOTED"
    static let pollVote = "POLL_VOTE"

    /// A GPS tick of a live location share, and the end of one. Both ride the
    /// user inbox alongside messages, and neither is ever persisted: the feed
    /// keeps the `LOCATION` anchor message, these only move its pin.
    ///
    /// `LIVE_LOCATION_UPDATE` always arrives with `suppressNotification: true`
    /// — nothing to honour on this side, since an event we never store can
    /// raise no badge.
    static let liveLocationUpdate = "LIVE_LOCATION_UPDATE"
    static let liveLocationStop = "LIVE_LOCATION_STOP"

    /// Un objet financier de cet utilisateur a changé.
    ///
    /// Ne porte **jamais** de statut : uniquement la référence à requêter. Un
    /// statut transporté par MQTT arriverait sans garantie d'ordre, sans
    /// signature vérifiable et sans corrélation à la requête qui l'a produit.
    /// Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §5.5.
    static let financeObjectChanged = "FINANCE_OBJECT_CHANGED"
    /// Pointeur Chat Core réel — INTEGRATION_CHAT_FINANCE.md §11.1, en majuscules
    /// comme le parseur normalise tous les `eventType`.
    static let chatCoreFinancialObjectChanged = "CONVERSATION.FINANCIAL.OBJECT_CHANGED"
    /// Un litige s'ouvre ou se ferme : la carte du litige se relit (réponse du
    /// backend, Q11). En majuscules, comme le parseur normalise les `eventType`.
    static let financialDisputeOpened = "CONVERSATION.FINANCIAL.DISPUTE.OPENED"
    static let financialDisputeClosed = "CONVERSATION.FINANCIAL.DISPUTE.CLOSED"

    static let storyCreated = "STORY_CREATED"
    static let storyViewed = "STORY_VIEWED"
    static let storyDeleted = "STORY_DELETED"
    static let storyReacted = "STORY_REACTED"
    static let storyExpired = "STORY_EXPIRED"

    /// Call events. All arrive on the same user inbox as everything else and are
    /// distinguished by `category == "call"` on the envelope.
    enum Call {
        static let category = "call"

        static let initiated = "CALL_INITIATED"
        static let offerMedia = "CALL_OFFER_MEDIA"
        static let mediaAnswer = "CALL_MEDIA_ANSWER"
        static let iceAnswer = "CALL_ICE_ANSWER"
        static let newProducer = "CALL_NEW_PRODUCER"
        static let consumerCreated = "CALL_CONSUMER_CREATED"
        static let peerJoined = "CALL_PEER_JOINED"
        static let peerLeft = "CALL_PEER_LEFT"
        static let answered = "CALL_ANSWERED"
        static let rejected = "CALL_REJECTED"
        static let busy = "CALL_BUSY"
        static let missed = "CALL_MISSED"
        static let ended = "CALL_ENDED"
        static let statusChanged = "CALL_STATUS_CHANGED"
        static let deviceTransferred = "CALL_DEVICE_TRANSFERRED"
        static let reconnecting = "CALL_RECONNECTING"
        static let pong = "CALL_PONG"
        static let error = "CALL_ERROR"
        static let hold = "CALL_HOLD"
        /// Agent transfer (§9.4) — a different person takes over the far end.
        /// Not the same as `deviceTransferred`, which is one user's own devices.
        static let transferred = "CALL_TRANSFERRED"
        static let producerState = "CALL_PRODUCER_STATE"
        static let screenShareStarted = "CALL_SCREEN_SHARE_STARTED"
        static let screenShareStopped = "CALL_SCREEN_SHARE_STOPPED"

        // ── Conference features (§16) ─────────────────────────────────
        /// A participant asked to speak. `REQUEST_TO_SPEAK` accompanies
        /// `HAND_RAISED` for the same act, so both mean the same state change.
        static let handRaised = "HAND_RAISED"
        static let requestToSpeak = "REQUEST_TO_SPEAK"
        static let handLowered = "HAND_LOWERED"
        static let handAcknowledged = "HAND_ACKNOWLEDGED"
        static let reaction = "CALL_REACTION"

        /// Feature events carry no `CALL_` prefix, so the parser cannot infer
        /// them from the name alone.
        static let featureEventTypes: Set<String> = [
            handRaised,
            requestToSpeak,
            handLowered,
            handAcknowledged
        ]
    }

    /// Group lifecycle events. They arrive on the same user inbox as messages and
    /// describe a change to a conversation rather than something a user sent.
    ///
    /// The backend projects each one into the thread, so they are handled as
    /// system messages on the ordinary message path — `GroupSystemEventNormalizer`
    /// rewrites the payload into message shape before it reaches the parser's
    /// message branch.
    enum Group {
        static let created = "GROUP_CREATED"
        static let updated = "GROUP_UPDATED"
        static let userAdded = "USER_ADDED_TO_GROUP"
        static let userLeft = "USER_LEFT_GROUP"
        static let userRemoved = "USER_REMOVED_FROM_GROUP"
        static let userPromoted = "USER_PROMOTED_TO_ADMIN"
        static let userDemoted = "USER_DEMOTED_FROM_ADMIN"

        static let all: Set<String> = [
            created, updated, userAdded, userLeft,
            userRemoved, userPromoted, userDemoted
        ]
    }

    /// True for an event `ChatMqttEventParser` returns nil on **by design**,
    /// because another subscriber on this same topic owns it.
    ///
    /// Both matter for the inbound log and nothing else. `CallSignalingRepository`
    /// subscribes to the very same user inbox, so every `CALL_*` event is
    /// delivered to the chat parser as well and falls through its `default:`.
    /// Logging those as unhandled would mean a warning per call event — the
    /// noise would bury the one case worth seeing, an event genuinely nobody
    /// handles.
    static func isHandledElsewhere(_ eventType: String) -> Bool {
        if eventType == typing { return true }
        if eventType.hasPrefix("CALL_") { return true }
        // The conference events carry no `CALL_` prefix, so the name alone
        // cannot place them — the same reason `featureEventTypes` exists.
        return Call.featureEventTypes.contains(eventType)
    }

    /// ACK.payload.operation values (backend may send with or without underscore).
    enum AckOperation {
        static let messageSent = "MESSAGESENT"
        static let messageRead = "MESSAGEREAD"
        static let messageModified = "MESSAGEMODIFIED"
        static let messageDeleted = "MESSAGEDELETED"
    }

    enum AckStatus {
        static let success = "SUCCESS"
        static let failed = "FAILED"
        static let failure = "FAILURE"
    }
}
