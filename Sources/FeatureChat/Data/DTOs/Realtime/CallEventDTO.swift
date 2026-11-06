// FeatureChat/Data/DTOs/Realtime/CallEventDTO.swift
//
// Call signaling payloads.
//
// Outbound: one struct per `waangu-chat/call-*` command topic.
// Inbound:  a single envelope on `waangu-chat/{userId}`, filtered by
//           `category == "call"` and dispatched on `eventType`.
//
// MQTT carries signaling only — media rides the Mediasoup SFU.
//
// Every outbound payload carries `sessionId`; the server rejects anything
// without a live session. `deviceId` is included wherever multi-device handoff
// depends on it (offer, join, transfer).

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: Participants
// ─────────────────────────────────────────────────────────────

public struct CallParticipantDTO: Codable, Sendable {
    public let userId: String
    public let username: String
    public let phone: String?

    public init(userId: String, username: String, phone: String? = nil) {
        self.userId = userId
        self.username = username
        self.phone = phone
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Outbound — call setup
// ─────────────────────────────────────────────────────────────

/// `call-offer` — starts a call.
///
/// `roomId` is generated client side and doubles as the idempotency key.
/// `conversationId` is required for the call to reach server-side history.
public struct CallOfferDTO: Codable, Sendable {
    public let sessionId: String
    public let deviceId: String
    public let roomId: String
    public let peerId: String
    public let conversationId: String?
    public let type: String              // "audio" | "video"
    public let participants: [CallParticipantDTO]

    public init(
        sessionId: String,
        deviceId: String,
        roomId: String,
        peerId: String,
        conversationId: String?,
        type: String,
        participants: [CallParticipantDTO]
    ) {
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.roomId = roomId
        self.peerId = peerId
        self.conversationId = conversationId
        self.type = type
        self.participants = participants
    }
}

/// `call-join` — accepts or rejoins a call.
public struct CallJoinDTO: Codable, Sendable {
    public let sessionId: String
    public let deviceId: String
    public let roomId: String
    public let peerId: String
    public let user: CallParticipantDTO

    public init(
        sessionId: String,
        deviceId: String,
        roomId: String,
        peerId: String,
        user: CallParticipantDTO
    ) {
        self.sessionId = sessionId
        self.deviceId = deviceId
        self.roomId = roomId
        self.peerId = peerId
        self.user = user
    }
}

/// `call-reject` — declines an incoming call.
public struct CallRejectDTO: Codable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let userId: String
    public let reason: String

    public init(sessionId: String, roomId: String, userId: String, reason: String = "declined") {
        self.sessionId = sessionId
        self.roomId = roomId
        self.userId = userId
        self.reason = reason
    }
}

/// `call-disconnect` — leaves or hangs up.
public struct CallDisconnectDTO: Codable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String

    public init(sessionId: String, roomId: String, peerId: String) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Outbound — in-call state
// ─────────────────────────────────────────────────────────────

/// `call-mute`.
public struct CallMuteDTO: Codable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let isMuted: Bool

    public init(sessionId: String, roomId: String, peerId: String, isMuted: Bool) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.isMuted = isMuted
    }
}

/// `call-video`.
public struct CallVideoDTO: Codable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let isVideoOff: Bool

    public init(sessionId: String, roomId: String, peerId: String, isVideoOff: Bool) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.isVideoOff = isVideoOff
    }
}

/// `call-hand-raise`, `call-hand-lower` and `call-hand-ack` (§16.1).
///
/// One type for all three: the ingress payload is identical apart from
/// `targetUserId`, which only the host's ack carries. Optional so it is omitted
/// from the JSON entirely rather than sent as null — the server reads it as the
/// participant being acted on.
public struct CallHandDTO: Codable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let callId: String?
    public let targetUserId: String?

    public init(
        sessionId: String,
        roomId: String,
        peerId: String,
        callId: String? = nil,
        targetUserId: String? = nil
    ) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.callId = callId
        self.targetUserId = targetUserId
    }
}

/// `call-reaction` (§16.2). Ephemeral — never persisted on either end.
public struct CallReactionDTO: Codable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let reaction: String

    public init(sessionId: String, roomId: String, peerId: String, reaction: String) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.reaction = reaction
    }
}

/// `call-invite-peers` — adds people to a running call. Room cap is 32.
public struct CallInvitePeersDTO: Codable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let type: String
    public let participants: [CallParticipantDTO]

    public init(
        sessionId: String,
        roomId: String,
        peerId: String,
        type: String,
        participants: [CallParticipantDTO]
    ) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.type = type
        self.participants = participants
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Outbound — SFU media
// ─────────────────────────────────────────────────────────────
//
// The three JSON blobs below (`dtlsParameters`, `rtpParameters`,
// `rtpCapabilities`) are produced by the SFU client and passed straight
// through. They are deliberately not modelled: their shape belongs to
// mediasoup, and re-declaring it here would only add a lossy round trip.

/// `call-ice` — connects a transport's DTLS. Answered by `CALL_ICE_ANSWER`.
public struct CallIceDTO: Encodable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let transportId: String
    public let dtlsParameters: RawJSONPayload

    init(
        sessionId: String,
        roomId: String,
        peerId: String,
        transportId: String,
        dtlsParameters: RawJSONPayload
    ) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.transportId = transportId
        self.dtlsParameters = dtlsParameters
    }
}

/// `call-produce` — announces a local track. The server replies with the
/// producer id, which the SFU client needs to finish creating the producer.
public struct CallProduceDTO: Encodable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let transportId: String
    public let kind: String              // "audio" | "video"
    public let rtpParameters: RawJSONPayload
    /// The contract carries both; `mediaType` distinguishes a camera from a
    /// screen share, which `kind` cannot.
    public let mediaType: String

    init(
        sessionId: String,
        roomId: String,
        peerId: String,
        transportId: String,
        kind: String,
        rtpParameters: RawJSONPayload,
        mediaType: String
    ) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.transportId = transportId
        self.kind = kind
        self.rtpParameters = rtpParameters
        self.mediaType = mediaType
    }
}

/// `call-consume` — asks for a remote producer. Answered by
/// `CALL_CONSUMER_CREATED`.
public struct CallConsumeDTO: Encodable, Sendable {
    public let sessionId: String
    public let roomId: String
    public let peerId: String
    public let transportId: String
    public let producerId: String
    public let rtpCapabilities: RawJSONPayload

    init(
        sessionId: String,
        roomId: String,
        peerId: String,
        transportId: String,
        producerId: String,
        rtpCapabilities: RawJSONPayload
    ) {
        self.sessionId = sessionId
        self.roomId = roomId
        self.peerId = peerId
        self.transportId = transportId
        self.producerId = producerId
        self.rtpCapabilities = rtpCapabilities
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Outbound — keep-alive and recovery
// ─────────────────────────────────────────────────────────────

/// `call-heartbeat` — mandatory roughly every 10s while in a call. Miss 30s and
/// the server evicts the peer from the room.
public struct CallHeartbeatDTO: Codable, Sendable {
    public let sessionId: String
    public let peerId: String
    public let roomId: String

    public init(sessionId: String, peerId: String, roomId: String) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.roomId = roomId
    }
}

/// `call-screen-share-start` / `-stop` — announces a screen share that has
/// *already* been produced.
///
/// CALL-INTEGRATION.md §8 (:379-388) shows produce-like params on this topic,
/// but it does not create the producer: the fanout it triggers
/// (`CALL_SCREEN_SHARE_STARTED`, §9.2 :666-674) carries no `producerId`, so
/// nothing on this path could complete `createProducer`. The producer comes from
/// `call-produce` with `mediaType: "screen"`; this is the announcement.
public struct CallScreenShareDTO: Codable, Sendable {
    public let sessionId: String
    public let peerId: String
    public let roomId: String

    public init(sessionId: String, peerId: String, roomId: String) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.roomId = roomId
    }
}

/// `call-ping` — session liveness probe, answered by `CALL_PONG`.
public struct CallPingDTO: Codable, Sendable {
    public let sessionId: String
    public let peerId: String
    public let roomId: String
    public let callId: String?

    public init(sessionId: String, peerId: String, roomId: String, callId: String?) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.roomId = roomId
        self.callId = callId
    }
}

/// `call-reconnect` — rebuilds transports after a network drop. Max 3 attempts.
public struct CallReconnectDTO: Codable, Sendable {
    public let sessionId: String
    public let peerId: String
    public let roomId: String
    public let tryCount: Int

    public init(sessionId: String, peerId: String, roomId: String, tryCount: Int) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.roomId = roomId
        self.tryCount = tryCount
    }
}

/// `call-user-disconnect` — this user is going away entirely (sign-out), so the
/// server should drop them from any room they are still in.
public struct CallUserDisconnectDTO: Codable, Sendable {
    public let sessionId: String
    public let userId: String

    public init(sessionId: String, userId: String) {
        self.sessionId = sessionId
        self.userId = userId
    }
}

/// `call-transfer-device` — continues the call on another device.
public struct CallTransferDeviceDTO: Codable, Sendable {
    public let sessionId: String
    public let peerId: String
    public let roomId: String
    public let fromDeviceId: String
    public let toDeviceId: String

    public init(
        sessionId: String,
        peerId: String,
        roomId: String,
        fromDeviceId: String,
        toDeviceId: String
    ) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.roomId = roomId
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Inbound — envelope
// ─────────────────────────────────────────────────────────────

/// What the client receives on `waangu-chat/{userId}` for calls.
///
/// The payload shape varies per `eventType`, so it stays as raw JSON here and is
/// read through the accessors below by whichever handler owns that event.
public struct InboundCallEventDTO: @unchecked Sendable {

    public let eventType: String
    public let payload: [String: Any]
    /// `notification.show` — whether the system should ring for this.
    public let showsNotification: Bool
    /// `ui.fullScreen` — whether the incoming call screen takes over.
    public let isFullScreen: Bool
    /// Silent signaling (ICE, producers…) that must never surface in the UI.
    public let suppressNotification: Bool
    public let timestamp: Date

    public init(
        eventType: String,
        payload: [String: Any],
        showsNotification: Bool,
        isFullScreen: Bool,
        suppressNotification: Bool,
        timestamp: Date
    ) {
        self.eventType = eventType
        self.payload = payload
        self.showsNotification = showsNotification
        self.isFullScreen = isFullScreen
        self.suppressNotification = suppressNotification
        self.timestamp = timestamp
    }
}

// MARK: - Payload accessors

public extension InboundCallEventDTO {
    var roomId: String? { payload["roomId"] as? String }
    var callId: String? { payload["callId"] as? String }
    var from: String? { payload["from"] as? String }
    var callType: String? { payload["type"] as? String }
    var isVideo: Bool { (payload["type"] as? String)?.lowercased() == "video" }
    var reason: String? { payload["reason"] as? String }
    /// Who hung up / cancelled — present on `CALL_ENDED`.
    var endedBy: String? { payload["endedBy"] as? String }
    /// Call lifecycle status — `RINGING`, `ANSWERED`, `ENDED`, `REJECTED`…
    var callStatus: String? { payload["status"] as? String }
    /// Machine-readable failure code, e.g. `CORE_INITIATE_FAILED`.
    var errorCode: String? { payload["code"] as? String }
    /// Server-side failure description. English and infrastructure-facing —
    /// for logs and diagnostics, never for display.
    var errorMessage: String? { payload["error"] as? String }
    var durationSeconds: Int? { payload["durationSec"] as? Int }

    var participants: [CallParticipantDTO] {
        guard let raw = payload["participants"] as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let userId = entry["userId"] as? String else { return nil }
            return CallParticipantDTO(
                userId: userId,
                username: entry["username"] as? String ?? "",
                phone: entry["phone"] as? String
            )
        }
    }

    /// The caller, taken from the participant list when present.
    var caller: CallParticipantDTO? {
        guard let from else { return participants.first }
        return participants.first { $0.userId == from } ?? participants.first
    }

    /// `CALL_PEER_JOINED` names the joiner in a singular `user` object rather
    /// than in `participants`, so it needs its own accessor.
    var user: CallParticipantDTO? {
        guard
            let entry = payload["user"] as? [String: Any],
            let userId = entry["userId"] as? String
        else { return nil }

        return CallParticipantDTO(
            userId: userId,
            username: entry["username"] as? String ?? "",
            phone: entry["phone"] as? String
        )
    }
}

// MARK: - Media payload accessors

public extension InboundCallEventDTO {

    var transportId: String? { payload["transportId"] as? String }
    var producerId: String? { payload["producerId"] as? String }

    /// The server names the consumer `consumerId` in most events and plain `id`
    /// inside consumer parameters.
    var consumerId: String? {
        payload["consumerId"] as? String ?? payload["id"] as? String
    }

    /// `"audio"` / `"video"` — present on producer and consumer events.
    var mediaKind: String? { payload["kind"] as? String }

    /// `"audio"` / `"video"` / `"screen"` on `CALL_NEW_PRODUCER`. Distinguishes
    /// a screen share from a camera, which `kind` cannot.
    var mediaType: String? { payload["mediaType"] as? String }
    var isScreenShare: Bool { mediaType?.lowercased() == "screen" }

    /// `CALL_PRODUCER_STATE` — whether the remote peer paused that track.
    var isPaused: Bool? { payload["isPaused"] as? Bool }

    /// Multi-device handoff, from `CALL_DEVICE_TRANSFERRED`.
    var fromDeviceId: String? { payload["fromDeviceId"] as? String }
    var toDeviceId: String? { payload["toDeviceId"] as? String }

    /// How long the callee is given to answer before the server gives up.
    var ringingTimeoutMs: Int? { payload["ringingTimeoutMs"] as? Int }

    /// Conversation the call belongs to, carried by `CALL_INITIATED`.
    var conversationId: String? { payload["conversationId"] as? String }

    /// Who a §16 feature event is about. `HAND_RAISED` names them here rather
    /// than in `peerId`, which on some events is the actor instead.
    var participantId: String? { payload["participantId"] as? String }

    /// Speaking order from the server, newest request last (§16.1).
    var speakingQueue: [String]? { payload["speakingQueue"] as? [String] }

    /// The emoji on `CALL_REACTION` (§16.2).
    var reaction: String? { payload["reaction"] as? String }

    /// Who a host action applies to — the ack's subject (§16.1 step 3).
    var targetUserId: String? { payload["targetUserId"] as? String }

    /// Which peer a producer belongs to. Field naming varies by event, so all
    /// three spellings the contract uses are accepted.
    var peerId: String? {
        payload["peerId"] as? String
            ?? payload["userId"] as? String
            ?? payload["from"] as? String
    }

    /// Re-serialises a nested JSON object back to the string the SFU client
    /// expects. Returns nil when the key is absent or is not an object.
    func rawJSON(_ key: String) -> String? {
        guard let object = payload[key] else { return nil }
        guard JSONSerialization.isValidJSONObject(object) else {
            // A bare scalar is never a valid parameters blob.
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
