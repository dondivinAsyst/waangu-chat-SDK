import Foundation
import Combine
import AVFoundation
import UIKit
import SwiftUI
import WaanguCoreKit

enum CallPhase: Equatable {
    case idle
    case incomingRinging(handle: String, isVideo: Bool)
    case outgoingRinging(handle: String, isVideo: Bool)
    case connecting
    case connected(isVideo: Bool)
    case ended
    
    var isActive: Bool {
        switch self {
        case .idle, .ended: return false
        default: return true
        }
    }

    /// Ringing, connecting, or connected — excludes ended/idle.
    var isLiveCall: Bool { isActive }

    /// Live call chrome (full screen or banner) — excludes the brief ended state.
    var showsLiveCallChrome: Bool {
        switch self {
        case .incomingRinging, .outgoingRinging, .connecting, .connected:
            return true
        case .idle, .ended:
            return false
        }
    }

    /// Phases where a minimised call has something to put in a floating window.
    ///
    /// An incoming ring is excluded: it is a decision to make, not a call to
    /// carry around, and there is no media behind it yet.
    var supportsPictureInPicture: Bool {
        switch self {
        case .outgoingRinging, .connecting, .connected:
            return true
        case .incomingRinging, .idle, .ended:
            return false
        }
    }
}

/// AppTarget asks this before suspending MQTT. FeatureChat owns call state;
/// the app must not reach into `VoipManager` directly.
@MainActor
public enum ChatCallLifecycle {
    /// Ringing or connected — keep realtime up so CallKit Accept can publish `call-join`.
    public static var shouldRetainRealtimeConnection: Bool {
        VoipManager.shared.callPhase.isActive
    }
}

/// What the call screen says is happening, right now.
///
/// Separate from `CallPhase`, which drives *which* screen shows. This is the one
/// line of text under the name, and it is the thing a user actually reads to
/// know whether the far end is ringing, busy, or gone.
enum CallStatus: Equatable {
    case connecting
    /// Offer accepted by the broker; the far end is not known to be alerting yet.
    case calling
    /// The callee's device is ringing.
    case ringing
    case connected
    case reconnecting
    /// The far end is already on another call.
    case busy
    case declined
    case noAnswer
    case failed
    case ended

    /// Translation key for the text shown under the caller's name.
    var translationKey: String {
        switch self {
        case .connecting:   return ChatTranslationKeys.CALLS_CONNECTING
        case .calling:      return ChatTranslationKeys.CALLS_CALLING
        case .ringing:      return ChatTranslationKeys.CALLS_RINGING
        case .connected:    return ChatTranslationKeys.CALLS_CONNECTED
        case .reconnecting: return ChatTranslationKeys.CALLS_RECONNECTING
        case .busy:         return ChatTranslationKeys.CALLS_BUSY
        case .declined:     return ChatTranslationKeys.CALLS_DECLINED
        case .noAnswer:     return ChatTranslationKeys.CALLS_NO_ANSWER
        case .failed:       return ChatTranslationKeys.CALLS_FAILED
        case .ended:        return ChatTranslationKeys.CALLS_ENDED
        }
    }
}

/// Whether a multi-device handoff concerns this device.
enum CallDeviceTransferOutcome: Equatable {
    /// This device keeps the call — either it is the one that answered, or there
    /// is not enough information to say it is not.
    case keepCall
    /// Another device took the call; this one should let go.
    case releaseCall
}

/// MQTT command to publish when *this* device ends a call the server has not
/// already closed. Without it the far end keeps ringing after CallKit or a
/// local timeout tears the UI down.
enum CallLocalEndSignal: Equatable {
    /// Incoming still ringing — refuse so the caller gets `CALL_REJECTED`.
    case reject(reason: String)
    /// Outgoing cancel, or hang up after the call was answered.
    case disconnect
}

/// Why a call finished, when the end screen should say more than "Call ended".
enum CallEndReason: Equatable {
    /// The normal case — either side hung up.
    case hungUp
    /// The server could not carry the call.
    case failed
    /// Nobody picked up.
    case noAnswer
    /// The far end declined.
    case declined
    /// The far end was already on a call.
    case busy
}

/// Someone pulled into a running call. A presentation-level shape rather than a
/// contact entity, so the call manager stays independent of the contacts domain.
struct CallInvitee: Hashable {
    let userId: String
    let name: String
    let phone: String
}

class VoipManager: ObservableObject {
    static let shared = VoipManager()

    /// Product limit from the call signaling contract: one active call per user,
    /// 32 peers per room.
    static let maxParticipants = 32

    /// Diagnostic only — no view reads this. `callStatus` is what the user sees.
    @Published var state: String = "idle"

    /// What the call screen tells the user is happening.
    @Published var callStatus: CallStatus = .connecting
    @Published var callPhase: CallPhase = .idle
    @Published var activeCallUUID: UUID?
    @Published var callHandle: String?
    @Published var callerName: String?
    @Published var callerProfileImage: String?
    @Published var isIncoming: Bool = false
    @Published var callDuration: Int = 0
    /// Camera currently publishing (may be off mid-call without leaving the video UI).
    @Published var hasVideo: Bool = false
    /// Call was started (or upgraded) as video — drives VideoCallView vs audio layout.
    @Published var isVideoCall: Bool = false
    /// Local camera preview (or SFU local track) is on screen — used to delay `call-offer`.
    @Published var isLocalPreviewReady: Bool = false
    @Published var isMuted: Bool = false
    @Published var isOnSpeaker: Bool = false
    /// People invited after the call started, in invitation order.
    ///
    /// Append-only for the life of a call: it is what the call log records, and
    /// someone who left was still a participant.
    @Published var invitedParticipants: [CallInvitee] = []

    /// Who is on the call right now, besides this device.
    ///
    /// Shrinks on `CALL_PEER_LEFT` / invite failures and grows on invite +
    /// `CALL_PEER_JOINED`. Distinct from `invitedParticipants` because the call
    /// ends when this empties, not when someone is removed from history.
    /// Includes peers still ringing (not yet in `joinedPeerKeys`).
    @Published var remoteParticipants: [CallInvitee] = []

    /// Normalised keys of remotes who have actually joined the SFU room.
    ///
    /// Invitees sit in `remoteParticipants` as waiting tiles until they appear
    /// here via `CALL_PEER_JOINED` (or their first consumed producer).
    @Published private(set) var joinedPeerKeys: Set<String> = []

    /// Normalised keys of remotes the server has been asked to alert.
    ///
    /// The contract gives the inviter no per-participant ringing event (§9.1:
    /// `CALL_INITIATED` is fanned out to the callees only), so this is inferred
    /// from the same evidence `markRinging` uses for the one-to-one header: the
    /// server has created the room, or has accepted a mid-call invite, which is
    /// exactly when it alerts those people. Without it every invitee sat on a
    /// static "Calling…" for the whole ring, which says nothing about whether
    /// their phone is actually ringing.
    @Published private(set) var ringingPeerKeys: Set<String> = []
    /// Collapsed to the top banner: the call keeps running, the full screen steps
    /// aside so the rest of the app is usable.
    @Published var isMinimized: Bool = false

    /// Why the call finished — read by the end screen so a failure does not
    /// look like an ordinary hang-up.
    @Published var endReason: CallEndReason = .hungUp

    /// Peers who have muted themselves, by user id.
    @Published var mutedPeerIds: Set<String> = []
    /// Peers who have turned their camera off, by user id.
    @Published var cameraOffPeerIds: Set<String> = []
    /// Who is sharing their screen, if anyone. Only one peer at a time — the
    /// server refuses a second with a `CALL_ERROR`.
    @Published var screenSharingPeerId: String?

    /// True while *this* device is sharing.
    ///
    /// Separate from `screenSharingPeerId` on purpose: the server sends
    /// `CALL_SCREEN_SHARE_STARTED` to "Peers room" only (CALL-INTEGRATION.md
    /// §9.0 :419), so the sharer never receives their own event and this can
    /// never be derived from MQTT.
    @Published var isSharingScreen = false

    // ── Conference features (CALL-INTEGRATION V3 §16) ─────────────────

    /// Who has asked to speak, in server order (§16.1).
    @Published private(set) var raisedHands: [String] = []

    /// Whether this device's own hand is up.
    @Published private(set) var isHandRaised = false

    /// Reactions currently animating, newest last (§16.2). Never persisted.
    @Published private(set) var activeReactions: [CallReaction] = []

    private var handQueue = CallRaisedHands()
    private var reactionFeed = CallReactionFeed()
    private var reactionPruneTasks: [UUID: Task<Void, Never>] = [:]

    /// Whether this device may run host-only actions.
    ///
    /// The backend designates the host, but V3 never documents the payload that
    /// carries it — `room.payload.conference` appears once, in the §16 recap
    /// table, with no example and no event named. The initiator is the closest
    /// thing this device knows, and the server no-ops a non-host action anyway
    /// (§16.0 rule 3), so a wrong guess costs an inert button, not a wrong action.
    var isCallHost: Bool { !isIncoming }

    /// Translation *key* for the current screen-share error, not the message.
    ///
    /// The manager has no translation service and must not: resolving here would
    /// bake one language into state the UI then renders. The view resolves it.
    @Published var screenShareErrorKey: String?

    /// True between "user asked to share" and "camera is producing".
    ///
    /// The broadcast confirmation waits on this: sharing needs a live video call
    /// to carry it, so the switch happens first and the ask comes after.
    var isAwaitingVideoForShare = false

    /// The switch-to-video confirmation currently on screen, if any.
    ///
    /// Published rather than view-local because it is raised from two places:
    /// the call panel's own buttons, and the more sheet — which has to close
    /// before the dialog can appear over the call.
    @Published var pendingVideoSwitch: CallVideoSwitchIntent?

    /// Why the relay could not start, if it could not.
    ///
    /// Recorded when the call begins but only shown if the user actually taps
    /// Share — a broken App Group should not interrupt a call that is otherwise
    /// working, but it must not be invisible either.
    @Published var screenShareUnavailableReason: String?

    /// Whether the camera was on before the share, so it is restored only if the
    /// user actually had it on.
    var screenShareCameraState = ScreenShareCameraState()

    /// Receives relayed frames from the broadcast extension. Started with the
    /// call, not with the share: the extension connects the instant the user
    /// confirms the system picker, which is before we learn about it.
    var screenFrameBridge: ScreenShareFrameBridge?

    /// This device's camera, once it is capturing. Nil on an audio call.
    @Published var localVideoTrack: (any CallVideoTrackProtocol)?
    /// Remote cameras, keyed by consumer id — one entry per peer publishing video.
    @Published var remoteVideoTracks: [String: any CallVideoTrackProtocol] = [:]
    /// The same cameras keyed by participant, which is what a grid needs.
    @Published var videoTracksByPeer: [String: any CallVideoTrackProtocol] = [:]
    /// Which participant each consumer belongs to — **every** consumer, audio
    /// and video alike.
    ///
    /// Filled at consume time from `CALL_NEW_PRODUCER.peerId`, so it is ready
    /// before the video-added event and covers audio consumers that raise no
    /// event at all. That completeness is what lets a removed track clear the
    /// right tile *and* a speech level find the peer it belongs to; while this
    /// held video only, every remote audio level was looked up here and silently
    /// discarded.
    private var consumerOwners: [String: String] = [:]

    /// Conversation this call belongs to. Nil until resolved — never a phone
    /// number, which is what previously spawned a duplicate conversation per call.
    private(set) var conversationId: String?

    var displayName: String {
        callerName ?? callHandle ?? "Unknown"
    }

    /// One identity for a participant across every source that names them.
    ///
    /// The server calls a peer by `userId`, but a call placed from a contact
    /// carries a phone number in that field, and events variously use `peerId`,
    /// `userId` or `from`. Reducing all of them to digits when they look like a
    /// phone number is what keeps a tile, its mute badge and its video track
    /// pointing at the same person — they would otherwise silently disagree.
    func participantKey(_ identifier: String) -> String {
        Self.normalizedPeerKey(identifier)
    }

    /// `participantKey` as pure logic, so the removal rules below can be tested
    /// without standing up a call.
    static func normalizedPeerKey(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let digits = trimmed.onlyDigits
        // Prefer digits only for phone-like ids; bare UUIDs stay as lowercase.
        if !digits.isEmpty, digits.count >= 8 { return digits }
        return trimmed.lowercased()
    }

    // MARK: - Who owns what, when somebody leaves

    /// The consumers belonging to one peer — matched exactly, never by alias.
    ///
    /// `consumerOwners` is keyed by the normalised `CALL_NEW_PRODUCER.peerId`,
    /// and `CALL_PEER_LEFT` names the leaver through the same accessor, so there
    /// is nothing to infer here. Widening this to a roster-derived alias set is
    /// what used to evict a peer who was still on the call.
    static func consumersOwned(
        by peerKey: String,
        in consumerOwners: [String: String]
    ) -> Set<String> {
        guard !peerKey.isEmpty else { return [] }
        return Set(
            consumerOwners
                .filter { normalizedPeerKey($0.value) == peerKey }
                .map(\.key)
        )
    }

    /// Roster rows that are this peer — every clone of them, and nobody else.
    ///
    /// Rows are matched on the aliases they carry themselves. A row seeded by
    /// phone is only linked to a uuid by a row holding both, so the match reads
    /// that row directly rather than re-expanding through its neighbours, which
    /// is how one leaver used to drag unrelated rows out with them.
    static func rosterIndices(
        matching peerKey: String,
        in roster: [CallInvitee]
    ) -> [Int] {
        guard !peerKey.isEmpty else { return [] }
        return roster.indices.filter { index in
            let row = roster[index]
            return normalizedPeerKey(row.userId) == peerKey
                || normalizedPeerKey(row.phone) == peerKey
        }
    }

    /// Whether two roster rows are demonstrably the same person.
    ///
    /// True only when they carry an identifier in common. Two rows that merely
    /// both lack a phone share nothing — a blank field is an absent value, not
    /// a match — and two rows for one person stay separate until some event
    /// arrives carrying both of their identifiers.
    static func rowsShareIdentity(_ lhs: CallInvitee, _ rhs: CallInvitee) -> Bool {
        !rowIdentityKeys(lhs).isDisjoint(with: rowIdentityKeys(rhs))
    }

    private static func rowIdentityKeys(_ row: CallInvitee) -> Set<String> {
        Set([normalizedPeerKey(row.userId), normalizedPeerKey(row.phone)].filter { !$0.isEmpty })
    }

    /// The single roster row an inbound peer belongs to, if any.
    ///
    /// Only the identifiers the event itself carries are read — never an alias
    /// set expanded back through the roster, which is how an arriving peer used
    /// to land on somebody else's row and leave two people sharing it.
    ///
    /// `userId` outranks `phone`. The id is the authoritative identity while the
    /// phone is supporting data the server attaches loosely, so a phone that
    /// happens to sit on another row can never redirect the match.
    static func rosterMatch(
        userIdKey: String,
        phoneKey: String,
        in roster: [CallInvitee]
    ) -> Int? {
        func rowCarries(_ identifier: String) -> (CallInvitee) -> Bool {
            { row in
                normalizedPeerKey(row.userId) == identifier
                    || normalizedPeerKey(row.phone) == identifier
            }
        }

        if !userIdKey.isEmpty, let index = roster.firstIndex(where: rowCarries(userIdKey)) {
            return index
        }
        guard !phoneKey.isEmpty else { return nil }
        return roster.firstIndex(where: rowCarries(phoneKey))
    }

    /// The peer→track index rebuilt from the consumers that are still open.
    ///
    /// Rebuilding rather than deleting by key is the point: a slot survives for
    /// exactly as long as something is still feeding it, so closing one consumer
    /// cannot blank a tile that another consumer of the same peer still serves —
    /// a camera surviving the end of a screen share, for instance.
    static func rebuiltTrackIndex<Track>(
        consumerOwners: [String: String],
        tracks: [String: Track],
        aliases: (String) -> Set<String>
    ) -> [String: Track] {
        var index: [String: Track] = [:]
        for (consumerId, owner) in consumerOwners {
            guard let track = tracks[consumerId] else { continue }
            for alias in aliases(owner) where !alias.isEmpty {
                index[alias] = track
            }
        }
        return index
    }

    /// Every normalised id that means "this device" (account uid + phone).
    ///
    /// Empty while the session is still loading, and deliberately so: an empty
    /// set means "cannot prove anything is us", which is honest. It used to
    /// contain the string `"unknown"` — a sentinel that matched any peer whose
    /// id normalised to it and quietly dropped them from the call.
    private var selfIdentityKeys: Set<String> {
        var keys = Set<String>()
        if let uid = currentUserIdentifier {
            let key = participantKey(uid)
            if !key.isEmpty { keys.insert(key) }
        }
        let phone = participantKey(CurrentSessionInfo.shared.userPhoneNumber)
        if !phone.isEmpty { keys.insert(phone) }
        return keys
    }

    /// This device's account id, or nil when the session has not loaded yet.
    ///
    /// `CurrentSessionInfo` reads through an `AppSettings` that is injected
    /// during `ChatFeature.bootstrap()`, so every field is empty before that
    /// lands — which for a call answered straight from a push is exactly when
    /// the first participant list arrives.
    private var currentUserIdentifier: String? {
        let uid = CurrentSessionInfo.shared.currentUid
        if !uid.isEmpty { return uid }
        guard let stored = UserDefaults.standard.string(forKey: "currentUserId"),
              !stored.isEmpty else { return nil }
        return stored
    }

    /// True when `peerId` is us (uid or phone) — used to drop echo producers.
    func isSelfPeerId(_ peerId: String?) -> Bool {
        guard let peerId else { return false }
        let key = participantKey(peerId)
        guard !key.isEmpty else { return false }
        return selfIdentityKeys.contains(key)
    }

    /// `CALL_CONSUMER_CREATED.peerId` names the consuming peer (often us). Only
    /// accept it when it clearly refers to someone else in the room.
    private func remoteProducerOwnerKey(for peerId: String?) -> String? {
        guard let peerId, !isSelfPeerId(peerId) else { return nil }
        let key = participantKey(peerId)
        return key.isEmpty ? nil : key
    }

    /// Aliases that belong to one roster row only (never other peers).
    private func identityKeys(for participant: CallInvitee) -> Set<String> {
        var keys = Set<String>()
        let userKey = participantKey(participant.userId)
        let phoneKey = participantKey(participant.phone)
        if !userKey.isEmpty { keys.insert(userKey) }
        if !phoneKey.isEmpty { keys.insert(phoneKey) }
        return keys
    }

    /// Aliases for a peer id, limited to the single matching roster entry.
    private func identityKeys(forPeerId peerId: String) -> Set<String> {
        let key = participantKey(peerId)
        guard !key.isEmpty else { return [] }
        if let match = remoteParticipants.first(where: {
            identityKeys(for: $0).contains(key)
        }) {
            return identityKeys(for: match).union([key])
        }
        return [key]
    }

    /// Looks up a known display name for a peer id (seeded roster / invites).
    ///
    /// Matched on the same terms as the roster itself, `userId` ahead of
    /// `phone`. Invited rows carry a `userId` in their `phone` field whenever no
    /// number is known, so a plain "any field contains this key" search could
    /// settle on a different person's row and put their name on the tile.
    private func resolvedDisplayName(forPeerId peerId: String) -> String? {
        let key = participantKey(peerId)
        guard !key.isEmpty else { return nil }

        let pools = remoteParticipants + invitedParticipants
        guard let index = Self.rosterMatch(userIdKey: key, phoneKey: "", in: pools) else {
            return nil
        }

        let name = pools[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, participantKey(name) != key else { return nil }
        return name
    }

    /// Indexes a remote camera under that peer's aliases only.
    @MainActor
    private func assignVideoTrack(
        _ track: any CallVideoTrackProtocol,
        toOwnerKey ownerKey: String,
        consumerId: String
    ) {
        guard !isSelfPeerId(ownerKey) else { return }
        let keys = identityKeys(forPeerId: ownerKey)
        for key in keys {
            videoTracksByPeer[key] = track
        }
        consumerOwners[consumerId] = participantKey(ownerKey)
        upsertRemotePeer(userId: ownerKey, markJoined: true)
    }

    /// Whether this remote has joined the SFU (vs still ringing after invite).
    func isPeerJoined(_ participant: CallInvitee) -> Bool {
        !identityKeys(for: participant).isDisjoint(with: joinedPeerKeys)
    }

    func isPeerWaiting(_ participant: CallInvitee) -> Bool {
        !isPeerJoined(participant)
    }

    /// Whether the server has been asked to alert this waiting peer.
    ///
    /// Only ever true while they are still waiting: once they join, their tile
    /// shows live media and "Ringing…" would be a lie.
    func isPeerRinging(_ participant: CallInvitee) -> Bool {
        guard isPeerWaiting(participant) else { return false }
        return !identityKeys(for: participant).isDisjoint(with: ringingPeerKeys)
    }

    /// The server is alerting these people now — see `ringingPeerKeys`.
    @MainActor
    private func markPeersRinging(_ participants: [CallInvitee]) {
        var keys = ringingPeerKeys
        for participant in participants {
            keys.formUnion(identityKeys(for: participant))
        }
        guard keys != ringingPeerKeys else { return }
        ringingPeerKeys = keys
    }

    @MainActor
    private func markPeerJoined(_ participant: CallInvitee) {
        for key in identityKeys(for: participant) {
            joinedPeerKeys.insert(key)
            // They are in the room; there is nothing left to alert.
            ringingPeerKeys.remove(key)
        }
    }

    @MainActor
    private func markPeerJoined(key: String) {
        for alias in identityKeys(forPeerId: key) {
            joinedPeerKeys.insert(alias)
            ringingPeerKeys.remove(alias)
        }
    }

    /// Ensures a remote appears on the grid roster (late joiners / invitees).
    ///
    /// Merges into an existing row when uid/phone collide so we never show the
    /// same person twice, and never adds this device as a remote tile.
    @MainActor
    private func upsertRemotePeer(
        userId: String,
        name: String? = nil,
        phone: String? = nil,
        markJoined: Bool = false
    ) {
        guard !isSelfPeerId(userId) else { return }
        if let phone, isSelfPeerId(phone) { return }

        let key = participantKey(userId)
        guard !key.isEmpty else { return }

        let phoneValue: String = {
            guard let phone, !phone.isEmpty, !isSelfPeerId(phone) else { return "" }
            // Don't store a UUID peerId as "phone" — that duplicates identity keys.
            let phoneKey = participantKey(phone)
            if phoneKey == key { return "" }
            return phone
        }()

        let resolvedName = (name?.isEmpty == false ? name : nil)
            ?? resolvedDisplayName(forPeerId: userId)
            ?? (phoneValue.isEmpty ? nil : phoneValue)

        if let index = Self.rosterMatch(
            userIdKey: key,
            phoneKey: phoneValue.isEmpty ? "" : participantKey(phoneValue),
            in: remoteParticipants
        ) {
            var existing = remoteParticipants[index]
            // Prefer real usernames over raw ids.
            if let resolvedName,
               !resolvedName.isEmpty,
               participantKey(resolvedName) != key,
               (existing.name.isEmpty || participantKey(existing.name) == participantKey(existing.userId)
                || participantKey(existing.name) == participantKey(existing.phone)) {
                existing = CallInvitee(
                    userId: existing.userId,
                    name: resolvedName,
                    phone: existing.phone.isEmpty && !phoneValue.isEmpty ? phoneValue : existing.phone
                )
                remoteParticipants[index] = existing
            } else if existing.phone.isEmpty, !phoneValue.isEmpty {
                remoteParticipants[index] = CallInvitee(
                    userId: existing.userId,
                    name: existing.name,
                    phone: phoneValue
                )
            }
            if markJoined { markPeerJoined(remoteParticipants[index]) }
            return
        }

        let invitee = CallInvitee(
            userId: userId,
            name: resolvedName ?? userId,
            phone: phoneValue.isEmpty ? userId : phoneValue
        )
        // Last resort name still raw id — UI can improve once CALL_PEER_JOINED
        // or seeded participants arrive with a username.
        remoteParticipants.append(invitee)
        if !invitedParticipants.contains(where: {
            !identityKeys(for: $0).isDisjoint(with: identityKeys(for: invitee))
        }) {
            invitedParticipants.append(invitee)
        }
        if markJoined { markPeerJoined(invitee) }
        refreshLoudspeakerPolicyIfNeeded()
    }

    /// Seeds the live roster from a `CALL_INITIATED` (or similar) participant list.
    @MainActor
    private func seedRemoteParticipants(from participants: [CallParticipantDTO]) {
        var merged: [CallInvitee] = []
        for dto in participants {
            guard !isSelfPeerId(dto.userId) else { continue }
            if let phone = dto.phone, isSelfPeerId(phone) { continue }

            let phone = dto.phone ?? ""
            let name = dto.username.isEmpty
                ? (phone.isEmpty ? dto.userId : phone)
                : dto.username
            let invitee = CallInvitee(
                userId: dto.userId,
                name: name,
                phone: phone.isEmpty ? dto.userId : phone
            )

            if let index = merged.firstIndex(where: {
                !identityKeys(for: $0).isDisjoint(with: identityKeys(for: invitee))
            }) {
                let existing = merged[index]
                let betterName = (!invitee.name.isEmpty && participantKey(invitee.name) != participantKey(invitee.userId))
                    ? invitee.name : existing.name
                let betterPhone = existing.phone.isEmpty ? invitee.phone : existing.phone
                merged[index] = CallInvitee(
                    userId: existing.userId,
                    name: betterName,
                    phone: betterPhone
                )
            } else {
                merged.append(invitee)
            }
        }
        guard !merged.isEmpty else { return }
        remoteParticipants = merged
        invitedParticipants = merged
        refreshLoudspeakerPolicyIfNeeded()
    }

    /// Drops exactly one remote and only that peer's media — never other tiles.
    @MainActor
    private func removeRemotePeer(matching identifier: String) {
        let key = participantKey(identifier)
        guard !key.isEmpty else { return }
        guard !isSelfPeerId(identifier) else { return }

        // The rows that are this peer, and the aliases those rows carry. One hop
        // only: expanding an alias set back through the roster is what used to
        // let a leaver reach a neighbour's tile.
        let rowIndices = Self.rosterIndices(matching: key, in: remoteParticipants)
        var keys: Set<String> = [key]
        for index in rowIndices {
            keys.formUnion(identityKeys(for: remoteParticipants[index]))
        }

        for index in rowIndices.reversed() {
            remoteParticipants.remove(at: index)
        }
        // Dedupe leftovers in case seed + upsert left clones.
        dedupeRemoteParticipants()

        joinedPeerKeys.subtract(keys)
        // Declined, busy, or gone — their phone is not ringing any more.
        ringingPeerKeys.subtract(keys)

        for k in keys {
            mutedPeerIds.remove(k)
            cameraOffPeerIds.remove(k)
        }

        // Someone who left is gone, not reconnecting.
        clearReconnectingFlags(for: keys)

        // Media is matched exactly on the peer key the producer was announced
        // under — never on a roster-derived guess.
        var ownedConsumers = Set<String>()
        for alias in keys {
            ownedConsumers.formUnion(Self.consumersOwned(by: alias, in: consumerOwners))
        }
        for consumerId in ownedConsumers {
            remoteVideoTracks.removeValue(forKey: consumerId)
            consumerOwners.removeValue(forKey: consumerId)
        }

        // Drop producer gate bookkeeping for this peer.
        let ownedProducers = producerOwnerByProducerId
            .filter { keys.contains(participantKey($0.value)) }
            .map(\.key)
        for producerId in ownedProducers {
            producerOwnerByProducerId.removeValue(forKey: producerId)
            remoteAudioProducerIds.remove(producerId)
            remoteVideoProducerIds.remove(producerId)
            consumedRemoteAudioProducerIds.remove(producerId)
            consumedRemoteVideoProducerIds.remove(producerId)
        }

        if let sharing = screenSharingPeerId, keys.contains(participantKey(sharing)) {
            screenSharingPeerId = nil
        }

        // Rebuild rather than delete by key: a tile survives for exactly as long
        // as an open consumer still feeds it.
        reindexVideoTracksForRoster()

        refreshLoudspeakerPolicyIfNeeded()
    }

    @MainActor
    private func dedupeRemoteParticipants() {
        var result: [CallInvitee] = []
        for participant in remoteParticipants {
            if isSelfPeerId(participant.userId) || isSelfPeerId(participant.phone) {
                continue
            }
            if let index = result.firstIndex(where: {
                !identityKeys(for: $0).isDisjoint(with: identityKeys(for: participant))
            }) {
                let existing = result[index]
                let name = (participantKey(participant.name) != participantKey(participant.userId)
                    && !participant.name.isEmpty)
                    ? participant.name : existing.name
                let phone = existing.phone.isEmpty ? participant.phone : existing.phone
                result[index] = CallInvitee(userId: existing.userId, name: name, phone: phone)
            } else {
                result.append(participant)
            }
        }
        remoteParticipants = result
    }

    /// True when at least one remote is still on the call (joined or ringing).
    private var hasRemainingRemotes: Bool {
        !remoteParticipants.isEmpty
    }

    /// Video or group: loudspeaker + no proximity blanking.
    ///
    /// Counted off `isGroupCall` — the deduped roster — rather than the raw one.
    /// The two disagree: a seed-plus-upsert clone puts the same person on the
    /// roster twice, which was enough to give a one-to-one call the group audio
    /// policy while the screen kept the one-to-one layout. The speaker button
    /// then showed a toggle that `toggleSpeaker` refused to honour, so the call
    /// was pinned to loudspeaker with no way back to the earpiece.
    private var requiresLoudspeakerPolicy: Bool {
        isVideoCall || isGroupCall
    }

    /// Re-apply speaker/proximity when the call becomes (or stops being) a group.
    private func refreshLoudspeakerPolicyIfNeeded() {
        applyLoudspeakerPolicy(enabled: requiresLoudspeakerPolicy)
    }

    /// Whether this peer has muted themselves.
    func isPeerMuted(_ participant: CallInvitee) -> Bool {
        mutedPeerIds.contains(participantKey(participant.userId))
            || mutedPeerIds.contains(participantKey(participant.phone))
    }

    /// Whether this peer has turned their camera off.
    func isPeerCameraOff(_ participant: CallInvitee) -> Bool {
        cameraOffPeerIds.contains(participantKey(participant.userId))
            || cameraOffPeerIds.contains(participantKey(participant.phone))
    }

    /// This peer's live camera, if they are publishing one.
    func videoTrack(for participant: CallInvitee) -> (any CallVideoTrackProtocol)? {
        videoTracksByPeer[participantKey(participant.userId)]
            ?? videoTracksByPeer[participantKey(participant.phone)]
    }

    /// Whether this peer is the one sharing their screen.
    func isPeerSharingScreen(_ participant: CallInvitee) -> Bool {
        guard let sharing = screenSharingPeerId else { return false }
        let key = participantKey(sharing)
        return key == participantKey(participant.userId)
            || key == participantKey(participant.phone)
    }

    /// Digits-only phones of everyone who is on the call *right now*.
    ///
    /// Read off `remoteParticipants`, the roster that shrinks when someone
    /// declines, is busy, or leaves — never off `invitedParticipants`, which is
    /// append-only history for the call log. Taken from history, somebody who
    /// dropped out stayed permanently excluded from the invite picker (no way to
    /// call them back) and kept consuming a slot against `maxParticipants`.
    ///
    /// `callHandle` is deliberately not folded in: the callee is seeded into
    /// `remoteParticipants` when the call is placed, so including it again would
    /// reintroduce exactly the stale entry this property exists to avoid — the
    /// original callee of a call that has since become a group.
    var activeParticipantPhones: Set<String> {
        Self.invitablePhones(excluding: remoteParticipants)
    }

    /// `activeParticipantPhones` as pure logic, so the rule can be tested
    /// against a roster without standing up a call.
    static func invitablePhones(excluding roster: [CallInvitee]) -> Set<String> {
        Set(roster.map { $0.phone.onlyDigits }.filter { !$0.isEmpty })
    }
    
    private let callKit = CallKitManager()
    private var pushKit: PushKitManager?
    private var callTimer: Timer?
    private let ringback = CallToneController()
    private let appState = AppState.shared

    /// AVCapture preview used only when WebRTC preview prep is unavailable.
    @MainActor
    let fallbackCamera = CallCameraController()
    private var localPreviewTask: Task<Void, Never>?

    /// Outbound signaling. Nil until `ChatFeature.bootstrap()` injects it, and a
    /// call cannot be placed without it.
    /// Readable from `VoipManager+ScreenShare`, which lives in another file.
    private(set) var signaling: CallSignalingRepositoryProtocol?
    private var inboundEventTask: Task<Void, Never>?
    private var outgoingOfferTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var ringTimeoutTask: Task<Void, Never>?

    /// Carries the actual audio and video. Injected by the app target, which is
    /// the only place that knows CallMediaKit — signaling still works without it,
    /// but nothing is heard or seen.
    private(set) var mediaEngine: (any CallMediaEngineProtocol)?
    private var mediaEventTask: Task<Void, Never>?
    /// Ensures hangup actually finishes engine teardown (mic/camera release).
    private var mediaStopTask: Task<Void, Never>?

    /// Needed before the first call, not at bootstrap: iOS only prompts on first
    /// use, and asking for the microphone during sign-in would be unexplained.
    /// Injected by `ChatFeature.bootstrap()`; nil means the prompt is skipped and
    /// the OS denies capture silently.
    var permissionService: (any PermissionServiceProtocol)?
    /// Guards against running the SFU handshake twice: the initiator gets
    /// `CALL_OFFER_MEDIA` and the joiner `CALL_MEDIA_ANSWER`, but a reconnect can
    /// deliver either again.
    private var isMediaRunning = false

    /// CallKit has handed us a live audio session (`didActivate`).
    ///
    /// Outgoing used to skip CallKit entirely, so WebRTC stayed on manual audio
    /// with `isAudioEnabled == false` and the caller never produced real mic RTP
    /// even though `call-produce` could still fire. Media start waits for this
    /// (with a short fallback) so produce runs with a working capture unit.
    private var isCallKitAudioActivated = false

    /// SFU setup that arrived before CallKit activated audio — flushed from
    /// `onAudioSessionActivated`.
    private var pendingMediaSetupEvent: InboundCallEventDTO?

    /// `CALL_NEW_PRODUCER` events received before media is ready to consume.
    private var pendingRemoteProducers: [InboundCallEventDTO] = []
    private var consumeRetryCounts: [String: Int] = [:]
    /// Producer owner from `CALL_NEW_PRODUCER.peerId` — not `CALL_CONSUMER_CREATED.peerId`
    /// (that names the consuming peer / us).
    private var producerOwnerByProducerId: [String: String] = [:]
    private static let maxConsumeRetries = 3

    /// Remote producers announced for the active call (excluding self).
    private var remoteAudioProducerIds: Set<String> = []
    private var remoteVideoProducerIds: Set<String> = []
    private var consumedRemoteAudioProducerIds: Set<String> = []
    private var consumedRemoteVideoProducerIds: Set<String> = []
    /// Prefer audio consumes before video when both are queued.
    private var consumeQueue: [InboundCallEventDTO] = []
    private var isConsumeLoopRunning = false
    private var producerSettleTask: Task<Void, Never>?
    private var connectMediaTimeoutTask: Task<Void, Never>?
    private var producerSettleExpired = false
    private var connectMediaTimedOut = false
    /// Wait for a late video/audio producer after the first kind arrives.
    private static let producerSettleDuration: Duration = .milliseconds(900)
    /// Hard cap so Connecting never sticks if a consume hangs.
    private static let connectMediaTimeout: Duration = .seconds(5)

    /// Whether the callee is known to be ringing. Separate from `callPhase`
    /// because several events can signal it and only the first should count.
    private var isCalleeRinging = false

    /// One retry per call, for a join that lost a race with a reject.
    private var hasRetriedJoin = false

    /// The id the *server* knows this call by.
    ///
    /// Distinct from `roomId`: the contract carries both, and §9.1 annotates the
    /// field as "uuid-call-or-room", so they are not guaranteed equal. Records
    /// written under a client-invented id can never be reconciled with anything
    /// read back from the server, which is why this is preferred wherever it is
    /// known.
    private var serverCallId: String?

    /// Whether the far end put the call on hold.
    @Published var isRemoteOnHold = false

    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    /// §6: three tries, then give up.
    private static let maxReconnectAttempts = 3
    /// Far longer than the 10s heartbeat — this only proves the session, while
    /// the heartbeat is what keeps the peer in the room.
    private static let pingInterval: Duration = .seconds(15)

    /// Whether the server has actually created the SFU room.
    ///
    /// Announced by `CALL_OFFER_MEDIA` / `CALL_MEDIA_ANSWER`. Anything addressed
    /// to the room before this — inviting people, in particular — is published
    /// into nowhere. Deliberately not the same as `callPhase.isActive`, which is
    /// already true while the offer is still in flight.
    private var isRoomEstablished = false

    /// People to pull in as soon as the room exists.
    ///
    /// A group call starts as an ordinary call to the first participant; the
    /// rest can only be invited once the server has actually created the room,
    /// which is what `CALL_OFFER_MEDIA` announces.
    private var pendingInvitees: [CallInvitee] = []

    /// Fallback deadline when the server does not state one.
    ///
    /// The contract's own timeout is 45s (`ringingTimeoutMs`), and the client
    /// deliberately waits a little longer so the server's `CALL_MISSED` wins the
    /// race and both sides agree on the outcome. This only applies when no
    /// timeout was advertised.
    private static let ringTimeout: Duration = .seconds(50)

    /// Grace added to the server's advertised timeout, for the same reason.
    private static let ringTimeoutGrace: Duration = .seconds(5)

    /// Deadline announced by `CALL_INITIATED.ringingTimeoutMs`, when present.
    private var serverRingTimeout: Duration?

    /// Room the current call belongs to. The contract uses a client-generated id
    /// that doubles as the idempotency key, so it is the call UUID.
    ///
    /// Lowercase, like every id this app emits — the call log persists the same
    /// UUID as `callId`, and an uppercase room id would never correlate with it.
    var roomId: String? { activeCallUUID?.lowercasedString }
    var discussionsUseCases: DiscussionUseCasesProtocol?
    /// Resolves local conversation ids to linked server ids for `call-offer`.
    /// Injected by `ChatFeature.bootstrap()` alongside the use cases.
    var discussionRepository: DiscussionRepositoryProtocol?
    /// Injected by `ChatFeature.bootstrap()`. Every finished call is written
    /// through this — without it the Calls tab stays empty.
    var callUseCases: CallUseCasesProtocol?
    /// Injected by `ChatFeature.bootstrap()`. Supplies the saved name for a peer
    /// so a tile reads "Ada" rather than the uuid the SFU knows them by.
    var contactUseCases: ContactsUseCasesProtocol?

    /// Saved contact names, indexed under every id that peer is known by.
    ///
    /// Published because it arrives after the first render: the call screen must
    /// come up immediately, so tiles start on whatever the wire supplied and
    /// upgrade to the saved name once this lands.
    @Published private(set) var contactNamesByPeerKey: [String: String] = [:]
    private var contactNameTask: Task<Void, Never>?

    /// Loads the local address book once per call and indexes it by peer key.
    ///
    /// Persisted contacts only — never the network fetch. A call must not wait
    /// on a sync, and the saved copy is what the user recognises anyway.
    ///
    /// Deliberately not `@MainActor`: it is called from the call-setup paths,
    /// which are not isolated, and it publishes its result on the main actor
    /// itself rather than forcing every caller to hop first.
    func loadContactNames() {
        // Refreshed per call rather than cached for the run — the address book
        // can change between calls. Any names already loaded stay on screen
        // while the new read is in flight.
        guard contactNameTask == nil, let contactUseCases else { return }

        contactNameTask = Task { [weak self] in
            let contacts = try? await contactUseCases.getPersistedContacts.execute()
            guard let self, let contacts, !Task.isCancelled else { return }

            let index = Self.contactNameIndex(from: contacts.waanguContacts)
            await MainActor.run {
                self.contactNamesByPeerKey = index
                self.contactNameTask = nil
            }
        }
    }

    /// Indexes each contact's display name under both ids they may appear as.
    ///
    /// `contactName` is what the user themselves saved, so it wins over the
    /// profile `name` the server supplies. Entries that would only map an id to
    /// itself are skipped — they are not names, and storing them would make the
    /// lookup answer with a uuid.
    static func contactNameIndex(from contacts: [WaanguContact]) -> [String: String] {
        var index: [String: String] = [:]
        for contact in contacts {
            let saved = contact.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = saved.isEmpty ? profile : saved
            guard !name.isEmpty else { continue }

            let nameKey = normalizedPeerKey(name)
            for identifier in [contact.userId, contact.phone] {
                let key = normalizedPeerKey(identifier)
                guard !key.isEmpty, key != nameKey else { continue }
                index[key] = name
            }
        }
        return index
    }

    /// The saved name for a peer, if we have one.
    func contactName(forPeerId peerId: String) -> String? {
        let key = participantKey(peerId)
        guard !key.isEmpty else { return nil }
        return contactNamesByPeerKey[key]
    }

    // MARK: - Who is speaking

    /// How loudly each peer is speaking, `0…1`, keyed by participant key.
    /// This device is under `Self.localAudioLevelKey`.
    @Published private(set) var audioLevelsByPeerKey: [String: Float] = [:]

    /// The key this device's own level is filed under. Not a peer id: the local
    /// microphone has no consumer, and the account id is not always known.
    static let localAudioLevelKey = "local"

    private var audioLevelTask: Task<Void, Never>?

    /// How often levels are sampled.
    ///
    /// The SFU client offers no callback for this, so it has to be polled, and
    /// each sample is a blocking `GetStats()` per open consumer. 8 Hz is fast
    /// enough to look continuous next to a 30 fps waveform while keeping that
    /// cost off the signalling thread most of the time.
    private static let audioLevelSampleInterval = Duration.milliseconds(125)

    /// Starts sampling speech levels for the life of the call.
    func startAudioLevelPolling() {
        guard audioLevelTask == nil else { return }

        audioLevelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let engine = await self.mediaEngineSnapshot() else { return }

                let byConsumer = await engine.remoteAudioLevels()
                let local = await engine.localAudioLevel()

                await MainActor.run {
                    self.applyAudioLevels(byConsumer: byConsumer, local: local)
                }

                try? await Task.sleep(for: Self.audioLevelSampleInterval)
            }
        }
    }

    func stopAudioLevelPolling() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
        audioLevelsByPeerKey = [:]
    }

    // MARK: - Who has dropped out

    /// Peers whose media has stopped arriving, by participant key.
    ///
    /// The union of two independent sources, because neither alone is enough:
    /// the server's `CALL_RECONNECTING` knows about outages we cannot see, but a
    /// peer that loses the network entirely stops talking to the server too, and
    /// then local byte counters are the only evidence there is.
    @Published private(set) var stalledPeerKeys: Set<String> = []

    /// Local evidence — consumer byte counters have stopped advancing.
    private var statsStalledPeerKeys: Set<String> = []
    /// The server's evidence — `CALL_RECONNECTING` named this peer.
    private var serverReconnectingPeerKeys: Set<String> = []

    private var stallTask: Task<Void, Never>?
    private var stallDetector = CallStallDetector()

    /// Sampled far slower than audio levels: this answers "has media stopped",
    /// which resolves over seconds, and every sample costs a `GetStats()` per
    /// open consumer.
    private static let stallSampleInterval = Duration.seconds(1)

    /// Starts watching for peers whose media stops arriving.
    func startStallPolling() {
        guard stallTask == nil else { return }

        stallTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.stallSampleInterval)
                guard !Task.isCancelled else { return }
                guard let self, let engine = await self.mediaEngineSnapshot() else { return }

                let bytes = await engine.remoteInboundBytes()

                await MainActor.run {
                    self.applyInboundBytes(bytes)
                }
            }
        }
    }

    func stopStallPolling() {
        stallTask?.cancel()
        stallTask = nil
        stallDetector.reset()
        statsStalledPeerKeys = []
        serverReconnectingPeerKeys = []
        stalledPeerKeys = []
    }

    /// Turns one sample of consumer byte counters into the set of stalled peers.
    @MainActor
    private func applyInboundBytes(_ bytes: [String: UInt64]) {
        let stalledConsumers = stallDetector.update(bytes: bytes, now: Date())
        let stalledOwners = CallStallDetector.stalledOwnerKeys(
            stalledConsumers: stalledConsumers,
            consumerOwners: consumerOwners
        )

        statsStalledPeerKeys = expandedIdentityKeys(for: stalledOwners)

        // Media flowing again is proof a peer the server flagged is back. The
        // server sends no "recovered" event, so without this their tile would
        // keep saying "Reconnecting…" for the rest of the call.
        let liveOwners = Set(consumerOwners.values).subtracting(stalledOwners)
        serverReconnectingPeerKeys.subtract(expandedIdentityKeys(for: liveOwners))

        refreshStalledPeers()
    }

    /// Every alias each peer is known by.
    ///
    /// A tile keyed on phone and a track keyed on userId have to agree about who
    /// has dropped out — the same reason mute and camera state are looked up
    /// through `identityKeys`.
    @MainActor
    private func expandedIdentityKeys(for ownerKeys: Set<String>) -> Set<String> {
        var expanded: Set<String> = []
        for key in ownerKeys {
            expanded.formUnion(identityKeys(forPeerId: key))
        }
        return expanded
    }

    @MainActor
    private func refreshStalledPeers() {
        let union = statsStalledPeerKeys.union(serverReconnectingPeerKeys)
        guard union != stalledPeerKeys else { return }
        stalledPeerKeys = union
    }

    /// The server told us this peer is rebuilding their transports.
    @MainActor
    private func markPeerReconnecting(_ peerId: String) {
        serverReconnectingPeerKeys.formUnion(identityKeys(forPeerId: peerId))
        refreshStalledPeers()
    }

    /// Someone who left is gone, not reconnecting — drop any flag they carried
    /// so it cannot outlive them on a tile that gets reused.
    @MainActor
    private func clearReconnectingFlags(for keys: Set<String>) {
        guard !keys.isEmpty else { return }
        statsStalledPeerKeys.subtract(keys)
        serverReconnectingPeerKeys.subtract(keys)
        refreshStalledPeers()
    }

    /// Whether this peer's media has stopped arriving.
    func isPeerReconnecting(_ participant: CallInvitee) -> Bool {
        stalledPeerKeys.contains(participantKey(participant.userId))
            || stalledPeerKeys.contains(participantKey(participant.phone))
    }

    @MainActor
    private func mediaEngineSnapshot() -> (any CallMediaEngineProtocol)? {
        isMediaRunning ? mediaEngine : nil
    }

    /// Re-files per-consumer levels onto the peers that own them.
    ///
    /// A peer can have more than one audio consumer, so the loudest wins rather
    /// than whichever happened to be enumerated last.
    @MainActor
    private func applyAudioLevels(byConsumer: [String: Float], local: Float?) {
        var levels: [String: Float] = [:]
        for (consumerId, level) in byConsumer {
            guard let owner = consumerOwners[consumerId] else { continue }
            for alias in identityKeys(forPeerId: owner) {
                levels[alias] = max(levels[alias] ?? 0, level)
            }
        }
        if let local {
            levels[Self.localAudioLevelKey] = local
        }
        audioLevelsByPeerKey = levels
    }

    /// This peer's current speech level, `0…1`.
    func audioLevel(for participant: CallInvitee) -> Float {
        audioLevelsByPeerKey[participantKey(participant.userId)]
            ?? audioLevelsByPeerKey[participantKey(participant.phone)]
            ?? 0
    }

    /// Above the floor where a level means speech rather than room noise.
    ///
    /// WebRTC reports a small non-zero level almost continuously on an open
    /// microphone, so a plain `> 0` would light every tile permanently.
    static let speakingThreshold: Float = 0.02

    func isPeerSpeaking(_ participant: CallInvitee) -> Bool {
        audioLevel(for: participant) > Self.speakingThreshold
    }

    private var callStartTime: Date?
    /// Wall-clock start of the connected phase — duration is derived from this
    /// rather than a free-running `+= 1` counter that drifts when multiple
    /// timers are accidentally scheduled.
    private var callConnectedAt: Date?
    private var callWasAnswered: Bool = false
    /// Guards against double `call-join` when in-app accept and CallKit
    /// `onAnswered` both fire for the same answer.
    private var isAnswerJoinInFlight: Bool = false
    private var callHistoryPersisted: Bool = false
    /// Set once we publish reject/disconnect, or once a server end event has
    /// already told both sides the call is over. Stops CallKit's `onEnded`
    /// from emitting a second hangup after `endCall` / `finishCall`.
    private var hasNotifiedServerOfEnd: Bool = false
    
    var formattedDuration: String {
        let minutes = callDuration / 60
        let secs = callDuration % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    private init() {
        callKit.delegate = self
        initializePushKit()
    }
    
    // MARK: - Signaling wiring

    /// Connects the call manager to the signaling transport and starts listening
    /// for inbound call events.
    /// - Parameter deviceId: this device's id, supplied up front rather than
    ///   fetched afterwards. Multi-device events are decided synchronously, and
    ///   an id that arrives late means the first `CALL_DEVICE_TRANSFERRED` is
    ///   judged against nothing — which is how the answering device used to hang
    ///   up on itself.
    func configureSignaling(
        _ repository: CallSignalingRepositoryProtocol,
        deviceId: String
    ) {
        signaling = repository
        thisDeviceId = deviceId
        startObservingCallEvents()
    }

    /// This device's id, as sent on every `call-offer` / `call-join`.
    private var thisDeviceId: String?

    /// Listens for call events, and keeps listening.
    ///
    /// The inbox subscription is bound to the signed-in user, so it has to be
    /// rebuilt after login, after logout, and whenever the transport drops it.
    /// Attaching once at start-up is how every call event went missing and every
    /// outgoing call sat on "Calling…" until the ring timeout.
    private func startObservingCallEvents() {
        inboundEventTask?.cancel()
        inboundEventTask = Task { [weak self] in
            guard let self, let signaling = self.signaling else { return }

            while !Task.isCancelled {
                await signaling.ensureInboundPump()

                do {
                    // Nil means there is no session yet — ordinary on a
                    // signed-out app, so it simply retries.
                    if let stream = try await signaling.observeCallEvents() {
                        for await event in stream {
                            guard !Task.isCancelled else { return }
                            await MainActor.run { self.handle(event) }
                        }
                    }
                } catch {
                    #if DEBUG
                    print("Call event stream unavailable: \(error)")
                    #endif
                }

                guard !Task.isCancelled else { return }
                // No session yet, or the transport dropped the stream. Wait
                // before retrying so a signed-out app does not spin.
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Ends any call and tells the server this user is gone.
    ///
    /// Called on sign-out: without it the server keeps the user listed in a room
    /// they can no longer be reached on, and the next sign-in is met with
    /// `CALL_BUSY (already_in_call)`.
    func handleSignOut() {
        Task { @MainActor in
            self.cancelInFlightCallWork()
            if self.callPhase.isActive {
                self.endCall()
            } else if self.activeCallUUID != nil {
                self.notifyServerOfLocalEndIfNeeded()
                self.callPhase = .idle
                self.resetCallState()
            }
        }
        Task { [weak self] in
            try? await self?.signaling?.sendUserDisconnect()
        }
    }

    /// Stops background offer/heartbeat work so a late `call-offer` cannot
    /// re-register this user on the server after local hang-up.
    @MainActor
    private func cancelInFlightCallWork() {
        outgoingOfferTask?.cancel()
        outgoingOfferTask = nil
        localPreviewTask?.cancel()
        localPreviewTask = nil
        producerSettleTask?.cancel()
        producerSettleTask = nil
        connectMediaTimeoutTask?.cancel()
        connectMediaTimeoutTask = nil
        stopHeartbeat()
        stopPing()
        stopReconnect()
    }

    @MainActor
    private func clearRemoteProducerGateState() {
        remoteAudioProducerIds.removeAll()
        remoteVideoProducerIds.removeAll()
        consumedRemoteAudioProducerIds.removeAll()
        consumedRemoteVideoProducerIds.removeAll()
        consumeQueue.removeAll()
        isConsumeLoopRunning = false
        producerSettleTask?.cancel()
        producerSettleTask = nil
        connectMediaTimeoutTask?.cancel()
        connectMediaTimeoutTask = nil
        producerSettleExpired = false
        connectMediaTimedOut = false
    }

    /// If `call-offer` lands after the user already hung up, publish disconnect
    /// again so the server does not keep this device marked in-call.
    @MainActor
    private func undoServerRegistrationIfCallEnded(roomId: String) {
        guard !callPhase.isActive else { return }
        hasNotifiedServerOfEnd = false
        notifyServerOfLocalEndIfNeeded()
        #if DEBUG
        print("[CallMedia] call-offer completed after hang-up — sending disconnect for room=\(roomId)")
        #endif
    }

    /// Rebuilds the call inbox subscription against the current session.
    ///
    /// Called when the app learns the session changed. Without it a pump started
    /// before login stays subscribed to the wrong topic for the whole run.
    func refreshSignalingSubscription() {
        Task { [weak self] in
            guard let signaling = self?.signaling else { return }
            await signaling.detachInboundPump()
            await signaling.ensureInboundPump()
        }
    }

    // MARK: - Media wiring

    /// Connects the call manager to the media engine. Without it the call still
    /// signals correctly but carries no audio or video.
    func configureMedia(_ engine: any CallMediaEngineProtocol) {
        mediaEngine = engine
        observeMediaEvents(of: engine)
    }

    private func observeMediaEvents(of engine: any CallMediaEngineProtocol) {
        mediaEventTask?.cancel()
        mediaEventTask = Task { [weak self] in
            for await event in engine.events {
                guard !Task.isCancelled else { return }
                await self?.handleMediaEvent(event, from: engine)
            }
        }
    }

    /// A remote camera or screen share arriving means there is finally something
    /// to look at, so the call adopts the video layout.
    ///
    /// Deliberately does not touch `hasVideo`: receiving video is not consent to
    /// send it. The local camera stays off until the user turns it on, which is
    /// what separates `isVideoCall` (the layout) from `hasVideo` (our camera).
    @MainActor
    private func adoptVideoLayoutForRemoteVideo() {
        guard !isVideoCall else { return }
        isVideoCall = true
        // Loudspeaker follows the *layout*, not our camera. Someone watching a
        // remote camera or a shared screen is holding the phone away from their
        // ear, so the earpiece is the wrong output even though they never turned
        // their own camera on. `toggleVideo` already does this for the case
        // where we are the one enabling video.
        applyLoudspeakerPolicy(enabled: true)
        if case .connected = callPhase {
            callPhase = .connected(isVideo: true)
        }
    }

    @MainActor
    private func handleMediaEvent(
        _ event: CallMediaEvent,
        from engine: any CallMediaEngineProtocol
    ) async {
        switch event {
        case .remoteVideoTrackAdded(let peerId, let consumerId):
            let track = await engine.videoTrack(forConsumer: consumerId)
            remoteVideoTracks[consumerId] = track
            // `CALL_CONSUMER_CREATED.peerId` is the consuming peer (us). Prefer the
            // producer owner recorded from `CALL_NEW_PRODUCER`.
            let ownerKey = consumerOwners[consumerId]
                ?? remoteProducerOwnerKey(for: peerId)
            if let track, let ownerKey {
                assignVideoTrack(track, toOwnerKey: ownerKey, consumerId: consumerId)
                adoptVideoLayoutForRemoteVideo()
            }
            evaluateConnectGate()

        case .remoteVideoTrackRemoved(let consumerId):
            // Only this consumer goes. The owner may still have another open —
            // a camera outliving a screen share — so the index is rebuilt from
            // what is left rather than cleared by key.
            remoteVideoTracks.removeValue(forKey: consumerId)
            consumerOwners.removeValue(forKey: consumerId)
            reindexVideoTracksForRoster()

        case .localVideoTrackChanged:
            localVideoTrack = await engine.localVideoTrack()
            stopFallbackCameraPreview()

        case .localVideoUnavailable:
            // Camera failed; stay on the video layout and show a placeholder.
            localVideoTrack = nil
            hasVideo = false
            state = "Camera unavailable"

        case .transportFailed:
            // Our own transport dropped. This used to only set the label and
            // wait for the server's `CALL_RECONNECTING` to start recovery — but
            // when the network is what failed, that event can never arrive, so
            // the call sat on "Reconnecting…" forever with nothing retrying and
            // nothing giving up. Drive the sequence from here instead; it is
            // idempotent, so the server event arriving too is harmless.
            guard callPhase.isActive else { return }
            callStatus = .reconnecting
            state = "Reconnecting…"
            beginReconnect()
        }
    }

    /// Asks for mic (and camera on video) without blocking on a first-time prompt
    /// when Chat already primed them. Safe to call again: decided statuses return
    /// immediately with no system sheet.
    private func requestCapturePermissions(video: Bool) async {
        guard let permissionService else { return }

        let microphone = await permissionService.request(.microphone)
        #if DEBUG
        if !microphone.isGranted {
            print("[CallMedia] microphone permission \(microphone.rawValue) — this call will send no audio")
        }
        #endif

        guard video else { return }
        let camera = await permissionService.request(.camera)
        #if DEBUG
        if !camera.isGranted {
            print("[CallMedia] camera permission \(camera.rawValue) — falling back to audio")
        }
        #endif
    }

    /// Runs the SFU handshake from `CALL_OFFER_MEDIA` (initiator) or
    /// `CALL_MEDIA_ANSWER` (joiner).
    @MainActor
    private func startMedia(with event: InboundCallEventDTO) {
        // Each of these used to return in silence, which made "the call has no
        // media" indistinguishable between a second setup event, a missing
        // engine, and a payload the mapper could not read.
        guard !isMediaRunning else {
            #if DEBUG
            print("[CallMedia] startMedia skipped — media already running (\(event.eventType))")
            #endif
            return
        }
        guard let engine = mediaEngine, let signaling, let room = roomId else {
            #if DEBUG
            print("[CallMedia] startMedia aborted — engine=\(mediaEngine != nil) signaling=\(signaling != nil) room=\(roomId ?? "nil")")
            #endif
            return
        }
        guard let setup = CallMediaMapper.setup(from: event) else {
            #if DEBUG
            print("[CallMedia] startMedia aborted — unreadable setup in \(event.eventType); payload keys: \(event.payload.keys.sorted())")
            #endif
            return
        }

        // Produce needs a live CallKit session. If setup beat `didActivate`,
        // hold it and flush when audio comes up (or after a short fallback).
        if !isCallKitAudioActivated {
            pendingMediaSetupEvent = event
            #if DEBUG
            print("[CallMedia] deferring startMedia (\(event.eventType)) until CallKit audio activates")
            #endif
            scheduleDeferredMediaStartFallback()
            return
        }

        pendingMediaSetupEvent = nil
        recvTransportId = setup.recvTransport.id
        let wantsVideo = hasVideo
        let bridge = CallMediaSignalingBridge(roomId: room, signaling: signaling)
        let uuid = activeCallUUID
        let playRingbackAfterProduce = !isIncoming

        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.start(setup: setup, isVideo: wantsVideo, signaling: bridge)
                // Honour mute chosen while ringing — otherwise produce starts
                // unmuted and the preference flipped before media is lost.
                let muted = await MainActor.run { self.isMuted }
                if muted {
                    await engine.setMicrophoneEnabled(false)
                    try? await signaling.sendMute(roomId: room, isMuted: true)
                }
                let localTrack = await engine.localVideoTrack()
                await MainActor.run {
                    guard self.activeCallUUID == uuid else { return }
                    self.isMediaRunning = true
                    self.localVideoTrack = localTrack
                    self.startAudioLevelPolling()
                    self.startStallPolling()
                    self.stopFallbackCameraPreview()
                    // After produce so AVAudioEngine does not steal the session.
                    if playRingbackAfterProduce, !self.callWasAnswered {
                        self.startRingbackTone()
                    }
                    // Callee: peer "answer" is our accept — wait for remote
                    // producers before Connected / timer (video gate).
                    if self.isIncoming {
                        self.notePeerAnswered()
                    }
                    self.flushPendingRemoteProducers()
                    // Re-assert loudspeaker / proximity after media is live.
                    if self.requiresLoudspeakerPolicy {
                        self.applyLoudspeakerPolicy(enabled: true)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.activeCallUUID == uuid else { return }
                    self.isMediaRunning = false
                    if self.isIncoming, !self.callWasAnswered {
                        self.failCall(reason: "No audio — media failed to start")
                    } else {
                        self.state = "No audio — media failed to start"
                    }
                }
                #if DEBUG
                print("Media engine failed to start: \(error)")
                #endif
            }
        }
    }

    /// If CallKit never activates (some Simulator paths), still attempt media
    /// so the offer side is not stuck forever with a pending setup.
    @MainActor
    private func scheduleDeferredMediaStartFallback() {
        let uuid = activeCallUUID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                guard let self else { return }
                guard self.activeCallUUID == uuid else { return }
                guard let pending = self.pendingMediaSetupEvent else { return }
                guard !self.isMediaRunning else { return }
                #if DEBUG
                print("[CallMedia] CallKit audio still inactive — starting media with forced session enable")
                #endif
                self.isCallKitAudioActivated = true
                Task { [weak self] in
                    await self?.mediaEngine?.setAudioSessionActivated(true)
                    await MainActor.run {
                        guard let self, self.activeCallUUID == uuid else { return }
                        guard let stillPending = self.pendingMediaSetupEvent else { return }
                        self.startMedia(with: stillPending)
                    }
                }
            }
        }
    }

    /// Subscribes to a remote track announced by `CALL_NEW_PRODUCER`.
    @MainActor
    private func consumeRemoteProducer(_ event: InboundCallEventDTO) {
        guard let producerId = event.producerId else { return }
        // Never consume our own produce (uid or phone as peerId).
        if isSelfPeerId(event.peerId) { return }

        if let peerId = event.peerId {
            producerOwnerByProducerId[producerId] = peerId
            // Late joiner: existing peers never send us CALL_PEER_JOINED — put
            // them on the grid as soon as their producer is announced.
            let username = event.user?.username
            upsertRemotePeer(
                userId: peerId,
                name: (username?.isEmpty == false) ? username : nil,
                phone: event.user?.phone,
                markJoined: true
            )
            reindexVideoTracksForRoster()
        }
        recordRemoteProducer(event)

        guard isMediaRunning, mediaEngine != nil, signaling != nil else {
            enqueuePendingRemoteProducer(event)
            #if DEBUG
            print("[CallMedia] queued producer \(producerId) — mediaRunning=\(isMediaRunning)")
            #endif
            return
        }

        if event.isScreenShare, let peerId = event.peerId {
            screenSharingPeerId = peerId
        }

        enqueueConsume(event)
    }

    @MainActor
    private func recordRemoteProducer(_ event: InboundCallEventDTO) {
        guard let producerId = event.producerId else { return }
        switch Self.remoteProducerKind(for: event) {
        case .audio:
            remoteAudioProducerIds.insert(producerId)
        case .video:
            remoteVideoProducerIds.insert(producerId)
        }
        armProducerSettleIfNeeded()
        evaluateConnectGate()
    }

    private enum RemoteProducerKind {
        case audio
        case video
    }

    private static func remoteProducerKind(for event: InboundCallEventDTO) -> RemoteProducerKind {
        let raw = (event.mediaType ?? event.mediaKind ?? "").lowercased()
        if raw == "video" || raw == "screen" { return .video }
        return .audio
    }

    @MainActor
    private func enqueueConsume(_ event: InboundCallEventDTO) {
        guard let producerId = event.producerId else { return }
        if consumeQueue.contains(where: { $0.producerId == producerId }) { return }
        // Already consumed successfully — ignore duplicates.
        if consumedRemoteAudioProducerIds.contains(producerId)
            || consumedRemoteVideoProducerIds.contains(producerId) {
            return
        }

        switch Self.remoteProducerKind(for: event) {
        case .audio:
            if let firstVideo = consumeQueue.firstIndex(where: {
                Self.remoteProducerKind(for: $0) == .video
            }) {
                consumeQueue.insert(event, at: firstVideo)
            } else {
                consumeQueue.append(event)
            }
        case .video:
            consumeQueue.append(event)
        }
        kickConsumeLoop()
    }

    @MainActor
    private func kickConsumeLoop() {
        guard !isConsumeLoopRunning else { return }
        guard isMediaRunning, mediaEngine != nil, signaling != nil else { return }
        isConsumeLoopRunning = true

        Task { [weak self] in
            while let event = await self?.nextQueuedConsumeEvent() {
                guard let self else { return }
                await self.performConsume(event)
                await MainActor.run { self.evaluateConnectGate() }
            }
            await MainActor.run {
                guard let self else { return }
                self.isConsumeLoopRunning = false
                if !self.consumeQueue.isEmpty {
                    self.kickConsumeLoop()
                }
            }
        }
    }

    @MainActor
    private func nextQueuedConsumeEvent() -> InboundCallEventDTO? {
        guard !consumeQueue.isEmpty else { return nil }
        return consumeQueue.removeFirst()
    }

    @MainActor
    private func performConsume(_ event: InboundCallEventDTO) async {
        guard let producerId = event.producerId else { return }
        guard let engine = mediaEngine, let signaling else { return }

        let transportId = event.transportId
        let room = roomIdSnapshot()
        let kind = Self.remoteProducerKind(for: event)

        do {
            let capabilities = try await engine.rtpCapabilities()
            let parameters = try await signaling.sendConsume(
                roomId: room,
                transportId: transportId ?? recvTransportId ?? "",
                producerId: producerId,
                rtpCapabilities: capabilities
            )
            // Recorded for every consumer, audio included, and before
            // `receive` so the video-added event already finds it. Audio used to
            // be staged in a separate map that only the video path ever read, so
            // an audio consumer never got an owner at all — and its speech level
            // had nothing to attribute itself to.
            if let remotePeerId = event.peerId {
                await MainActor.run {
                    self.consumerOwners[parameters.consumerId] =
                        self.participantKey(remotePeerId)
                }
            }
            try await engine.receive(consumer: parameters)
            await MainActor.run {
                self.consumeRetryCounts.removeValue(forKey: producerId)
                switch kind {
                case .audio:
                    self.consumedRemoteAudioProducerIds.insert(producerId)
                case .video:
                    self.consumedRemoteVideoProducerIds.insert(producerId)
                }
            }
            #if DEBUG
            print("[CallMedia] Consumed remote \(kind == .audio ? "audio" : "video") producer=\(producerId) peer=\(event.peerId ?? "?") consumer=\(parameters.consumerId)")
            #endif
        } catch {
            #if DEBUG
            print("[CallMedia] Could not consume producer \(producerId): \(error)")
            #endif
            await scheduleConsumeRetry(for: event)
        }
    }

    @MainActor
    private func scheduleConsumeRetry(for event: InboundCallEventDTO) async {
        guard let producerId = event.producerId else { return }
        guard callPhase.isActive, isMediaRunning else { return }

        let attempt = consumeRetryCounts[producerId, default: 0] + 1
        guard attempt <= Self.maxConsumeRetries else {
            enqueuePendingRemoteProducer(event)
            flushPendingRemoteProducers()
            return
        }
        consumeRetryCounts[producerId] = attempt

        let delayMs = UInt64(400 * attempt)
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)

        await MainActor.run {
            guard self.callPhase.isActive, self.isMediaRunning else { return }
            self.enqueueConsume(event)
        }
    }

    @MainActor
    private func enqueuePendingRemoteProducer(_ event: InboundCallEventDTO) {
        guard let producerId = event.producerId else { return }
        if isSelfPeerId(event.peerId) { return }
        if pendingRemoteProducers.contains(where: { $0.producerId == producerId }) { return }
        pendingRemoteProducers.append(event)
    }

    @MainActor
    private func flushPendingRemoteProducers() {
        guard isMediaRunning else { return }
        let queued = pendingRemoteProducers
        pendingRemoteProducers.removeAll()
        // Audio before video so voice is live before we wait on camera.
        let sorted = queued.sorted { lhs, rhs in
            let l = Self.remoteProducerKind(for: lhs) == .audio ? 0 : 1
            let r = Self.remoteProducerKind(for: rhs) == .audio ? 0 : 1
            return l < r
        }
        for event in sorted {
            enqueueConsume(event)
        }
        evaluateConnectGate()
    }

    @MainActor
    private func armProducerSettleIfNeeded() {
        guard producerSettleTask == nil, !producerSettleExpired else { return }
        let uuid = activeCallUUID
        producerSettleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.producerSettleDuration)
            await MainActor.run {
                guard let self, self.activeCallUUID == uuid else { return }
                self.producerSettleExpired = true
                self.producerSettleTask = nil
                self.evaluateConnectGate()
            }
        }
    }

    @MainActor
    private func scheduleConnectMediaTimeout() {
        connectMediaTimeoutTask?.cancel()
        connectMediaTimedOut = false
        let uuid = activeCallUUID
        connectMediaTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.connectMediaTimeout)
            await MainActor.run {
                guard let self, self.activeCallUUID == uuid else { return }
                self.connectMediaTimedOut = true
                self.connectMediaTimeoutTask = nil
                #if DEBUG
                print("[CallMedia] connect media timeout — promoting with available producers")
                #endif
                self.evaluateConnectGate()
            }
        }
    }

    /// Peer answered / we accepted: stop ringing, stay Connecting until the
    /// remote producer gate (or timeout) promotes to Connected + timer.
    @MainActor
    private func notePeerAnswered() {
        if !callWasAnswered {
            stopAllTones()
            stopRingTimeout()
            callWasAnswered = true
            if callStartTime == nil { callStartTime = Date() }
            switch callPhase {
            case .connected:
                break
            default:
                callPhase = .connecting
                callStatus = .connecting
                state = "Connecting…"
            }
            scheduleConnectMediaTimeout()
        }
        // 1:1 answer path may skip a named `CALL_PEER_JOINED` user — the sole
        // remote is in the room once answered.
        if remoteParticipants.count == 1, let only = remoteParticipants.first {
            markPeerJoined(only)
        }
        evaluateConnectGate()
    }

    /// Leaves Connecting for Connected and starts the duration timer.
    @MainActor
    private func promoteToConnected() {
        guard callWasAnswered else { return }
        if case .connected = callPhase { return }

        connectMediaTimeoutTask?.cancel()
        connectMediaTimeoutTask = nil
        producerSettleTask?.cancel()
        producerSettleTask = nil

        callPhase = .connected(isVideo: isVideoCall)
        callStatus = .connected
        state = "Call answered"
        startCallTimer()
        if let uuid = activeCallUUID, !isIncoming {
            callKit.reportOutgoingCallConnected(uuid: uuid)
        }
        #if DEBUG
        print("[CallMedia] promoted to connected audioProducers=\(remoteAudioProducerIds.count) videoProducers=\(remoteVideoProducerIds.count) consumedA=\(consumedRemoteAudioProducerIds.count) consumedV=\(consumedRemoteVideoProducerIds.count)")
        #endif
    }

    /// Video call: wait for every announced kind; missing kind after settle =
    /// peer muted that track — connect with what we consumed. Both kinds →
    /// wait until both ready (or hard timeout).
    @MainActor
    private func evaluateConnectGate() {
        guard callWasAnswered else { return }
        if case .connected = callPhase { return }

        if mediaEngine == nil {
            promoteToConnected()
            return
        }
        guard isMediaRunning else { return }

        let hasAudio = !remoteAudioProducerIds.isEmpty
        let hasVideo = !remoteVideoProducerIds.isEmpty
        let audioReady = hasAudio
            && remoteAudioProducerIds.isSubset(of: consumedRemoteAudioProducerIds)
        let videoReady = hasVideo
            && remoteVideoProducerIds.isSubset(of: consumedRemoteVideoProducerIds)

        if !isVideoCall {
            if audioReady || connectMediaTimedOut || (producerSettleExpired && !hasAudio) {
                promoteToConnected()
            }
            return
        }

        if hasAudio && hasVideo {
            if (audioReady && videoReady) || connectMediaTimedOut {
                promoteToConnected()
            }
            return
        }

        if hasAudio, !hasVideo {
            // Video muted / never published — accept after settle.
            if audioReady && (producerSettleExpired || connectMediaTimedOut) {
                promoteToConnected()
            }
            return
        }

        if hasVideo, !hasAudio {
            // Mic muted / never published — accept after settle.
            if videoReady && (producerSettleExpired || connectMediaTimedOut) {
                promoteToConnected()
            }
            return
        }

        // No remote producers yet.
        if connectMediaTimedOut {
            promoteToConnected()
        }
    }

    /// Receive transport handed to us at setup, needed by `call-consume`.
    private var recvTransportId: String?

    private func roomIdSnapshot() -> String {
        roomId ?? ""
    }

    @MainActor
    private func stopMedia() {
        pendingRemoteProducers.removeAll()
        consumeRetryCounts.removeAll()
        producerOwnerByProducerId.removeAll()
        clearRemoteProducerGateState()
        pendingMediaSetupEvent = nil
        isMediaRunning = false
        stopAudioLevelPolling()
        stopStallPolling()
        isCallKitAudioActivated = false
        localVideoTrack = nil
        remoteVideoTracks.removeAll()
        videoTracksByPeer.removeAll()
        consumerOwners.removeAll()
        recvTransportId = nil
        clearProximityMonitoring()
        // Drop AVFoundation fallback immediately (sync) — WebRTC capture follows
        // in the engine stop below.
        stopAllLocalVideoPreview()

        guard let engine = mediaEngine else { return }

        // Do not cancel an in-flight stop: we need mic/camera hardware released.
        // Starting a second stop is fine — engine.stop() is idempotent enough.
        mediaStopTask = Task { [weak self] in
            // Mute + deactivate the audio unit first so the privacy indicator
            // clears even if full SFU teardown takes a moment.
            await engine.setMicrophoneEnabled(false)
            await engine.setAudioSessionActivated(false)
            await engine.stop()
            await MainActor.run {
                self?.isCallKitAudioActivated = false
            }
        }
    }

    // MARK: - Recovery

    /// Rebuilds the media path after a network drop (§6).
    ///
    /// Three attempts, backing off 1s × attempt, then the call is given up on.
    /// Retrying forever would hold the user on a call that is already gone.
    @MainActor
    private func beginReconnect() {
        guard reconnectTask == nil, callPhase.isActive else { return }
        guard let uuid = activeCallUUID, let room = roomId else { return }

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            for attempt in 1...Self.maxReconnectAttempts {
                try? await Task.sleep(for: .seconds(attempt))

                let stillOurs = await MainActor.run {
                    self.activeCallUUID == uuid && self.callPhase.isActive
                }
                guard stillOurs, !Task.isCancelled else { return }

                do {
                    try await self.signaling?.sendReconnect(roomId: room, tryCount: attempt)
                } catch {
                    #if DEBUG
                    print("Reconnect attempt \(attempt) could not be sent: \(error)")
                    #endif
                    continue
                }

                // The server answers a successful reconnect with a fresh
                // `CALL_MEDIA_ANSWER`, which restarts media and clears the
                // status. Give it room to arrive before trying again.
                try? await Task.sleep(for: .seconds(2))
                let recovered = await MainActor.run { self.callStatus != .reconnecting }
                if recovered {
                    await MainActor.run { self.reconnectTask = nil }
                    return
                }
            }

            await MainActor.run {
                guard self.activeCallUUID == uuid, self.callPhase.isActive else { return }
                self.reconnectTask = nil
                self.failCall(reason: "Connection lost")
            }
        }
    }

    private func stopReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    /// Session liveness probe. Answered by `CALL_PONG`.
    private func startPing(roomId: String) async {
        await MainActor.run {
            self.pingTask?.cancel()
            self.pingTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pingInterval)
                    guard !Task.isCancelled else { return }
                    guard let self, self.callPhase.isActive else { return }
                    try? await self.signaling?.sendPing(
                        roomId: roomId,
                        callId: self.activeCallUUID?.lowercasedString
                    )
                }
            }
        }
    }

    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
    }

    /// Keeps the peer in the SFU room. Missing 30s of beats evicts us.
    private func startHeartbeat(roomId: String) async {
        await MainActor.run {
            self.heartbeatTask?.cancel()
            self.heartbeatTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    guard let self, self.callPhase.isActive else { return }
                    try? await self.signaling?.sendHeartbeat(roomId: roomId)
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Gives up on a call the far end never picked up.
    ///
    /// Without this the screen would ring indefinitely whenever the server does
    /// not answer — offline, unreachable, or simply not sending `CALL_MISSED`.
    /// Callable from the CallKit completion handler, which is not main-isolated;
    /// the deadline itself lands back on the main actor.
    private func startRingTimeout() {
        ringTimeoutTask?.cancel()
        let uuid = activeCallUUID
        ringTimeoutTask = Task { [weak self] in
            let deadline = self?.serverRingTimeout.map { $0 + Self.ringTimeoutGrace }
                ?? Self.ringTimeout
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                // Only fires while still ringing, and only for the same call.
                guard self.activeCallUUID == uuid, !self.callWasAnswered else { return }
                switch self.callPhase {
                case .outgoingRinging, .incomingRinging, .connecting:
                    // Local give-up: the server may never send CALL_MISSED (or
                    // we beat it). Publish so the other side stops ringing.
                    self.finishCall(
                        outcome: self.isIncoming ? .missed : .noAnswer,
                        message: "No answer",
                        reason: .noAnswer,
                        notifyServer: true
                    )
                default:
                    break
                }
            }
        }
    }

    private func stopRingTimeout() {
        ringTimeoutTask?.cancel()
        ringTimeoutTask = nil
    }

    // MARK: - Configuration
    private func initializePushKit() {
        pushKit = PushKitManager()
    }
    
    func enablePushKit() {
        if pushKit == nil {
            pushKit = PushKitManager()
        }
    }
    
    func disablePushKit() {
        pushKit = nil
    }
    
    func isPushKitEnabled() -> Bool {
        return pushKit != nil
    }
    
    // MARK: - App State Observer
    private func setupAppStateObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidBecomeActive() {
        if let activeCallUUID = activeCallUUID {
            appState.handleCallKitActivation(
                handle: callHandle ?? "Unknown",
                uuid: activeCallUUID,
                isIncoming: isIncoming
            )
        }
    }
    
    // MARK: - Calls from killed state
    func handleCallFromKilledState(uuid: UUID, handle: String, isIncoming: Bool) {
        DispatchQueue.main.async {
            self.activeCallUUID = uuid
            self.callHandle = handle
            self.isIncoming = isIncoming
            
            self.appState.handleCallKitActivation(
                handle: handle,
                uuid: uuid,
                isIncoming: isIncoming
            )
            
            if isIncoming {
                self.callPhase = .incomingRinging(handle: handle, isVideo: self.hasVideo)
                self.state = "Incoming from \(handle)"
            } else {
                self.callPhase = .outgoingRinging(handle: handle, isVideo: self.hasVideo)
                self.state = "Calling \(handle)"
            }
        }
    }
    
    // MARK: - Incoming Calls
    func reportIncomingCallFromPush(uuid: UUID, handle: String, hasVideo: Bool, name: String? = nil, image: String? = nil, onReported: (() -> Void)? = nil) {
        self.activeCallUUID = uuid
        self.callHandle = handle
        self.callerName = name
        self.callerProfileImage = image
        self.hasVideo = hasVideo
        self.isVideoCall = hasVideo
        self.isIncoming = true
        self.callStartTime = Date()
        loadContactNames()
        self.callWasAnswered = false
        self.isAnswerJoinInFlight = false
        self.callHistoryPersisted = false
        self.hasNotifiedServerOfEnd = false
        self.isRoomEstablished = false
        self.hasRetriedJoin = false
        self.isMediaRunning = false
        self.isCallKitAudioActivated = false
        self.pendingMediaSetupEvent = nil
        self.serverCallId = nil
        // Video / group: speaker on + proximity off so ear-near does not blank the screen.
        applyLoudspeakerPolicy(enabled: hasVideo)
        self.remoteParticipants = [
            CallInvitee(userId: handle, name: name ?? handle, phone: handle)
        ]
        // Incoming always starts as the top banner. Tap expands to Decline/Accept.
        // Lock-screen slide-to-answer is CallKit's UI, not this screen.
        self.isMinimized = true
        
        self.callKit.reportIncomingCall(uuid: uuid, handle: name ?? handle, hasVideo: hasVideo) { [weak self] success in
            guard let self else { onReported?(); return }
            if success {
                self.callPhase = .incomingRinging(handle: self.displayName, isVideo: hasVideo)
                self.state = "Incoming from \(self.displayName)"
                // CallKit rings this one — no tone of our own.
                self.startRingTimeout()
                // Warm MQTT while the phone rings so Accept from the lock
                // screen is not racing a cold reconnect.
                self.warmRealtimeForIncomingCall()
            } else {
                // The system refused to ring — the user never had a chance to
                // answer. Tell the caller so they do not keep ringing while we
                // only record a missed call locally (common on Simulator).
                self.notifyServerOfLocalEndIfNeeded()
                self.persistCallToHistory(outcome: .missed)
                self.callPhase = .ended
                self.state = ChatErrorStrings.callConnectFailed
                self.scheduleEndedDismiss()
            }
            onReported?()
        }
    }

    // MARK: - Outgoing Calls

    /// Places an outgoing call.
    ///
    /// `conversationId` must be the id of the conversation the call belongs to.
    /// Callers that already sit in a conversation pass theirs; the rest leave it
    /// nil and the conversation is resolved from the contact's phone before the
    /// call is logged. It is never invented — writing a made-up id is what
    /// created duplicate conversations.
    /// - Parameter userId: the callee's real account id. The server resolves
    ///   conversation membership by it, and sending a phone number in its place
    ///   is what makes the offer fail with `CORE_INITIATE_FAILED`. Nil only when
    ///   dialling a number that belongs to no known contact.
    /// - Parameter hasVideo: no default on purpose. It used to default to `true`,
    ///   which sent audio calls looking for a camera and — before the engine
    ///   degraded gracefully — cost the caller every track, audio included.
    /// - Parameter otherInvitees: everyone being called besides `handle`. Empty
    ///   for a 1:1. CALL-INTEGRATION §11 opens a group with the *same*
    ///   `call-offer` carrying several `participants` — `call-invite-peers` is
    ///   for adding people mid-call — so these ride the first offer rather than
    ///   being dialled afterwards. That is also what lets the caller show the
    ///   whole group as waiting straight away instead of one person at a time.
    func startOutgoingCall(
        to handle: String,
        hasVideo: Bool,
        name: String? = nil,
        image: String? = nil,
        conversationId: String? = nil,
        userId: String? = nil,
        otherInvitees: [CallInvitee] = []
    ) {
        // One active call per user, per the contract. Without this a second dial
        // overwrites the live call's id, handle and phase — the first call keeps
        // running on the server while the client has forgotten it, and the
        // server's `CALL_BUSY (already_in_call)` arrives too late to help.
        guard !callPhase.isActive else {
            #if DEBUG
            print("Ignoring call to \(handle): already on a call")
            #endif
            return
        }

        let uuid = UUID()

        activeCallUUID = uuid
        callHandle = handle
        callerName = name
        callerProfileImage = image
        self.hasVideo = hasVideo
        self.isVideoCall = hasVideo
        isIncoming = false
        callStartTime = Date()
        isMinimized = false
        loadContactNames()
        // Video / group: speaker on; proximity must not blank the screen.
        applyLoudspeakerPolicy(enabled: hasVideo)
        // Keep the local conversation id for history / thread append. The wire
        // id is resolved just before `call-offer` (server id when linked).
        self.conversationId = conversationId
        // Show the live call UI immediately — permissions, conversation lookup,
        // and `call-offer` run in the background without freezing chrome.
        let displayHandle = name ?? handle
        callPhase = .outgoingRinging(handle: displayHandle, isVideo: hasVideo)
        isCalleeRinging = false
        ringingPeerKeys = []
        isRoomEstablished = false
        hasRetriedJoin = false
        hasNotifiedServerOfEnd = false
        isMediaRunning = false
        isCallKitAudioActivated = false
        pendingMediaSetupEvent = nil
        serverCallId = nil
        endReason = .hungUp
        callStatus = .calling
        isLocalPreviewReady = false
        state = "Calling \(displayHandle)"
        startRingTimeout()

        // Falling back to the phone keeps a call to an unknown number working,
        // but a known contact must go out under their account id — the server
        // resolves conversation membership by it, not by phone.
        let peerUserId = (userId?.isEmpty == false) ? userId! : handle
        let primary = CallInvitee(userId: peerUserId, name: name ?? handle, phone: handle)

        // Room limit of 32 counts this device and the primary callee, so the
        // rest of the group gets what is left.
        let others = Array(
            otherInvitees
                .filter { !VoipManager.rowsShareIdentity($0, primary) }
                .prefix(Self.maxParticipants - 2)
        )
        let isGroupOffer = !others.isEmpty

        // Seeded before anything goes on the wire so the participant grid can
        // show every callee as waiting from the moment the call is placed, not
        // once the server starts answering.
        remoteParticipants = [primary] + others

        let offerParticipants = ([primary] + others).map {
            CallParticipantDTO(userId: $0.userId, username: $0.name, phone: $0.phone)
        }

        // CallKit owns the VoIP audio session. Without an outgoing CX call the
        // caller never gets `didActivate`, WebRTC never enables capture, and
        // produce stays dead while the joiner (who answered via CallKit) works.
        callKit.startOutgoingCall(
            uuid: uuid,
            handle: name ?? handle,
            hasVideo: hasVideo
        )

        if hasVideo {
            Task { @MainActor in
                self.ensureLocalVideoPreview()
            }
        }

        outgoingOfferTask?.cancel()
        outgoingOfferTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                // One frame so CallScreen can mount; do not gate the UI on this.
                try? await Task.sleep(for: .milliseconds(50))
                try Task.checkCancellation()
                let stillOurs = await MainActor.run {
                    self.activeCallUUID == uuid && self.callPhase.isActive
                }
                guard stillOurs else { return }

                // Ahead of the offer, not after `CALL_OFFER_MEDIA`: the SFU
                // handshake starts the moment the server answers, and a
                // permission sheet appearing then would race `produceAudio`.
                let allowCreate = await MainActor.run { self.pendingInvitees.isEmpty }
                async let permissionsDone: Void = self.requestCapturePermissions(video: hasVideo)
                async let resolvedConversationId: String? = self.ensureLocalConversationId(
                    existing: conversationId,
                    handle: handle,
                    name: name,
                    image: image,
                    userId: peerUserId,
                    allowCreate: allowCreate
                )
                await permissionsDone
                try Task.checkCancellation()

                let stillActive = await MainActor.run {
                    self.activeCallUUID == uuid && self.callPhase.isActive
                }
                guard stillActive else { return }

                let localConversationId = await resolvedConversationId
                if let localConversationId {
                    await MainActor.run {
                        guard self.activeCallUUID == uuid else { return }
                        self.conversationId = localConversationId
                    }
                }

                let wireConversationId = await self.outboundConversationId(for: localConversationId)
                #if DEBUG
                if let localConversationId, localConversationId != wireConversationId {
                    print("[CallMedia] call-offer conversation local=\(localConversationId) wire=\(wireConversationId ?? "nil")")
                }
                #endif
                let room = uuid.lowercasedString
                try await self.signaling?.sendOffer(
                    roomId: room,
                    conversationId: wireConversationId,
                    isVideo: hasVideo,
                    participants: offerParticipants
                )
                try Task.checkCancellation()

                let stillLive = await MainActor.run {
                    self.activeCallUUID == uuid && self.callPhase.isActive
                }
                guard stillLive else {
                    await MainActor.run {
                        self.undoServerRegistrationIfCallEnded(roomId: room)
                    }
                    return
                }

                await self.startHeartbeat(roomId: room)
                await self.startPing(roomId: room)
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.activeCallUUID == uuid, self.callPhase.isActive else { return }
                    self.failCall(reason: error.localizedDescription)
                }
            }
        }
    }

    /// Marks the inline local camera (or SFU local track) as visible on CallScreen.
    @MainActor
    func markLocalPreviewReady() {
        guard !isLocalPreviewReady else { return }
        isLocalPreviewReady = true
    }

    /// One camera path for the whole call: WebRTC preview first, AVCapture fallback.
    @MainActor
    func ensureLocalVideoPreview() {
        guard hasVideo, localVideoTrack == nil else { return }
        guard localPreviewTask == nil else { return }
        localPreviewTask = Task { [weak self] in
            await self?.beginLocalVideoPreview()
        }
    }

    @MainActor
    private func beginLocalVideoPreview() async {
        defer { localPreviewTask = nil }
        guard hasVideo, localVideoTrack == nil else { return }
        guard callPhase.isActive else { return }

        await requestCapturePermissions(video: true)
        guard callPhase.isActive else { return }

        if let engine = mediaEngine {
            do {
                if let track = try await engine.prepareLocalVideoPreview() {
                    localVideoTrack = track
                    stopFallbackCameraPreview()
                    markLocalPreviewReady()
                    return
                }
            } catch {
                #if DEBUG
                print("[CallMedia] WebRTC preview failed: \(error.localizedDescription)")
                #endif
            }
        }

        await beginFallbackCameraPreview()
    }

    @MainActor
    private func beginFallbackCameraPreview() async {
        guard hasVideo, localVideoTrack == nil else { return }
        await fallbackCamera.start()
        markLocalPreviewReady()
    }

    @MainActor
    func stopFallbackCameraPreview() {
        fallbackCamera.stop()
    }

    @MainActor
    private func stopAllLocalVideoPreview() {
        localPreviewTask?.cancel()
        localPreviewTask = nil
        stopFallbackCameraPreview()
    }

    /// Calls a whole group in a single offer (§11).
    ///
    /// CALL-INTEGRATION §11 requires all callees to be listed in the initial
    /// `call-offer` `participants` array. `call-invite-peers` is for genuine
    /// mid-call additions only. Passing everyone through `otherInvitees` means:
    ///   • The waiting grid is populated instantly — all callees show as ringing
    ///     the moment the caller taps call, not one at a time as invites land.
    ///   • The broker receives one coherent offer that it can route to all
    ///     participants simultaneously.
    ///   • `pendingInvitees` stays empty; `invitePeers` is never called at
    ///     room-creation time.
    func startGroupCall(
        _ participants: [CallInvitee],
        hasVideo: Bool,
        conversationId: String? = nil,
        groupName: String? = nil
    ) {
        guard let first = participants.first else { return }

        // Everyone after the primary callee rides the same offer, capped by the
        // room limit. maxParticipants counts all peers; subtract 1 for this
        // device and 1 for the primary to get the headroom for the rest.
        let others = Array(
            participants
                .dropFirst()
                .prefix(Self.maxParticipants - 2)
        )

        startOutgoingCall(
            to: first.phone,
            hasVideo: hasVideo,
            name: groupName ?? first.name,
            conversationId: conversationId,
            userId: first.userId,
            otherInvitees: others
        )
    }

    /// Ends a call that could not be established, recording it as a failure.
    ///
    /// Defaults to `.failed` because every path here is something going wrong —
    /// an offer that would not publish, a join the server would not accept. None
    /// of them is the user changing their mind, which is what `.cancelled` means.
    @MainActor
    private func failCall(reason: String, outcome: CallOutcome = .failed) {
        cancelInFlightCallWork()
        // Offer may already be on the wire (join failed, reconnect gave up). Tell
        // the server so the far end does not keep ringing on a dead attempt.
        notifyServerOfLocalEndIfNeeded()
        state = reason
        endReason = .failed
        callStatus = .failed
        stopAllTones()
        stopMedia()
        stopRingTimeout()
        if let uuid = activeCallUUID {
            callKit.endCall(uuid: uuid)
        }
        persistCallToHistory(outcome: outcome)
        callPhase = .ended
        scheduleEndedDismiss()
    }

    // MARK: - Group / invite

    /// Pulls more people into the running call, up to the room limit.
    func invitePeers(_ invitees: [CallInvitee]) {
        // The room has to exist first. `callPhase.isActive` is true from the
        // moment the call is placed, which is too early — the invite would be
        // published to a room the server has not created.
        guard let uuid = activeCallUUID, callPhase.isActive, isRoomEstablished else { return }

        // The live roster, not invite history — somebody who declined or left has
        // to be invitable again, and must not keep holding a slot.
        let known = activeParticipantPhones
        let newcomers = invitees.filter { !known.contains($0.phone.onlyDigits) }
        guard !newcomers.isEmpty else { return }

        // +1 for this device, which is in the room but never in `remoteParticipants`.
        let free = Self.maxParticipants - known.count - 1
        guard free > 0 else { return }

        let accepted = Array(newcomers.prefix(free))
        let isVideo = hasVideo

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.signaling?.sendInvitePeers(
                    roomId: uuid.lowercasedString,
                    isVideo: isVideo,
                    participants: accepted.map {
                        CallParticipantDTO(userId: $0.userId, username: $0.name, phone: $0.phone)
                    }
                )
                // Only reflect them locally once the invite really went out.
                // Existing remotes are already in-room; newcomers stay waiting
                // until `CALL_PEER_JOINED` / their first producer.
                await MainActor.run {
                    for existing in self.remoteParticipants {
                        self.markPeerJoined(existing)
                    }
                    self.invitedParticipants.append(contentsOf: accepted)
                    self.remoteParticipants.append(contentsOf: accepted)
                    self.dedupeRemoteParticipants()
                    // The invite was accepted, which is when the server fans
                    // `CALL_INITIATED` out to them — the same evidence the
                    // one-to-one path treats as "their phone is ringing".
                    self.markPeersRinging(accepted)
                    self.refreshLoudspeakerPolicyIfNeeded()
                }
            } catch {
                #if DEBUG
                print("Failed to invite peers: \(error)")
                #endif
            }
        }
    }

    // MARK: - Inbound call events

    /// Drives the call state machine from real server events.
    ///
    /// Only events for the call we are actually in are acted on: the inbox is
    /// shared, and a stale event from a previous room must not tear down the
    /// current one.
    @MainActor
    private func handle(_ event: InboundCallEventDTO) {
        // `suppressNotification` means "do not alert the user" — no ring, no
        // banner. It does not mean "ignore this". Treating it as a filter here
        // silently dropped whole events: a suppressed CALL_ERROR left the screen
        // calling until the no-answer timeout, and CALL_ENDED or CALL_REJECTED
        // would do the same. Suppression is honoured where alerting happens, in
        // `handleIncoming`.

        // Almost every event names the call. Recording it means the history this
        // device writes is filed under the id the server uses, so the two can be
        // reconciled instead of sitting side by side.
        #if DEBUG
        // Every call event, before any filtering. A call that produces nothing
        // is almost always an event that was dropped here — either it never
        // arrived, or its room did not match ours — and both look identical
        // from the UI.
        debugLog(
            "\(event.eventType) room=\(event.roomId ?? "nil") ours=\(roomId ?? "nil") match=\(isForActiveCall(event))",
            category: "call-signal"
        )
        #endif

        if let callId = event.callId, !callId.isEmpty, isForActiveCall(event) {
            serverCallId = callId
        }

        switch event.eventType {
        case ChatMqttEvents.Call.initiated:
            handleIncoming(event)

        case ChatMqttEvents.Call.offerMedia, ChatMqttEvents.Call.mediaAnswer:
            guard isForActiveCall(event) else { return }
            // Set from the event rather than from `startMedia`, which gives up
            // early when no media engine is wired in — signaling to the room
            // still works in that case.
            isRoomEstablished = true
            // UI/ringing first; ringback itself waits until produce succeeds.
            if event.eventType == ChatMqttEvents.Call.offerMedia {
                markRinging()
            }
            startMedia(with: event)
            // Listen before the user can possibly tap Share: the extension
            // connects the moment the system picker is confirmed, and the first
            // frame is our only signal that a broadcast actually started.
            startScreenShareBridge()

        case ChatMqttEvents.Call.producerState:
            guard isForActiveCall(event) else { return }
            updateRemoteTrackState(event)

        case ChatMqttEvents.Call.handRaised, ChatMqttEvents.Call.requestToSpeak:
            guard isForActiveCall(event) else { return }
            // Both events describe one act and both arrive, which is why `raise`
            // has to be idempotent. Ids are normalised on the way in because the
            // grid keys its tiles on `participantKey`, and a raw wire id would
            // put the hand on nobody's tile.
            if let peer = event.participantId ?? event.peerId {
                handQueue.raise(participantKey(peer))
                if isSelfPeerId(peer) { isHandRaised = true }
            }
            handQueue.apply(serverQueue: event.speakingQueue?.map(participantKey))
            raisedHands = handQueue.queue

        case ChatMqttEvents.Call.handLowered:
            guard isForActiveCall(event) else { return }
            if let peer = event.participantId ?? event.peerId {
                handQueue.lower(participantKey(peer))
                if isSelfPeerId(peer) { isHandRaised = false }
            }
            handQueue.apply(serverQueue: event.speakingQueue?.map(participantKey))
            raisedHands = handQueue.queue

        case ChatMqttEvents.Call.handAcknowledged:
            guard isForActiveCall(event) else { return }
            // V3 §16.1 documents this event only as a topic→event row — no
            // payload example — so both plausible spellings of its subject are
            // read rather than guessing one.
            if let peer = event.targetUserId ?? event.participantId ?? event.peerId {
                handQueue.lower(participantKey(peer))
                if isSelfPeerId(peer) { isHandRaised = false }
            }
            handQueue.apply(serverQueue: event.speakingQueue?.map(participantKey))
            raisedHands = handQueue.queue

        case ChatMqttEvents.Call.reaction:
            guard isForActiveCall(event) else { return }
            guard let peer = event.peerId, let emoji = event.reaction else { return }
            // Ours is already on screen from the optimistic path.
            guard !isSelfPeerId(peer) else { return }
            showReaction(peerId: participantKey(peer), emoji: emoji)

        case ChatMqttEvents.Call.screenShareStarted:
            guard isForActiveCall(event) else { return }
            if let peerId = event.peerId { screenSharingPeerId = peerId }

        case ChatMqttEvents.Call.screenShareStopped:
            guard isForActiveCall(event) else { return }
            if event.peerId == screenSharingPeerId { screenSharingPeerId = nil }

        case ChatMqttEvents.Call.statusChanged:
            // Presence only — `ON_CALL` / `AVAILABLE` per §9.1. It carries no
            // roomId, so it must not be matched against the active call.
            break

        case ChatMqttEvents.Call.newProducer:
            guard isForActiveCall(event) else { return }
            consumeRemoteProducer(event)

        case ChatMqttEvents.Call.answered:
            guard isForActiveCall(event) else { return }
            notePeerAnswered()

        case ChatMqttEvents.Call.peerJoined:
            guard isForActiveCall(event) else { return }
            addJoinedPeer(event)
            notePeerAnswered()

        case ChatMqttEvents.Call.rejected:
            guard isForActiveCall(event) else { return }
            handleInviteeUnavailable(
                event,
                message: "Call declined",
                aloneOutcome: .declined,
                aloneReason: .declined
            )

        case ChatMqttEvents.Call.busy:
            guard isForActiveCall(event) else { return }
            handleBusy(event)

        case ChatMqttEvents.Call.missed:
            guard isForActiveCall(event) else { return }
            handleInviteeUnavailable(
                event,
                message: "No answer",
                aloneOutcome: isIncoming ? .missed : .noAnswer,
                aloneReason: .noAnswer
            )

        case ChatMqttEvents.Call.ended:
            guard isForActiveCall(event) else { return }
            handleEnded(event)

        case ChatMqttEvents.Call.peerLeft:
            guard isForActiveCall(event) else { return }
            handlePeerLeft(event)

        case ChatMqttEvents.Call.reconnecting:
            guard isForActiveCall(event) else { return }
            handleReconnecting(event)

        case ChatMqttEvents.Call.pong:
            guard isForActiveCall(event) else { return }
            // Proof the session is alive. A call showing "Reconnecting…" over a
            // dropped transport is demonstrably back.
            if callStatus == .reconnecting, callWasAnswered {
                callStatus = .connected
            }

        case ChatMqttEvents.Call.hold:
            guard isForActiveCall(event) else { return }
            isRemoteOnHold = event.payload["isOnHold"] as? Bool ?? true

        case ChatMqttEvents.Call.transferred:
            // Agent transfer, not device handoff (§9.4). The call carries on with
            // somebody else at the far end.
            guard isForActiveCall(event) else { return }
            #if DEBUG
            print("Call transferred to \(event.payload["toUserId"] as? String ?? "unknown")")
            #endif

        case ChatMqttEvents.Call.deviceTransferred:
            guard isForActiveCall(event) else { return }
            handleDeviceTransfer(event)

        case ChatMqttEvents.Call.error:
            guard isForActiveCall(event) else { return }
            handleCallError(event)

        default:
            // Media plumbing and presence updates are not UI state.
            break
        }
    }

    /// Events carry the room they belong to; anything else is from another call.
    private func isForActiveCall(_ event: InboundCallEventDTO) -> Bool {
        guard let roomId else { return false }
        guard let eventRoom = event.roomId else { return true }
        return eventRoom.caseInsensitiveCompare(roomId) == .orderedSame
    }

    @MainActor
    private func handleIncoming(_ event: InboundCallEventDTO) {
        // This is the one place suppression belongs: a silent CALL_INITIATED is
        // bookkeeping — a resend, or a call already picked up on another device —
        // and must not take over the screen or ring.
        guard !event.suppressNotification else { return }

        // One active call per user: anything arriving mid-call is rejected as busy.
        guard !callPhase.isActive else {
            if let room = event.roomId {
                Task { [weak self] in
                    try? await self?.signaling?.sendReject(roomId: room, reason: "busy")
                }
            }
            return
        }

        guard let room = event.roomId, let uuid = UUID(uuidString: room) else { return }
        let caller = event.caller

        // The server states how long it will ring before giving up. Honouring it
        // keeps both sides on the same deadline instead of guessing at 50s.
        if let timeoutMs = event.ringingTimeoutMs, timeoutMs > 0 {
            serverRingTimeout = .milliseconds(timeoutMs)
        }

        reportIncomingCallFromPush(
            uuid: uuid,
            handle: caller?.phone ?? caller?.userId ?? event.from ?? "Unknown",
            hasVideo: event.isVideo,
            name: caller?.username,
            image: nil
        )

        let handle = callHandle ?? "Unknown"
        let peerUserId = caller?.userId ?? handle
        let wireConversationId = event.conversationId
        // Keep the wire id immediately so an early hangup still has something to
        // resolve; the Task below replaces it with the local PK when known.
        if let wireConversationId, !wireConversationId.isEmpty {
            conversationId = wireConversationId
        }

        // Captured here rather than in `handle`: there was no active call to
        // match against when this event arrived, so the generic capture skipped
        // it.
        if let callId = event.callId, !callId.isEmpty {
            serverCallId = callId
        }

        // The event lists everyone invited / already in the room — always seed
        // the roster (even a single other peer). Mid-call invitees otherwise
        // keep a 1:1 placeholder and never show the rest of the group.
        // Normalised, and matching on phone as well as uid: a raw `!=` against
        // the account id missed this device whenever the wire named it by the
        // other of the two.
        let others = event.participants.filter {
            !isSelfPeerId($0.userId) && !isSelfPeerId($0.phone)
        }
        let isMultiParty = others.count > 1
        if !others.isEmpty {
            seedRemoteParticipants(from: event.participants)
        }

        // Same as outbound: ensure a local conversation exists while ringing,
        // not only when the call ends.
        let roomUUID = uuid
        let callerName = caller?.username
        Task { [weak self] in
            guard let self else { return }
            let localId = await self.ensureLocalConversationId(
                existing: wireConversationId,
                handle: handle,
                name: callerName,
                image: nil,
                userId: peerUserId,
                allowCreate: !isMultiParty
            )
            await MainActor.run {
                guard self.activeCallUUID == roomUUID else { return }
                if let localId {
                    self.conversationId = localId
                }
            }
        }
    }

    /// A remote peer muted, unmuted, or turned their camera on or off.
    ///
    /// `CALL_PRODUCER_STATE` is keyed by peer and kind rather than by producer
    /// id (§9.2), which is why the client never needs to track producer ids.
    @MainActor
    private func updateRemoteTrackState(_ event: InboundCallEventDTO) {
        // Normalised: a raw `!=` let this device's own mute or camera state
        // through, and it was then written under a peer key — a badge appearing
        // on somebody else's tile.
        guard
            let peerId = event.peerId,
            let isPaused = event.isPaused,
            !isSelfPeerId(peerId)
        else { return }

        let key = participantKey(peerId)
        switch event.mediaKind?.lowercased() {
        case "audio":
            if isPaused { mutedPeerIds.insert(key) } else { mutedPeerIds.remove(key) }
        case "video":
            if isPaused { cameraOffPeerIds.insert(key) } else { cameraOffPeerIds.remove(key) }
        default:
            break
        }
    }

    /// The room closed — or, mid-group, a misleading fan-out when one peer left.
    ///
    /// `reason` says which of the two it was while still ringing (§9.1):
    /// `TIMEOUT` when nobody answered within `ringingTimeoutMs`, `CANCELLED`
    /// when the caller hung up. Once answered, `CALL_PEER_LEFT` is the real
    /// per-peer leave; a `CALL_ENDED` that still names other remotes must not
    /// tear the whole group down.
    @MainActor
    private func handleEnded(_ event: InboundCallEventDTO) {
        let isTimeout = event.reason?.caseInsensitiveCompare("TIMEOUT") == .orderedSame

        if callWasAnswered {
            // Prefer explicit leave ids — never `peerId`'s `from` fallback, which
            // can name the initiator and wipe the wrong tile.
            let leaver = event.endedBy
                ?? (event.payload["peerId"] as? String)
                ?? (event.payload["userId"] as? String)
            if let leaver, hasRemainingRemotes {
                removeRemotePeer(matching: leaver)
                if hasRemainingRemotes {
                    state = "A participant left"
                    return
                }
            } else if remoteParticipants.count > 1 {
                // Blanket end while several remotes remain — keep the room.
                #if DEBUG
                print("[CallSignal] Ignoring CALL_ENDED — \(remoteParticipants.count) remotes still on roster")
                #endif
                return
            }

            finishCall(outcome: .answered, message: "Call ended", reason: .hungUp)
            return
        }

        if isTimeout {
            finishCall(
                outcome: isIncoming ? .missed : .noAnswer,
                message: "No answer",
                reason: .noAnswer
            )
        } else {
            // Cancelled while ringing: missed for the callee, cancelled for the
            // caller who hung up.
            finishCall(
                outcome: isIncoming ? .missed : .cancelled,
                message: "Call ended",
                reason: .hungUp
            )
        }
    }

    /// Somebody could not take the call.
    ///
    /// Two very different situations share this event (§9.1). `callee_busy` is
    /// the far end already talking. `already_in_call` is *our own* offer being
    /// refused because this user is mid-call — and its `roomId` is the call we
    /// are already on, so treating it as terminal would hang up the very call
    /// that caused the refusal.
    @MainActor
    private func handleBusy(_ event: InboundCallEventDTO) {
        let isSelfBlocked = event.reason?.caseInsensitiveCompare("already_in_call") == .orderedSame

        if isSelfBlocked {
            // Our own offer was refused because this user is mid-call. If a call
            // really is up, the refusal concerns an attempt that must not be
            // allowed to disturb it.
            guard !callWasAnswered else {
                #if DEBUG
                print("Call offer refused: already on a call")
                #endif
                return
            }

            // Otherwise this attempt is the one that was refused, and leaving it
            // on "Calling…" until the ring timeout tells the user nothing.
            finishCall(outcome: .failed, message: "Already on a call", reason: .busy)
            return
        }

        handleInviteeUnavailable(
            event,
            message: "User is on another call",
            aloneOutcome: .busy,
            aloneReason: .busy
        )
    }

    /// One invitee rejected, missed, or was busy — drop their waiting card.
    ///
    /// Only finishes the whole call when nobody else remains (classic 1:1).
    /// Never disconnects us from a live group just because one invite failed.
    @MainActor
    private func handleInviteeUnavailable(
        _ event: InboundCallEventDTO,
        message: String,
        aloneOutcome: CallOutcome,
        aloneReason: CallEndReason
    ) {
        if let peerId = event.peerId {
            removeRemotePeer(matching: peerId)
        }

        if hasRemainingRemotes {
            state = message
            return
        }

        // peerId missing/mismatch on a live group — do not hang everyone up.
        if callWasAnswered && isRoomEstablished && !joinedPeerKeys.isEmpty {
            state = message
            return
        }

        finishCall(
            outcome: aloneOutcome,
            message: message,
            reason: aloneReason,
            notifyServer: !callWasAnswered
        )
    }

    /// Somebody is rebuilding their transports after a network drop (§6).
    ///
    /// The event names who (`peerId`), and that distinction is the whole point:
    /// treating every `CALL_RECONNECTING` as our own told the user *they* were
    /// reconnecting whenever anyone else on the call hiccuped, and started this
    /// device's own reconnect sequence against a transport that was working.
    @MainActor
    private func handleReconnecting(_ event: InboundCallEventDTO) {
        if let peerId = event.peerId, !peerId.isEmpty, !isSelfPeerId(peerId) {
            markPeerReconnecting(peerId)
            return
        }

        callStatus = .reconnecting
        state = "Reconnecting…"
        beginReconnect()
    }

    /// Someone joined the room.
    ///
    /// `CALL_PEER_JOINED` identifies them in a singular `user` object, which is
    /// how a peer we never dialled — invited by someone else in a group — first
    /// becomes known to this device.
    @MainActor
    private func addJoinedPeer(_ event: InboundCallEventDTO) {
        guard let peer = event.user ?? event.participants.first else { return }
        guard !isSelfPeerId(peer.userId) else { return }

        let phone = peer.phone ?? ""
        let name = peer.username.isEmpty
            ? (phone.isEmpty ? peer.userId : phone)
            : peer.username

        upsertRemotePeer(
            userId: peer.userId,
            name: name,
            phone: phone.isEmpty ? nil : phone,
            markJoined: true
        )
        reindexVideoTracksForRoster()
    }

    /// Rebuilds the peer→track index from the consumers that are still open.
    ///
    /// A full rebuild, not a merge: it is the only thing that retires the slot
    /// of a peer who left, and it does so without ever deleting a key by name —
    /// so a consumer closing can never blank a tile another consumer still
    /// serves.
    @MainActor
    private func reindexVideoTracksForRoster() {
        videoTracksByPeer = Self.rebuiltTrackIndex(
            consumerOwners: consumerOwners,
            tracks: remoteVideoTracks,
            aliases: { identityKeys(forPeerId: $0) }
        )
    }

    /// Someone left the room.
    ///
    /// Not the same as the call ending: in a group, one person hanging up
    /// leaves everyone else talking. Only when nobody remains on the other side
    /// — which is always the case one-to-one — does the call finish. The server
    /// sends `CALL_ENDED` separately when it really is over.
    @MainActor
    private func handlePeerLeft(_ event: InboundCallEventDTO) {
        // Only the live roster shrinks. `invitedParticipants` is what the call
        // log records, and someone who left was still on the call.
        let leaver = (event.payload["peerId"] as? String)
            ?? (event.payload["userId"] as? String)
        if let leaver {
            removeRemotePeer(matching: leaver)
        }

        guard !hasRemainingRemotes else {
            state = "A participant left"
            return
        }

        finishCall(outcome: outcomeForRemoteHangUp(), message: "Call ended")
    }

    /// What a device-handoff event means for this device.
    ///
    /// The server sends `CALL_DEVICE_TRANSFERRED` to *every* device of the user
    /// as soon as one of them joins — including the one that just answered. So
    /// the decision is entirely "is that me?", and the two outcomes are not
    /// symmetric: staying in a call that moved elsewhere leaves a stale screen
    /// the user can dismiss, while releasing a call this device just answered
    /// hangs up on them with no way back. Every uncertain case therefore keeps
    /// the call.
    static func deviceTransferOutcome(
        toDeviceId: String?,
        thisDeviceId: String?
    ) -> CallDeviceTransferOutcome {
        // No target named: nothing to compare against.
        guard let target = toDeviceId, !target.isEmpty else { return .keepCall }
        // We do not know which device we are — this is the case that used to
        // hang up on the answering device before its id had finished loading.
        guard let mine = thisDeviceId, !mine.isEmpty else { return .keepCall }

        // Case-insensitive: `identifierForVendor` is uppercase while every other
        // id on the wire is lowercase, so anything normalising case in transit
        // would stop this device recognising itself.
        return target.caseInsensitiveCompare(mine) == .orderedSame
            ? .keepCall
            : .releaseCall
    }

    /// One of this user's devices picked up, or the call was moved to another.
    ///
    /// Only a handoff to a *different* device closes this screen — see
    /// `deviceTransferOutcome` for why every uncertain case keeps the call.
    @MainActor
    private func handleDeviceTransfer(_ event: InboundCallEventDTO) {
        let outcome = Self.deviceTransferOutcome(
            toDeviceId: event.toDeviceId,
            thisDeviceId: thisDeviceId
        )

        guard outcome == .releaseCall else {
            // This device took the call — or we cannot prove it did not.
            stopAllTones()
            return
        }

        stopAllTones()
        cancelInFlightCallWork()
        stopMedia()
        stopRingTimeout()
        // Another device owns the call — the server already knows; do not
        // reject/disconnect from this one or the answering device loses media.
        acknowledgeServerEndedCall()
        callPhase = .ended
        state = "Continued on another device"
        scheduleEndedDismiss()
    }

    /// Documented failure codes (§9.3). Anything unrecognised is treated as
    /// terminal, which is the safe direction: ending a call that might have
    /// recovered beats leaving the user on a dead screen.
    private enum CallErrorCode {
        static let lockBusy = "LOCK_BUSY"
    }

    /// The server could not carry the call.
    ///
    /// Most codes are terminal — `CORE_INITIATE_FAILED`, `RECONNECT_FAILED`,
    /// `TRANSFER_FAILED`. `LOCK_BUSY` is not: §12 describes it as a join racing
    /// a reject, and prescribes retrying the join once.
    @MainActor
    private func handleCallError(_ event: InboundCallEventDTO) {
        // The server's text is English and infrastructure-facing
        // ("Conversation membership service is unavailable"), so it belongs in
        // the log, not in front of the user.
        #if DEBUG
        print("Call error \(event.errorCode ?? "unknown"): \(event.errorMessage ?? "no detail")")
        #endif

        if event.errorCode?.caseInsensitiveCompare(CallErrorCode.lockBusy) == .orderedSame,
           retryJoinAfterLockBusy() {
            return
        }

        // A refused screen share is not a call failure. It arrives as a generic
        // CALL_ERROR with no code (CALL-INTEGRATION.md §9.3 :700-717), so without
        // this the fall-through below would hang up a perfectly healthy call
        // because someone else was already sharing.
        if handleScreenShareRejection(code: event.errorCode, message: event.errorMessage) {
            return
        }

        // Recorded as a failure, not as the user hanging up. The Calls tab would
        // otherwise show a server outage as a call this user cancelled.
        finishCall(
            outcome: .failed,
            message: event.errorCode ?? "Call error",
            reason: .failed
        )
    }

    /// Retries a join that lost a race with a concurrent reject.
    ///
    /// Once only: a second `LOCK_BUSY` means the room is genuinely gone, and
    /// retrying forever would hold the caller on a call that cannot start.
    /// Returns whether a retry was actually scheduled.
    @MainActor
    private func retryJoinAfterLockBusy() -> Bool {
        guard isIncoming, !callWasAnswered, !hasRetriedJoin else { return false }
        guard let uuid = activeCallUUID, let room = roomId else { return false }

        hasRetriedJoin = true
        state = "Connecting…"

        Task { [weak self] in
            guard let self else { return }
            // A short pause lets the competing lock clear before trying again.
            try? await Task.sleep(for: .milliseconds(400))
            do {
                try await self.sendJoinWithRetries(roomId: room)
            } catch {
                await MainActor.run {
                    guard self.activeCallUUID == uuid else { return }
                    self.failCall(reason: "Could not join call")
                }
            }
        }
        return true
    }

    /// The far end is being alerted — its phone is actually ringing.
    ///
    /// This is what turns "Calling…" into "Ringing…" and starts the ringback,
    /// which in telephony means exactly one thing: the callee's device is
    /// ringing. Publishing the offer is not that; it only means the broker
    /// accepted the message.
    ///
    /// Driven by `CALL_OFFER_MEDIA`, which is the closest signal the contract
    /// offers: the server has created the room, which is also when it sends
    /// `CALL_INITIATED` to the callee. There is no dedicated ringing event —
    /// §9 lists every message realtime publishes and none says "the callee is
    /// alerting", so an unreachable callee shows as ringing until the timeout.
    @MainActor
    private func markRinging() {
        guard !callWasAnswered, !isCalleeRinging else { return }
        guard !isIncoming else { return }
        // A late signal after the call already ended must not restart anything.
        switch callPhase {
        case .connecting, .outgoingRinging:
            break
        default:
            return
        }

        isCalleeRinging = true
        if case .connecting = callPhase {
            callPhase = .outgoingRinging(handle: displayName, isVideo: isVideoCall)
        }
        // The room exists, so the server has alerted everyone on the offer —
        // the grid can say so per tile, not just the one-to-one header.
        markPeersRinging(remoteParticipants.filter(isPeerWaiting))
        callStatus = .ringing
        state = "Ringing \(displayName)"
        // Ringback starts after SFU produce succeeds (`startMedia`), not here —
        // starting AVAudioEngine beside the first produce stole the session and
        // left the caller unable to publish mic while the joiner worked fine.

        // The room exists now, so the rest of a redialled group can be pulled in.
        if !pendingInvitees.isEmpty {
            let invitees = pendingInvitees
            pendingInvitees = []
            invitePeers(invitees)
        }
    }

    @MainActor
    private func finishCall(
        outcome: CallOutcome,
        message: String,
        reason: CallEndReason = .hungUp,
        notifyServer: Bool = false
    ) {
        cancelInFlightCallWork()
        if notifyServer {
            notifyServerOfLocalEndIfNeeded()
        } else {
            // Server (or another device) already closed the call — CallKit's
            // follow-up `onEnded` must not publish a second hangup.
            acknowledgeServerEndedCall()
        }
        endReason = reason
        // One source for the line the user reads, derived from why it ended —
        // so the screen can never say "Calling…" for a call that is over.
        callStatus = Self.status(for: reason)
        stopCallTimer()
        stopAllTones()
        stopMedia()
        stopRingTimeout()
        if let uuid = activeCallUUID {
            callKit.endCall(uuid: uuid)
        }
        persistCallToHistory(outcome: outcome)
        callPhase = .ended
        state = message
        scheduleEndedDismiss()
    }

    // MARK: - Server hangup signaling

    /// Which MQTT command a local teardown should publish.
    ///
    /// Incoming + still ringing → reject (caller gets `CALL_REJECTED`).
    /// Anything else we initiated locally → disconnect.
    static func localEndSignal(
        hasNotifiedServer: Bool,
        isIncoming: Bool,
        wasAnswered: Bool
    ) -> CallLocalEndSignal? {
        guard !hasNotifiedServer else { return nil }
        if isIncoming && !wasAnswered {
            return .reject(reason: "declined")
        }
        return .disconnect
    }

    /// Publishes reject/disconnect at most once for the current call.
    private func notifyServerOfLocalEndIfNeeded() {
        guard let room = roomId else {
            hasNotifiedServerOfEnd = true
            return
        }
        guard let signal = Self.localEndSignal(
            hasNotifiedServer: hasNotifiedServerOfEnd,
            isIncoming: isIncoming,
            wasAnswered: callWasAnswered
        ) else { return }

        hasNotifiedServerOfEnd = true
        #if DEBUG
        switch signal {
        case .reject(let reason):
            print("[CallMedia] local end → call-reject (\(reason)) room=\(room)")
        case .disconnect:
            print("[CallMedia] local end → call-disconnect room=\(room)")
        }
        #endif

        Task { [weak self] in
            switch signal {
            case .reject(let reason):
                try? await self?.signaling?.sendReject(roomId: room, reason: reason)
            case .disconnect:
                try? await self?.signaling?.sendDisconnect(roomId: room)
            }
        }
    }

    private func acknowledgeServerEndedCall() {
        hasNotifiedServerOfEnd = true
    }

    // MARK: - Call Controls

    /// In-app Accept. CallKit lock-screen answer ends up in the same join path
    /// via `onAnswered` — do not send `call-join` here as well.
    func answerCall() {
        guard let uuid = activeCallUUID, roomId != nil else { return }

        stopAllTones()
        isMinimized = false
        callPhase = .connecting
        callStatus = .connecting
        state = "Connecting…"

        // Notifies CallKit and invokes `onAnswered` → `beginJoinAfterAnswer`.
        callKit.answerCall(uuid: uuid)
    }

    /// Publishes `call-join` once per answer (CallKit or in-app).
    ///
    /// Media produce still waits for inbound `CALL_MEDIA_ANSWER`; this only
    /// tells the server we accepted.
    @MainActor
    private func beginJoinAfterAnswer(uuid: UUID) {
        guard activeCallUUID == uuid, let room = roomId else { return }
        guard !callWasAnswered, !isAnswerJoinInFlight else {
            isMinimized = false
            return
        }

        isAnswerJoinInFlight = true
        isMinimized = false
        stopAllTones()

        if case .connecting = callPhase {
            // Already set by in-app `answerCall()`.
        } else if case .connected = callPhase {
            // Peer/MQTT already marked connected.
        } else {
            callPhase = .connecting
            callStatus = .connecting
            state = "Connecting…"
        }

        let wantsVideo = hasVideo
        Task { [weak self] in
            guard let self else { return }
            do {
                // Before the join, for the same reason as the offer: the server
                // answers with `CALL_MEDIA_ANSWER` and media starts immediately.
                await self.requestCapturePermissions(video: wantsVideo)
                if wantsVideo {
                    await MainActor.run { self.ensureLocalVideoPreview() }
                }
                // CallKit answer often races SessionManager's background MQTT
                // drop — reconnect + retry before giving up.
                try await self.sendJoinWithRetries(roomId: room)
                await self.startHeartbeat(roomId: room)
                await self.startPing(roomId: room)
                await MainActor.run {
                    self.isAnswerJoinInFlight = false
                    // Signaling-only path (no SFU wired): nothing will call
                    // `notePeerAnswered` from `startMedia`.
                    if self.mediaEngine == nil {
                        guard self.activeCallUUID == uuid else { return }
                        self.notePeerAnswered()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAnswerJoinInFlight = false
                    guard self.activeCallUUID == uuid else { return }
                    self.failCall(reason: "Could not join call")
                }
            }
        }
    }

    /// Publishes `call-join` after ensuring MQTT is up, with a few retries.
    ///
    /// Accept from a locked phone frequently hits a disconnected broker; a
    /// single attempt then fails the whole call even though reconnect would
    /// succeed a moment later.
    private func sendJoinWithRetries(roomId: String) async throws {
        guard let signaling else {
            struct SignalingUnavailable: Error {}
            throw SignalingUnavailable()
        }

        var lastError: Error?
        for attempt in 1...3 {
            do {
                // `sendJoin` reconnects MQTT + inbox when the broker was dropped
                // on background suspend.
                try await signaling.sendJoin(roomId: roomId)
                return
            } catch {
                lastError = error
                #if DEBUG
                print("[CallMedia] call-join attempt \(attempt) failed: \(error)")
                #endif
                if attempt < 3 {
                    try? await Task.sleep(for: .milliseconds(400 * attempt))
                }
            }
        }
        throw lastError ?? {
            struct JoinFailed: Error {}
            return JoinFailed()
        }()
    }

    /// Reconnects MQTT as soon as CallKit starts ringing — before the user answers.
    private func warmRealtimeForIncomingCall() {
        Task { [weak self] in
            try? await self?.signaling?.prepareForOutboundSignaling()
        }
    }

    @MainActor
    func declineCall() {
        guard let uuid = activeCallUUID, roomId != nil else { return }

        cancelInFlightCallWork()
        stopAllTones()
        stopMedia()
        stopRingTimeout()
        // Flag before CallKit so its async `onEnded` does not publish again.
        notifyServerOfLocalEndIfNeeded()
        callKit.endCall(uuid: uuid)

        // The user rejected an incoming call — declined, not missed.
        persistCallToHistory(outcome: .declined)

        callPhase = .ended
        state = "Call declined"
        scheduleEndedDismiss()
    }

    @MainActor
    func endCall() {
        guard let uuid = activeCallUUID, roomId != nil else { return }

        cancelInFlightCallWork()
        persistCallToHistory(outcome: outcomeForLocalHangUp())

        stopCallTimer()
        stopAllTones()
        stopMedia()
        stopRingTimeout()
        notifyServerOfLocalEndIfNeeded()
        callKit.endCall(uuid: uuid)

        callPhase = .ended
        state = "Call ended"
        scheduleEndedDismiss()
    }

    func toggleMute() {
        guard let uuid = activeCallUUID else { return }

        isMuted.toggle()
        callKit.muteCall(uuid: uuid, mute: isMuted)

        // Before media is up this is only a preference — applied in
        // `startMedia` once the mic producer exists. Publishing mute to the
        // room before anyone has joined would be a no-op on the far end.
        guard isMediaRunning, let room = roomId else { return }

        let muted = isMuted
        Task { [weak self] in
            // The track is what actually stops the far end hearing anything;
            // the signal only keeps their UI in step.
            await self?.mediaEngine?.setMicrophoneEnabled(!muted)
            try? await self?.signaling?.sendMute(roomId: room, isMuted: muted)
        }
    }
    
    // MARK: - Conference features (§16)

    /// Raises or lowers this device's hand.
    ///
    /// Guarded on a live room: §16.0 rule 1 is explicit that these topics act
    /// inside a call that already exists and never start one. Main-actor
    /// isolated so the queue has one owner — `handle(_:)` mutates it from there
    /// too, and splitting it across isolations is how races start.
    @MainActor
    func toggleHandRaise() {
        guard let room = roomId, callPhase.isActive else { return }

        let raising = !isHandRaised
        isHandRaised = raising

        // Optimistic. The server echoes HAND_RAISED / HAND_LOWERED to the whole
        // room including us, and that echo reconciles the queue order.
        let me = participantKey(getCurrentUserId())
        if raising { handQueue.raise(me) } else { handQueue.lower(me) }
        raisedHands = handQueue.queue

        let call = serverCallId
        Task { [weak self] in
            do {
                if raising {
                    try await self?.signaling?.sendHandRaise(roomId: room, callId: call)
                } else {
                    try await self?.signaling?.sendHandLower(roomId: room, callId: call)
                }
            } catch {
                #if DEBUG
                print("[CallFeature] hand raise/lower failed: \(error)")
                #endif
            }
        }
    }

    /// Host acknowledges somebody's raised hand.
    ///
    /// Gated locally as well as on the server: a control that silently does
    /// nothing reads as a bug, so non-hosts never get here.
    func acknowledgeHand(peerId: String) {
        guard isCallHost, let room = roomId, callPhase.isActive, !peerId.isEmpty else { return }

        let call = serverCallId
        Task { [weak self] in
            do {
                try await self?.signaling?.sendHandAck(
                    roomId: room, callId: call, targetUserId: peerId
                )
            } catch {
                #if DEBUG
                print("[CallFeature] hand ack failed: \(error)")
                #endif
            }
        }
    }

    /// Sends an ephemeral reaction. Never persisted (§16.2 step 2).
    ///
    /// Main-actor isolated because it draws the reaction locally before the
    /// round trip, and every caller is a tap.
    @MainActor
    func sendReaction(_ emoji: String) {
        guard let room = roomId, callPhase.isActive,
              CallReactionFeed.palette.contains(emoji) else { return }

        // Ours shows immediately: the server echo confirms it for everyone else,
        // and waiting a round trip makes the tap feel broken. Filed under the
        // local tile's own key, which is what `localGridItem` reads.
        showReaction(peerId: Self.localAudioLevelKey, emoji: emoji)

        Task { [weak self] in
            do {
                try await self?.signaling?.sendReaction(roomId: room, reaction: emoji)
            } catch {
                #if DEBUG
                print("[CallFeature] reaction failed: \(error)")
                #endif
            }
        }
    }

    /// Puts a reaction on screen and schedules its own removal.
    @MainActor
    private func showReaction(peerId: String, emoji: String) {
        let id = reactionFeed.add(peerId: peerId, emoji: emoji, at: Date())
        activeReactions = reactionFeed.items

        reactionPruneTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CallReactionFeed.ttl * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.reactionFeed.prune(now: Date())
                self.activeReactions = self.reactionFeed.items
                self.reactionPruneTasks[id] = nil
            }
        }
    }

    /// Drops every hand and reaction. Called when a call ends — none of this
    /// state outlives the room it belongs to.
    @MainActor
    private func clearConferenceFeatureState() {
        handQueue.removeAll()
        raisedHands = []
        isHandRaised = false
        reactionPruneTasks.values.forEach { $0.cancel() }
        reactionPruneTasks.removeAll()
        reactionFeed.removeAll()
        activeReactions = []
    }

    func toggleSpeaker() {
        // Video / group calls stay on speaker — proximity / earpiece is disabled.
        guard !requiresLoudspeakerPolicy else {
            isOnSpeaker = true
            UIDevice.current.isProximityMonitoringEnabled = false
            Task { [weak self] in
                try? await self?.applyAudioRoute(isSpeakerOn: true)
            }
            return
        }

        let nextValue = !isOnSpeaker
        // Optimistic: the button has to answer the tap now, and a failed
        // override is rolled back below rather than left lying to the user.
        isOnSpeaker = nextValue
        UIDevice.current.isProximityMonitoringEnabled = !nextValue
        Task { [weak self] in
            do {
                try await self?.applyAudioRoute(isSpeakerOn: nextValue)
            } catch {
                await MainActor.run {
                    self?.isOnSpeaker = !nextValue
                    self?.applyLoudspeakerPolicy(enabled: false)
                }
                #if DEBUG
                print("Speaker toggle failed: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Minimize

    /// Collapses the call to the top banner. The call itself is untouched —
    /// audio, timer and signaling all keep running.
    func minimize() {
        guard callPhase.isActive else { return }
        isMinimized = true
    }

    /// Brings the full call screen back.
    func expand() {
        isMinimized = false
    }

    /// Whether minimising this call should hand it to the floating window rather
    /// than the banner strip.
    ///
    /// A video call minimised into a one-line strip loses the only thing that
    /// made it a video call; an audio call gains nothing from a window, and the
    /// strip carries its duration and hang-up in less space.
    var minimizesToPictureInPicture: Bool {
        isVideoCall && callPhase.supportsPictureInPicture
    }

    func toggleVideo() {
        hasVideo.toggle()
        // Turning the camera on upgrades an audio call into the video layout;
        // turning it off only stops the stream — stay on VideoCallView.
        if hasVideo {
            isVideoCall = true
            applyLoudspeakerPolicy(enabled: true)
        }
        if case .connected = callPhase {
            callPhase = .connected(isVideo: isVideoCall)
        }

        // Before the media engine is running there is no camera to turn on, and
        // asking it to would surface "Camera unavailable" for what is really a
        // call that has not connected yet. The preference is still recorded, so
        // the camera starts in the right state once media begins.
        guard isMediaRunning else { return }

        guard let room = roomId else { return }
        let wantsVideo = hasVideo
        Task { [weak self] in
            guard let self else { return }
            // Starting the camera can fail (permission, hardware in use), and the
            // published state has to follow what really happened rather than what
            // was asked for.
            do {
                try await self.mediaEngine?.setCameraEnabled(wantsVideo)
                let track = await self.mediaEngine?.localVideoTrack()
                await MainActor.run {
                    self.localVideoTrack = wantsVideo ? track : nil
                    // The camera is producing now, so a share that was waiting
                    // on the switch can finally ask about broadcasting.
                    if wantsVideo { self.videoBecameReadyForPendingShare() }
                }
            } catch {
                await MainActor.run {
                    self.hasVideo = false
                    self.state = "Camera unavailable"
                    // No camera means no video call to carry a share; drop it
                    // rather than surfacing the broadcast prompt out of context.
                    self.cancelPendingShareSwitch()
                }
                return
            }
            try? await self.signaling?.sendVideo(roomId: room, isVideoOff: !wantsVideo)
        }
    }

    /// Flips between front and back camera.
    func switchCamera() {
        Task { [weak self] in
            try? await self?.mediaEngine?.switchCamera()
        }
    }
    
    // MARK: - Call Timer

    /// Starts (or restarts) the connected-call duration display.
    ///
    /// Always invalidates any previous timer first: `markAnswered`, CallKit
    /// `onAnswered`, and peer-joined can all fire for the same connect, and
    /// stacking `Timer`s made `callDuration` jump by 2+ each second.
    ///
    /// Duration is wall-clock from `callConnectedAt`, not a manual counter, so
    /// a delayed fire or a brief RunLoop stall does not permanently desync the
    /// displayed time from real elapsed seconds.
    func startCallTimer() {
        callTimer?.invalidate()
        if callConnectedAt == nil {
            callConnectedAt = Date()
        }
        refreshCallDuration()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshCallDuration()
        }
        RunLoop.main.add(timer, forMode: .common)
        callTimer = timer
    }

    private func refreshCallDuration() {
        guard let callConnectedAt else {
            callDuration = 0
            return
        }
        callDuration = max(0, Int(Date().timeIntervalSince(callConnectedAt)))
    }
    
    func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
        callConnectedAt = nil
        callDuration = 0
    }
    
    // MARK: - End Dismiss

    /// How long the end screen stays up.
    ///
    /// A call that connected and was hung up has nothing left to offer, so it
    /// clears itself almost at once. One that never connected holds long enough
    /// to read why and tap "Call again" — but it still goes away on its own. A
    /// phone left on a table must not sit on a dead call screen indefinitely.
    private var endedScreenDuration: TimeInterval {
        switch endReason {
        case .hungUp:
            return 1.5
        case .failed, .noAnswer, .declined, .busy:
            return 30
        }
    }

    private func scheduleEndedDismiss() {
        // A failed call can be redialled from its own end screen, so a second
        // call may end while the first screen's timer is still pending. The
        // token makes the stale one a no-op instead of closing the new screen
        // early.
        endedDismissToken &+= 1
        let token = endedDismissToken

        DispatchQueue.main.asyncAfter(deadline: .now() + endedScreenDuration) { [weak self] in
            guard let self = self, self.endedDismissToken == token else { return }
            if case .ended = self.callPhase {
                // Remove withAnimation to prevent TabView re-render
                // Animation is handled by the CallScreen transition
                self.callPhase = .idle
                self.appState.reset()
                self.resetCallState()
            }
        }
    }

    /// The status text that matches how a call ended.
    private static func status(for reason: CallEndReason) -> CallStatus {
        switch reason {
        case .hungUp:   return .ended
        case .failed:   return .failed
        case .noAnswer: return .noAnswer
        case .declined: return .declined
        case .busy:     return .busy
        }
    }

    /// Distinguishes one scheduled dismissal from the next.
    private var endedDismissToken: UInt = 0

    /// Closes an end screen that is waiting on the user.
    @MainActor
    func dismissEndedCall() {
        guard case .ended = callPhase else { return }
        callPhase = .idle
        appState.reset()
        resetCallState()
    }

    /// Places the same call again from the end screen.
    ///
    /// Read before the reset, since clearing the state is what makes the screen
    /// go away.
    @MainActor
    func redialLastCall() {
        guard case .ended = callPhase else { return }

        let handle = callHandle
        let name = callerName
        let image = callerProfileImage
        let wantsVideo = hasVideo
        let conversation = conversationId
        // Redial under the same identity the first attempt used.
        let peerUserId = remoteParticipants.first?.userId

        dismissEndedCall()

        guard let handle else { return }
        startOutgoingCall(
            to: handle,
            hasVideo: wantsVideo,
            name: name,
            image: image,
            conversationId: conversation,
            userId: peerUserId
        )
    }

    // MARK: - Tones

    /// Ringback while an outgoing call is ringing at the other end.
    ///
    /// Incoming calls are rung by CallKit with the system ringtone — playing our
    /// own on top would fight it and pull the session out of `.voiceChat`.
    /// Started only after the SFU produce path has begun, so the tone does not
    /// race the first `call-produce`.
    private func startRingbackTone() {
        ringback.start()
        Task { [weak self] in
            guard let self else { return }
            let speaker = await MainActor.run { self.isOnSpeaker }
            try? await self.applyAudioRoute(isSpeakerOn: speaker)
        }
    }

    private func stopAllTones() {
        ringback.stop()
    }


    // MARK: - Helpers
    /// Legacy accessor for callers that need a string whatever happens (call log
    /// persistence). Identity decisions must use `isSelfPeerId` instead — this
    /// still answers `"unknown"`, which is a label, never a usable id.
    func getCurrentUserId() -> String {
        currentUserIdentifier ?? "unknown"
    }
    
    // MARK: - App State
    func handleAppBackground() {}
    func handleAppForeground() {}
    
    deinit {
        callTimer?.invalidate()
        inboundEventTask?.cancel()
        heartbeatTask?.cancel()
        ringTimeoutTask?.cancel()
        pingTask?.cancel()
        reconnectTask?.cancel()
        audioLevelTask?.cancel()
        stallTask?.cancel()
        ringback.stop()
    }
}

// MARK: - CallKitManagerDelegate
extension VoipManager: CallKitManagerDelegate {
    func onIncoming(uuid: UUID, handle: String, hasVideo: Bool) {
        DispatchQueue.main.async {
            self.state = "Incoming from \(self.displayName)"
            self.activeCallUUID = uuid
            self.callHandle = handle
            self.hasVideo = hasVideo
            self.isVideoCall = hasVideo
            self.isIncoming = true
            self.callPhase = .incomingRinging(handle: self.displayName, isVideo: hasVideo)
        }
    }
    
    func onAnswered(uuid: UUID) {
        DispatchQueue.main.async {
            // CallKit lock-screen answer and in-app Accept both land here.
            // Join must run for media; `markAnswered` alone left produce dead.
            self.beginJoinAfterAnswer(uuid: uuid)
        }
    }
    
    func onEnded(uuid: UUID) {
        DispatchQueue.main.async {
            guard self.activeCallUUID == uuid else { return }

            // CallKit closed the system call. On Simulator this often fires
            // right after an incoming ring starts — without a reject the
            // caller keeps ringing until the server's 45s timeout.
            self.notifyServerOfLocalEndIfNeeded()

            // `endCall` / `declineCall` / `finishCall` already moved us to
            // `.ended`. Only finish teardown when CallKit killed a call that was
            // still live.
            switch self.callPhase {
            case .idle, .ended:
                return
            default:
                break
            }

            self.cancelInFlightCallWork()
            self.persistCallToHistory(outcome: self.outcomeForLocalHangUp())
            self.stopCallTimer()
            self.stopAllTones()
            self.stopMedia()
            self.stopRingTimeout()
            self.callPhase = .ended
            self.state = "Call ended"
            self.scheduleEndedDismiss()
        }
    }
    
    func onStarted(uuid: UUID, handle: String) {
        DispatchQueue.main.async {
            // CallKit "started" is not the same as the peer answering. Outgoing
            // connect is driven by MQTT (`CALL_ANSWERED` / peer joined); starting
            // the duration timer here made the clock run while still ringing.
            guard !self.callWasAnswered else { return }
            self.state = "Calling \(self.displayName)"
        }
    }
    
    func onMuted(uuid: UUID, isMuted: Bool) {
        DispatchQueue.main.async {
            self.isMuted = isMuted
        }
    }
    
    func onHold(uuid: UUID, isOnHold: Bool) {
        DispatchQueue.main.async {}
    }

    func onAudioSessionActivated(_ isActivated: Bool) {
        Task { [weak self] in
            await self?.mediaEngine?.setAudioSessionActivated(isActivated)
            guard let self else { return }
            let pending: InboundCallEventDTO? = await MainActor.run {
                self.isCallKitAudioActivated = isActivated
                guard isActivated else { return nil }
                let event = self.pendingMediaSetupEvent
                self.pendingMediaSetupEvent = nil
                return event
            }
            if let pending {
                #if DEBUG
                print("[CallMedia] CallKit audio up — flushing deferred startMedia (\(pending.eventType))")
                #endif
                await MainActor.run { self.startMedia(with: pending) }
            }
            guard isActivated else { return }
            let speaker = await MainActor.run { () -> Bool in
                if self.requiresLoudspeakerPolicy {
                    self.isOnSpeaker = true
                    UIDevice.current.isProximityMonitoringEnabled = false
                    return true
                }
                UIDevice.current.isProximityMonitoringEnabled = !self.isOnSpeaker
                return self.isOnSpeaker
            }
            do {
                try await self.applyAudioRoute(isSpeakerOn: speaker)
            } catch {
                #if DEBUG
                print("Could not reapply audio route after activation: \(error)")
                #endif
            }
        }
    }

    /// Reasserts the current earpiece/speaker preference on the live session.
    ///
    /// CallKit can reactivate the session after the user already tapped speaker;
    /// reapplying here keeps the UI state and the real route in sync.
    ///
    /// Delegated to the engine: the output override has to be taken under
    /// WebRTC's configuration lock, and this module does not link WebRTC.
    private func applyAudioRoute(isSpeakerOn: Bool) async throws {
        try await mediaEngine?.setSpeakerEnabled(isSpeakerOn)
    }

    /// Loudspeaker + no proximity (video calls and group calls).
    /// Classic 1:1 audio keeps earpiece + proximity when speaker is off.
    private func applyLoudspeakerPolicy(enabled: Bool) {
        let run: () -> Void = { [weak self] in
            guard let self else { return }
            if enabled {
                self.isOnSpeaker = true
                UIDevice.current.isProximityMonitoringEnabled = false
            } else if !self.requiresLoudspeakerPolicy {
                UIDevice.current.isProximityMonitoringEnabled = !self.isOnSpeaker
            }

            guard self.isMediaRunning || self.isCallKitAudioActivated else { return }
            let speaker = self.isOnSpeaker
            Task { [weak self] in
                try? await self?.applyAudioRoute(isSpeakerOn: speaker)
            }
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    private func clearProximityMonitoring() {
        let run = { UIDevice.current.isProximityMonitoringEnabled = false }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }
    
    // MARK: - Outcome resolution

    /// Outcome when this device hangs up.
    ///
    /// Answered → a real conversation happened. Otherwise it depends on who
    /// started it: hanging up on a call that is still ringing here means the
    /// user missed it, while hanging up on one we placed means we cancelled it.
    private func outcomeForLocalHangUp() -> CallOutcome {
        if callWasAnswered { return .answered }
        return isIncoming ? .missed : .cancelled
    }

    /// Outcome when the other end hangs up.
    ///
    /// If it was never answered, an inbound call stopped ringing before we
    /// reached it (missed), and an outbound one rang out unanswered (noAnswer).
    private func outcomeForRemoteHangUp() -> CallOutcome {
        if callWasAnswered { return .answered }
        return isIncoming ? .missed : .noAnswer
    }

    // MARK: - Call History Persistence

    /// Records a finished call.
    ///
    /// Writes two things, matching `CallLogModel`'s own contract: a call log for
    /// the Calls tab, and a message in the conversation thread. Every call that
    /// reaches a terminal state is logged, connected or not — that is what makes
    /// missed, declined and cancelled calls visible in the history.
    private func persistCallToHistory(outcome: CallOutcome) {
        guard !callHistoryPersisted else { return }
        callHistoryPersisted = true

        // Snapshot everything now: the call state is reset shortly after this,
        // and resolving the conversation is asynchronous.
        let snapshot = CallSnapshot(
            // The server's id wins where it is known: a record filed under a
            // client-invented id can never be matched to what is read back, so
            // the same call would show up twice. The room id is the fallback for
            // a call that ended before any event named it.
            callId: serverCallId?.lowercased()
                ?? activeCallUUID?.lowercasedString
                ?? UUID().lowercasedString,
            handle: callHandle ?? "Unknown",
            contactName: callerName ?? (callHandle ?? "Unknown"),
            contactImage: callerProfileImage,
            hasVideo: hasVideo,
            isIncoming: isIncoming,
            outcome: outcome,
            durationSeconds: outcome.didConnect ? callDuration : 0,
            startedAt: callStartTime ?? Date(),
            endedAt: Date(),
            currentUserId: getCurrentUserId(),
            knownConversationId: conversationId,
            participants: callRoster()
        )

        Task { [weak self] in
            guard let self else { return }
            let resolvedConversationId = await self.resolveConversationId(for: snapshot)
            await self.saveCallLog(snapshot, conversationId: resolvedConversationId)
            await self.appendCallToConversation(snapshot, conversationId: resolvedConversationId)
        }
    }

    /// Finds or creates the local conversation this call belongs to.
    ///
    /// Same contract as sending a first message: look up by phone, otherwise
    /// mint a local UUID and persist a DM shell (1:1 only). The wire id is still
    /// resolved separately via `outboundConversationId` (`serverId` when linked).
    private func resolveConversationId(for snapshot: CallSnapshot) async -> String? {
        await ensureLocalConversationId(
            existing: snapshot.knownConversationId,
            handle: snapshot.handle,
            name: snapshot.contactName,
            image: snapshot.contactImage,
            userId: snapshot.participants.first?.userId ?? snapshot.handle,
            // Multi-party without a known group conversation must not invent a
            // 1:1 DM with the first peer.
            allowCreate: snapshot.participants.count <= 1
        )
    }

    /// Ensures a local conversation id exists for a 1:1 call (create if needed).
    ///
    /// `existing` may be a local PK or a wire/server id from `CALL_INITIATED` /
    /// the dialer. Unknown wire ids become the new local PK so both sides share
    /// one conversation id until a `serverId` link exists.
    private func ensureLocalConversationId(
        existing: String?,
        handle: String,
        name: String?,
        image: String?,
        userId: String,
        allowCreate: Bool = true
    ) async -> String? {
        if let existing, !existing.isEmpty,
           let local = await resolveLocalConversationId(forWireOrLocal: existing) {
            return local
        }

        // Only look up / create DMs for true 1:1. Ad-hoc groups must not reuse
        // the first peer's personal conversation.
        guard allowCreate else {
            return (existing?.isEmpty == false) ? existing : nil
        }

        // Prefer an existing DM by phone over minting a second chat when the
        // wire id is unknown on this device.
        if let found = await findExistingDirectConversationId(phone: handle) {
            return found
        }

        let id = (existing?.isEmpty == false) ? existing! : UUID().lowercasedString
        return await createConversationShell(
            id: id,
            handle: handle,
            name: name,
            image: image,
            userId: userId
        )
    }

    /// Maps a wire or local conversation id to the local primary key, if known.
    private func resolveLocalConversationId(forWireOrLocal id: String) async -> String? {
        guard let discussionsUseCases else { return nil }

        do {
            let discussions = try await discussionsUseCases.getDiscussions.execute() ?? []
            if discussions.contains(where: { $0.conversationId == id }) {
                return id
            }
            guard let discussionRepository else { return nil }
            for discussion in discussions {
                let wire = await discussionRepository.outboundConversationId(
                    for: discussion.conversationId
                )
                if wire == id {
                    return discussion.conversationId
                }
            }
        } catch {
            #if DEBUG
            print("[CallMedia] Failed to resolve conversation id \(id): \(error)")
            #endif
        }
        return nil
    }

    /// Persists an empty DM shell (no message bubble) under `id`.
    private func createConversationShell(
        id: String,
        handle: String,
        name: String?,
        image: String?,
        userId: String
    ) async -> String {
        guard let discussionsUseCases else { return id }

        let shell = MessageDataItem(
            codeMessage: "",
            message: MessageContent(),
            createdAt: Date()
        )
        let discussion = DiscussionChatItem(
            lastMessage: shell,
            conversationId: id,
            contact: ContactChannel(
                userName: name ?? handle,
                phone: handle,
                image: image,
                isBlocked: false,
                isGroup: false,
                id: "",
                userId: userId
            )
        )

        do {
            try await discussionsUseCases.createDiscussion.execute(discussion: discussion)
            await MainActor.run {
                NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
            }
            #if DEBUG
            print("[CallMedia] created local conversation \(id) for call with \(handle)")
            #endif
        } catch {
            #if DEBUG
            print("[CallMedia] Failed to create conversation for call: \(error)")
            #endif
        }
        return id
    }

    private func findExistingDirectConversationId(phone: String) async -> String? {
        guard let discussionsUseCases else { return nil }
        let digits = phone.onlyDigits
        guard !digits.isEmpty else { return nil }

        do {
            let discussions = try await discussionsUseCases.getDiscussions.execute() ?? []
            return discussions.first {
                ($0.contact?.isGroup ?? false) == false
                    && ($0.contact?.phone.onlyDigits ?? "") == digits
            }?.conversationId
        } catch {
            #if DEBUG
            print("Failed to look up conversation for call: \(error)")
            #endif
            return nil
        }
    }

    /// Backend conversation id for `call-offer` (`serverId` when linked).
    ///
    /// Local history keeps using the room's local id; only the MQTT payload
    /// needs the server id so core can attach the call to the right conversation.
    private func outboundConversationId(for localConversationId: String?) async -> String? {
        guard let localConversationId, !localConversationId.isEmpty else { return nil }
        guard let discussionRepository else { return localConversationId }
        return await discussionRepository.outboundConversationId(for: localConversationId)
    }

    /// Everything needed to write history, captured before the call state resets.
    /// Everyone on the call except this device, in the order they joined.
    ///
    /// The party originally dialled comes first, then anyone invited later.
    /// Recorded so the history can offer the same group again without the user
    /// re-picking them one by one.
    private func callRoster() -> [CallInvitee] {
        var roster: [CallInvitee] = []

        if let handle = callHandle {
            roster.append(
                CallInvitee(
                    userId: handle,
                    name: callerName ?? handle,
                    phone: handle
                )
            )
        }

        let known = Set(roster.map { $0.phone.onlyDigits })
        roster.append(contentsOf: invitedParticipants.filter { !known.contains($0.phone.onlyDigits) })

        return roster
    }

    private struct CallSnapshot {
        let callId: String
        let handle: String
        let contactName: String
        let contactImage: String?
        let hasVideo: Bool
        let isIncoming: Bool
        let outcome: CallOutcome
        let durationSeconds: Int
        let startedAt: Date
        let endedAt: Date
        let currentUserId: String
        let knownConversationId: String?
        /// Everyone who was on the call besides this device — the party dialled
        /// plus anyone invited afterwards. This is what lets history offer
        /// "call these people again".
        let participants: [CallInvitee]
    }

    private func saveCallLog(_ snapshot: CallSnapshot, conversationId: String?) async {
        guard let callUseCases else {
            #if DEBUG
            print("Call log dropped: callUseCases not injected")
            #endif
            return
        }

        let log = CallLogEntity(
            // The call's own id, so a later update of the same call replaces it
            // rather than adding a second row.
            id: snapshot.callId,
            // The remote party's account id, so redialling from history goes out
            // under the same identity the original offer used.
            userId: snapshot.participants.first?.userId,
            conversationId: conversationId,
            contactName: snapshot.contactName,
            contactPhone: snapshot.handle,
            contactAvatarURL: snapshot.contactImage,
            media: snapshot.hasVideo ? .video : .voice,
            direction: snapshot.isIncoming ? .incoming : .outgoing,
            outcome: snapshot.outcome,
            durationSeconds: snapshot.durationSeconds,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            // More than one other party makes it a group call. Recording the
            // roster is what lets history offer the same group again — it was
            // previously dropped, so every group call looked one-to-one.
            isGroupCall: snapshot.participants.count > 1,
            participantCount: max(snapshot.participants.count, 1),
            initiatedByUserId: snapshot.isIncoming ? nil : snapshot.currentUserId,
            participants: snapshot.participants.map {
                CallLogParticipant(
                    userId: $0.userId,
                    name: $0.name,
                    phone: $0.phone,
                    outcome: snapshot.outcome
                )
            }
        )

        do {
            try await callUseCases.saveCallLog.execute(log)
        } catch {
            #if DEBUG
            print("Failed to save call log: \(error)")
            #endif
        }
    }

    /// Adds the call to its conversation thread.
    ///
    /// Requires a resolved conversation id (looked up or created for 1:1 before
    /// dial / on persist). Upserts via `createDiscussion` so the bubble lands on
    /// the existing thread when the conversation already had messages.
    private func appendCallToConversation(_ snapshot: CallSnapshot, conversationId: String?) async {
        guard let discussionsUseCases, let conversationId, !conversationId.isEmpty else { return }

        // The thread only distinguishes connected from not — the precise outcome
        // lives on the call log.
        let callType: MessageTypeProps
        if snapshot.outcome.didConnect {
            callType = snapshot.hasVideo ? .CALL_VIDEO : .CALL_AUDIO
        } else {
            callType = snapshot.hasVideo ? .MISSING_CALL_VIDEO : .MISSING_CALL_AUDIO
        }

        // The whole roster, not just the party dialled: a group call that
        // recorded one participant is indistinguishable from a one-to-one call
        // when the bubble is tapped later.
        let isGroup = snapshot.participants.count > 1
        let callContent = CallContent(
            callType: snapshot.hasVideo ? .video : .audio,
            callScope: isGroup ? .group : .private,
            participants: snapshot.participants.map {
                ParticipantItem(
                    name: $0.name,
                    phone: $0.phone,
                    userId: $0.userId,
                    startedAt: snapshot.startedAt,
                    endAt: snapshot.endedAt
                )
            },
            initiator: snapshot.isIncoming ? snapshot.handle : snapshot.currentUserId,
            outcome: snapshot.outcome.rawValue
        )

        // Filed under the call's id, which is the server's whenever one was
        // seen. `store.save` upserts on it, so if the backend ever delivers its
        // own copy of this call it replaces this row instead of adding a second
        // bubble for the same call.
        let msg = MessageDataItem(
            codeMessage: snapshot.callId,
            senderId: snapshot.isIncoming ? snapshot.handle : snapshot.currentUserId,
            senderAvatar: snapshot.isIncoming ? snapshot.contactImage : CurrentSessionInfo.shared.userProfile,
            senderPhone: snapshot.isIncoming ? snapshot.handle : CurrentSessionInfo.shared.userPhoneNumber,
            senderName: snapshot.isIncoming ? snapshot.contactName : CurrentSessionInfo.shared.userName,
            receiverId: snapshot.isIncoming ? snapshot.currentUserId : snapshot.handle,
            groupId: "",
            typeMessage: callType,
            message: MessageContent(
                text: snapshot.outcome.didConnect
                    ? "\(snapshot.hasVideo ? "Video" : "Voice") call · \(formatDuration(snapshot.durationSeconds))"
                    : "Missed \(snapshot.hasVideo ? "video" : "voice") call",
                call: callContent
            ),
            forwarded: false,
            // A call is not a sent message: it has no delivery lifecycle. This
            // value is never rendered — `isCallEvent` suppresses the ticks — and
            // is terminal so the unsent/retry paths ignore it.
            status: .SEEN,
            isMoney: false,
            createdAt: snapshot.startedAt
        )

        let conversation = DiscussionChatItem(
            lastMessage: msg,
            conversationId: conversationId,
            contact: ContactChannel(
                userName: snapshot.contactName,
                phone: snapshot.handle,
                image: snapshot.contactImage ?? "",
                isBlocked: false,
                isGroup: false,
                id: snapshot.handle
            )
        )

        do {
            try await discussionsUseCases.createDiscussion.execute(discussion: conversation)
            NotificationCenter.default.post(
                name: .callHistoryPersisted,
                object: nil,
                userInfo: [
                    "message": msg,
                    "conversationId": conversationId
                ]
            )
        } catch {
            #if DEBUG
            print("Failed to persist call history: \(error)")
            #endif
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }

    @MainActor
    private func resetCallState() {
        cancelInFlightCallWork()
        activeCallUUID = nil
        callHandle = nil
        callerName = nil
        callerProfileImage = nil
        isIncoming = false
        hasVideo = false
        isVideoCall = false
        isLocalPreviewReady = false
        isMuted = false
        isOnSpeaker = false
        clearProximityMonitoring()
        isMinimized = false
        conversationId = nil
        invitedParticipants.removeAll()
        remoteParticipants.removeAll()
        joinedPeerKeys.removeAll()
        ringingPeerKeys.removeAll()
        mutedPeerIds.removeAll()
        cameraOffPeerIds.removeAll()

        // CALL_ENDED / peer left / hang-up. The broadcast extension is a separate
        // process and outlives the call unless it is told otherwise.
        if isSharingScreen {
            Task { @MainActor in await endScreenShare() }
        }
        stopScreenShareBridge()
        isSharingScreen = false
        screenShareCameraState.clear()
        screenSharingPeerId = nil
        videoTracksByPeer.removeAll()
        consumerOwners.removeAll()
        callStartTime = nil
        callConnectedAt = nil
        callWasAnswered = false
        isAnswerJoinInFlight = false
        callHistoryPersisted = false
        hasNotifiedServerOfEnd = false
        isCalleeRinging = false
        isRoomEstablished = false
        hasRetriedJoin = false
        serverRingTimeout = nil
        clearRemoteProducerGateState()
        pendingRemoteProducers.removeAll()
        consumeRetryCounts.removeAll()
        producerOwnerByProducerId.removeAll()
        serverCallId = nil
        isRemoteOnHold = false
        endReason = .hungUp
        pendingInvitees = []
        isMediaRunning = false
        isCallKitAudioActivated = false
        pendingMediaSetupEvent = nil
        Task { @MainActor in
            self.stopAllLocalVideoPreview()
            self.localVideoTrack = nil
            // Hands and reactions belong to the room that just ended, and both
            // live on the main actor with the rest of the call's view state.
            self.clearConferenceFeatureState()
        }
    }
}


// MARK: - App State
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentScreen: AppScreen = .main
    @Published var pendingCall: PendingCall?
    
    enum AppScreen {
        case main
        case callScreen
    }
    
    struct PendingCall {
        let handle: String
        let uuid: UUID
        let isIncoming: Bool
    }
    
    private init() {}
    
    func handleCallKitActivation(handle: String, uuid: UUID, isIncoming: Bool) {
        DispatchQueue.main.async {
            self.pendingCall = PendingCall(handle: handle, uuid: uuid, isIncoming: isIncoming)
            self.currentScreen = .callScreen
        }
    }
    
    func reset() {
        pendingCall = nil
        currentScreen = .main
    }
}
