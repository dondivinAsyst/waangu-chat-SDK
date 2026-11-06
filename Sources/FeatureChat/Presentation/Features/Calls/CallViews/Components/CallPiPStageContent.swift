//
//  CallPiPStageContent.swift
//  FeatureChat
//
//  What the Picture-in-Picture window draws: the call, not one feed from it.
//
//  The window used to be handed a single `UIView` built from one track — the
//  screen sharer, or whoever happened to be the first peer with a camera. On a
//  group call that meant the user left the app and took one participant with
//  them, with no sign the others were still there.
//
//  This mirrors the stage `CallScreen` picks instead, off the same grid items,
//  so the tiles carry the names, mute badges, waveforms, raised hands and
//  waiting cards they carry inline.
//
//  Every track inside is drawn on the Picture-in-Picture surface rather than the
//  inline Metal one — see `CallVideoRenderingMode`. Getting that wrong does not
//  fail loudly; the window simply freezes on its last frame the moment the app
//  is backgrounded, which is the only time it matters.
//
//  It observes `VoipManager` directly rather than being pushed values: the
//  window outlives the call screen, so there is nothing else left to push them.
//

import SwiftUI
import WaanguCoreKit

struct CallPiPStageContent: View {

    @ObservedObject private var voip = VoipManager.shared

    /// A window this size cannot carry six faces, and each one it does carry is
    /// a video still being decoded with the app in the background.
    private static let visibleTileLimit = 4

    var body: some View {
        ZStack {
            Color(white: 0.11)

            if let sharer = voip.screenSharingParticipant(unknownLabel: "") {
                // Whoever is sharing is the whole point of looking, so they get
                // the window to themselves — the same call the stage makes.
                CallParticipantTile(
                    name: sharer.name,
                    avatarURL: sharer.avatarURL,
                    track: sharer.track,
                    isMuted: sharer.isMuted,
                    isSharingScreen: true,
                    showsName: true,
                    hasRaisedHand: sharer.hasRaisedHand,
                    reaction: sharer.reaction
                )
            } else {
                CallParticipantGrid(
                    participants: gridItems,
                    spacing: 4,
                    visibleTileLimit: Self.visibleTileLimit
                )
            }
        }
        .environment(\.callVideoRenderingMode, .pictureInPicture)
    }

    /// Everyone but this device.
    ///
    /// The self tile is dropped on purpose: the window is small, and the one
    /// person the user does not need shown to them is themselves. Status labels
    /// are left empty because a word at this size is unreadable — the tile's own
    /// avatar, waveform and badges carry the state instead.
    private var gridItems: [CallParticipantGridItem] {
        voip.remoteGridItems(waitingLabel: "", unknownLabel: "")
    }
}
