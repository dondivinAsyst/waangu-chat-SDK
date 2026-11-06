//
//  CallLocalParticipantStage.swift
//  FeatureChat
//
//  Local camera-off surface — same look as the remote mute stage.
//

import SwiftUI

struct CallLocalParticipantStage: View {

    let name: String?
    let avatarURL: String?
    var isMuted: Bool = false
    var isCompact: Bool = false
    /// How loudly this device is speaking, `0…1`.
    var audioLevel: Float = 0
    /// This device's own colour, matching its tile in the group grid.
    var color: Color = .white

    var body: some View {
        CallRemoteParticipantStage(
            name: name,
            avatarURL: avatarURL,
            isMuted: isMuted,
            showsWaveform: true,
            isCompact: isCompact,
            audioLevel: audioLevel,
            color: color
        )
    }
}
