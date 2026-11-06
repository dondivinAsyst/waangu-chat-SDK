//
//  VoipManager+ParticipantGrid.swift
//  FeatureChat
//
//  Turns call state into the rows a grid can draw.
//
//  Kept out of the views: assembling who is on the call, whose camera is on and
//  who is muted is presentation logic, and a view that did it itself would have
//  to know about tracks, peer keys and roster bookkeeping.
//

import Foundation
import SwiftUI
import WaanguCoreKit

extension VoipManager {

    /// Everyone on the call except this device — deduped, never including self.
    /// - Parameter waitingLabel: localised "Calling..." for invitees not yet joined.
    /// - Parameter ringingLabel: localised "Ringing..." for invitees the server is
    ///   already alerting. Falls back to `waitingLabel` when absent, so a caller
    ///   that only needs the roster does not have to supply both.
    /// - Parameter unknownLabel: localised "Unknown" for a peer we cannot name.
    func remoteGridItems(
        waitingLabel: String,
        unknownLabel: String,
        ringingLabel: String = "",
        reconnectingLabel: String = ""
    ) -> [CallParticipantGridItem] {
        dedupedRemoteParticipantsForGrid().map { participant in
            let waiting = isPeerWaiting(participant)
            // Invited, and their phone is known to be ringing — a different
            // thing to say than "Calling…", which only means we asked.
            let ringing = waiting && isPeerRinging(participant)
            // Somebody who has not joined yet is not reconnecting — they have
            // never sent anything to stall in the first place.
            let reconnecting = !waiting && isPeerReconnecting(participant)
            return CallParticipantGridItem(
                id: stableGridId(for: participant),
                name: displayNameForGrid(participant, unknownLabel: unknownLabel),
                avatarURL: avatarURL(for: participant),
                // Waiting peers have no media yet. Joined peers who turned the
                // camera off keep a paused track — hide it so the last frame
                // does not freeze on the tile. A stalled peer is the same
                // problem arriving a different way: the track is still live and
                // still holding the last frame it decoded, which is exactly the
                // frozen picture the user reads as "still connected".
                // A peer who is sharing their screen has *paused their camera*
                // to do it, and `CALL_PRODUCER_STATE` carries no `mediaType`
                // (CALL-INTEGRATION.md §9.2 :652-664) — so "video paused" from a
                // sharer is indistinguishable from them turning the camera off.
                // Suppressing the track on that signal hid the screen share too,
                // which is the one thing they are deliberately sending.
                track: waiting || reconnecting
                    || (isPeerCameraOff(participant) && !isPeerSharingScreen(participant))
                    ? nil
                    : videoTrack(for: participant),
                isMuted: waiting ? false : isPeerMuted(participant),
                isSharingScreen: waiting ? false : isPeerSharingScreen(participant),
                isWaiting: waiting,
                waitingLabel: waiting
                    ? (ringing && !ringingLabel.isEmpty ? ringingLabel : waitingLabel)
                    : nil,
                isRinging: ringing,
                isReconnecting: reconnecting,
                reconnectingLabel: reconnecting ? reconnectingLabel : nil,
                // Their level is whatever last arrived — freezing the waveform
                // mid-bounce would look like they were still talking.
                audioLevel: waiting || reconnecting ? 0 : audioLevel(for: participant),
                color: CallParticipantColor.color(forKey: stableGridId(for: participant)),
                // Both are keyed on the same normalised id the queue and the
                // reaction feed store, so a tile shows only its own.
                hasRaisedHand: raisedHands.contains(stableGridId(for: participant)),
                reaction: activeReactions.last {
                    $0.peerId == stableGridId(for: participant)
                }?.emoji
            )
        }
    }

    /// This device's own tile, for the group layout where the local preview sits
    /// in the grid rather than floating over it.
    /// - Parameter youLabel: localised "You" — never the account display name.
    func localGridItem(youLabel: String) -> CallParticipantGridItem {
        let profile = CurrentSessionInfo.shared.userProfile
        return CallParticipantGridItem(
            id: "local",
            name: youLabel,
            avatarURL: profile.isEmpty ? nil : profile,
            track: hasVideo ? localVideoTrack : nil,
            isMuted: isMuted,
            isLocal: true,
            audioLevel: audioLevelsByPeerKey[Self.localAudioLevelKey] ?? 0,
            color: CallParticipantColor.color(forKey: Self.localAudioLevelKey),
            hasRaisedHand: isHandRaised,
            reaction: activeReactions.last { $0.peerId == Self.localAudioLevelKey }?.emoji
        )
    }

    /// The whole call: everyone else first, this device last, which keeps the
    /// self tile in a stable place as people come and go.
    func callGridItems(
        youLabel: String,
        waitingLabel: String,
        unknownLabel: String,
        ringingLabel: String = "",
        reconnectingLabel: String = ""
    ) -> [CallParticipantGridItem] {
        remoteGridItems(
            waitingLabel: waitingLabel,
            unknownLabel: unknownLabel,
            ringingLabel: ringingLabel,
            reconnectingLabel: reconnectingLabel
        ) + [localGridItem(youLabel: youLabel)]
    }

    /// More than one other person on the call (joined or still ringing).
    var isGroupCall: Bool {
        dedupedRemoteParticipantsForGrid().count > 1
    }

    /// Everyone on the call including this device.
    ///
    /// Counted off the deduped roster, the same list `isGroupCall` reads. Taken
    /// off the raw one it disagreed with itself: a seed-plus-upsert clone made a
    /// three-way call announce four participants.
    var participantCount: Int {
        dedupedRemoteParticipantsForGrid().count + 1
    }

    /// The sole remote party in a one-to-one call.
    var oneToOneRemoteParticipant: CallInvitee? {
        guard !isGroupCall else { return nil }
        return dedupedRemoteParticipantsForGrid().first
    }

    /// Live remote camera for 1:1, respecting an explicit camera-off signal.
    ///
    /// A stalled peer is treated exactly like camera-off: their track is still
    /// alive and still holding the last frame it decoded, so leaving it on
    /// screen shows a frozen picture of somebody who is no longer there.
    func oneToOneRemoteVideoTrack() -> (any CallVideoTrackProtocol)? {
        guard !isGroupCall else { return nil }

        if let participant = oneToOneRemoteParticipant {
            if isPeerCameraOff(participant) || isPeerReconnecting(participant) { return nil }
            if let track = videoTrack(for: participant) { return track }
        }

        // Fallback when `videoTracksByPeer` missed attribution (consumer ack
        // names the local peer, not the producer owner).
        guard remoteParticipants.count <= 1 else { return nil }
        if let participant = oneToOneRemoteParticipant,
           isPeerCameraOff(participant) || isPeerReconnecting(participant) {
            return nil
        }
        return remoteVideoTracks.values.first
    }

    /// Whether the sole remote in a 1:1 call has dropped out of the media path.
    var isOneToOneRemoteReconnecting: Bool {
        guard let participant = oneToOneRemoteParticipant else { return false }
        return isPeerReconnecting(participant)
    }

    /// How loudly the sole remote in a 1:1 call is speaking, `0…1`.
    ///
    /// Zero while they are stalled: a consumer that stopped receiving keeps
    /// reporting the last level it measured, which would leave the waveform
    /// bouncing under someone whose audio stopped arriving seconds ago.
    var oneToOneAudioLevel: Float {
        guard let participant = oneToOneRemoteParticipant else { return 0 }
        guard !isPeerReconnecting(participant) else { return 0 }
        return audioLevel(for: participant)
    }

    /// That peer's colour, so the 1:1 stage matches the tile they would have in
    /// a group — the same person keeps one colour as a call grows or shrinks.
    var oneToOneColor: Color {
        guard let participant = oneToOneRemoteParticipant else { return .white }
        return CallParticipantColor.color(forKey: stableGridId(for: participant))
    }

    /// This device's own colour and level, for the local preview stage.
    var localAudioLevel: Float {
        audioLevelsByPeerKey[Self.localAudioLevelKey] ?? 0
    }

    var localColor: Color {
        CallParticipantColor.color(forKey: Self.localAudioLevelKey)
    }

    /// Whether the remote peer in a 1:1 call has muted their microphone.
    var isOneToOneRemoteMuted: Bool {
        guard let participant = oneToOneRemoteParticipant else { return false }
        return isPeerMuted(participant)
    }

    // There is deliberately no "the one track PiP shows" here any more. Picking
    // a single participant for the window is what made a group call look like a
    // one-to-one from outside the app; `CallPiPStageContent` draws the whole
    // stage off `remoteGridItems` instead.

    /// Whether a consumable remote video track exists for the 1:1 peer.
    var hasRemoteVideoConsumer: Bool {
        oneToOneRemoteVideoTrack() != nil
    }

    /// Whether anyone on the call is sharing their screen.
    ///
    /// Answered from call state rather than by building grid items, so a view
    /// that only needs the yes/no does not have to supply display labels.
    var isAnyoneSharingScreen: Bool {
        screenSharingPeerId != nil
    }

    /// The participant currently sharing their screen, if any.
    func screenSharingParticipant(unknownLabel: String) -> CallParticipantGridItem? {
        remoteGridItems(waitingLabel: "", unknownLabel: unknownLabel)
            .first { $0.isSharingScreen }
    }

    /// Profile image when we know one — the person this call was placed to or
    /// from, and nobody else.
    ///
    /// Identity only. This used to hand the picture to whoever happened to be
    /// the sole remote, which is wrong twice over: a group call passes through
    /// a single-remote moment while people are still joining, so the avatar
    /// landed on an arbitrary peer and stayed there.
    private func avatarURL(for participant: CallInvitee) -> String? {
        guard let image = callerProfileImage, !image.isEmpty else { return nil }

        let handleKey = callHandle.map { participantKey($0) }
        let matchesHandle = handleKey.map {
            participantKey(participant.userId) == $0
                || participantKey(participant.phone) == $0
        } ?? false

        let matchesCallerName = participant.name.caseInsensitiveCompare(displayName) == .orderedSame
        return (matchesHandle || matchesCallerName) ? image : nil
    }

    /// The title for a one-to-one call: the person who is actually on it.
    ///
    /// Resolved from the live roster, not from `displayName`. `displayName` is
    /// fixed when the call is placed, so once a group shrank back to two people
    /// the header named whoever the call had originally been to — while the tile
    /// underneath showed the peer who had stayed.
    ///
    /// Falls back to `displayName` only before anyone is on the roster, which is
    /// the outgoing-ringing moment where it is the only name we have.
    func oneToOneTitle(unknownLabel: String) -> String {
        guard let participant = oneToOneRemoteParticipant else { return displayName }
        return displayNameForGrid(participant, unknownLabel: unknownLabel)
    }

    /// Remotes for the grid: no self, one row per identity.
    private func dedupedRemoteParticipantsForGrid() -> [CallInvitee] {
        var result: [CallInvitee] = []
        for participant in remoteParticipants {
            if isSelfPeerId(participant.userId) || isSelfPeerId(participant.phone) {
                continue
            }
            if let index = result.firstIndex(where: {
                VoipManager.rowsShareIdentity($0, participant)
            }) {
                let existing = result[index]
                // Only a name we actually hold may overwrite one that is still a
                // bare id — never a placeholder.
                if let betterName = bestKnownName(for: participant),
                   participantKey(existing.name) == participantKey(existing.userId)
                    || participantKey(existing.name) == participantKey(existing.phone) {
                    result[index] = CallInvitee(
                        userId: existing.userId,
                        name: betterName,
                        phone: existing.phone.isEmpty ? participant.phone : existing.phone
                    )
                }
            } else {
                result.append(participant)
            }
        }
        return result
    }

    private func stableGridId(for participant: CallInvitee) -> String {
        let userKey = participantKey(participant.userId)
        if !userKey.isEmpty { return userKey }
        return participantKey(participant.phone)
    }

    /// What to call this peer on their tile.
    ///
    /// In order: the name saved in the address book, then whatever username the
    /// server sent, then their number — and `unknownLabel` when none of those
    /// exist. A raw peer id is never shown; it is an internal identifier the
    /// user has no way to recognise, and it used to reach the screen whenever
    /// the server sent no username.
    func displayNameForGrid(_ participant: CallInvitee, unknownLabel: String) -> String {
        bestKnownName(for: participant) ?? unknownLabel
    }

    /// Names one entry in the raised-hands queue.
    ///
    /// The queue stores normalised peer keys because that is what the tiles are
    /// keyed on; the host's list needs the person behind the key. A raw id is
    /// never shown — `unknownLabel` stands in when the roster does not name them.
    func displayNameForRaisedHand(_ peerKey: String, youLabel: String, unknownLabel: String) -> String {
        if peerKey == participantKey(getCurrentUserId()) { return youLabel }
        guard let participant = remoteParticipants.first(where: {
            participantKey($0.userId) == peerKey || participantKey($0.phone) == peerKey
        }) else {
            return unknownLabel
        }
        return displayNameForGrid(participant, unknownLabel: unknownLabel)
    }

    /// The best name we hold for this peer, or nil when we hold none.
    ///
    /// Separate from `displayNameForGrid` because the roster dedupe needs to ask
    /// "do we know a name for this row" — handing it a localised "Unknown" there
    /// would let that label win over a real name arriving later.
    private func bestKnownName(for participant: CallInvitee) -> String? {
        if let saved = contactName(forPeerId: participant.userId)
            ?? contactName(forPeerId: participant.phone) {
            return saved
        }

        let name = participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty,
           participantKey(name) != participantKey(participant.userId),
           participantKey(name) != participantKey(participant.phone) {
            return name
        }

        let phone = participant.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty, participantKey(phone) != participantKey(participant.userId) {
            return phone
        }

        return nil
    }
}
