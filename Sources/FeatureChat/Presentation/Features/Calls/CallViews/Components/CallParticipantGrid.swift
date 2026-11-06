//
//  CallParticipantGrid.swift
//  FeatureChat
//
//  Everyone on the call, laid out to fit.
//
//  One component serves both call types: on a video call the tiles carry
//  camera feeds, on an audio call the same tiles show avatars. Keeping them the
//  same means a call that upgrades from audio to video does not rearrange
//  itself under the user.
//
//  Past six people the remainder collapses into a single "+N" tile — a seventh
//  tile on a phone is too small to recognise a face in, so it would cost
//  legibility for everyone without helping anyone.
//

import SwiftUI
import WaanguCoreKit

struct CallParticipantGrid: View {

    /// Everyone to show, in join order.
    let participants: [CallParticipantGridItem]
    var spacing: CGFloat = 8

    /// Beyond this the remainder becomes a single overflow tile.
    ///
    /// Six on a phone screen. The Picture-in-Picture window passes fewer: it is
    /// a couple of inches tall, so a sixth tile there is unrecognisable, and
    /// every tile it drops is one less video being decoded while the app is in
    /// the background.
    static let maxVisibleTiles = 6

    var visibleTileLimit: Int = Self.maxVisibleTiles

    private var visible: [CallParticipantGridItem] {
        participants.count > visibleTileLimit
            // One slot is given up to the overflow tile itself.
            ? Array(participants.prefix(visibleTileLimit - 1))
            : participants
    }

    private var overflowCount: Int {
        max(participants.count - visible.count, 0)
    }

    /// Total tiles including the overflow one, which drives the layout.
    private var tileCount: Int {
        visible.count + (overflowCount > 0 ? 1 : 0)
    }

    /// One column while there are at most two people — a single remote party
    /// deserves the whole screen, and two stacked reads better than two narrow
    /// columns on a phone.
    private var columns: Int {
        tileCount <= 2 ? 1 : 2
    }

    private var rows: Int {
        max(Int(ceil(Double(tileCount) / Double(columns))), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let tileWidth = (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let tileHeight = (proxy.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < visible.count {
                                tile(for: visible[index])
                                    .frame(width: tileWidth, height: tileHeight)
                            } else if index == visible.count && overflowCount > 0 {
                                CallOverflowTile(count: overflowCount)
                                    .frame(width: tileWidth, height: tileHeight)
                            } else {
                                // Keeps the last row aligned with the ones above
                                // instead of centring a lone tile.
                                Color.clear
                                    .frame(width: tileWidth, height: tileHeight)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tile(for item: CallParticipantGridItem) -> some View {
        CallParticipantTile(
            name: item.name,
            avatarURL: item.avatarURL,
            track: item.track,
            isMuted: item.isMuted,
            isSharingScreen: item.isSharingScreen,
            isMirrored: item.isLocal,
            isWaiting: item.isWaiting,
            waitingLabel: item.waitingLabel,
            isRinging: item.isRinging,
            isReconnecting: item.isReconnecting,
            reconnectingLabel: item.reconnectingLabel,
            showsName: tileCount > 1,
            audioLevel: item.audioLevel,
            color: item.color,
            hasRaisedHand: item.hasRaisedHand,
            reaction: item.reaction
        )
    }
}

/// One entry in the grid. A view-facing shape rather than a domain type, so the
/// grid does not need to know where a participant came from.
struct CallParticipantGridItem: Identifiable {
    let id: String
    let name: String
    let avatarURL: String?
    let track: (any CallVideoTrackProtocol)?
    var isMuted: Bool = false
    var isSharingScreen: Bool = false
    /// True for this device, which is the only tile that gets mirrored.
    var isLocal: Bool = false
    /// Invited but not yet in the SFU room — show a ringing/waiting card.
    var isWaiting: Bool = false
    /// Localised status under the avatar while `isWaiting` (e.g. "Calling...").
    var waitingLabel: String? = nil
    /// Waiting *and* known to be alerted — their device is ringing, rather than
    /// the invite merely having been sent.
    var isRinging: Bool = false
    /// In the room, but their media has stopped arriving — show "Reconnecting…"
    /// instead of the last frame they sent.
    var isReconnecting: Bool = false
    /// Localised status under the avatar while `isReconnecting`.
    var reconnectingLabel: String? = nil
    /// How loudly this participant is speaking right now, `0…1`.
    var audioLevel: Float = 0
    /// This participant's own colour, stable for the whole call.
    var color: Color = .white
    /// They have asked to speak and are in the queue (§16.1).
    var hasRaisedHand: Bool = false
    /// An emoji they just sent, while it is still animating (§16.2).
    var reaction: String? = nil
}
