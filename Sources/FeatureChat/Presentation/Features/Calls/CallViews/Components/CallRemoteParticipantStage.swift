//
//  CallRemoteParticipantStage.swift
//  FeatureChat
//
//  Camera-off participant surface (remote or local): avatar + waveform.
//  Compact mode matches the PiP tile; full mode fills the main stage.
//

import SwiftUI
import WaanguSharedUI

struct CallRemoteParticipantStage: View {

    let name: String?
    let avatarURL: String?
    var isMuted: Bool = false
    var showsWaveform: Bool = true
    var isCompact: Bool = false
    /// How loudly this person is speaking, `0…1`.
    var audioLevel: Float = 0
    /// Their own colour, so the 1:1 stage matches their tile in the grid.
    var color: Color = .white
    /// Their media stopped arriving — dims them and drops the waveform, which
    /// would otherwise keep moving under somebody who is no longer being heard.
    ///
    /// Says nothing in words: this stage only ever shows the sole remote, and
    /// that case puts "Reconnecting…" in the header in place of the duration.
    var isReconnecting: Bool = false

    private var avatarDiameter: CGFloat { isCompact ? 56 : 190 }
    private var stackSpacing: CGFloat { isCompact ? 8 : 18 }

    var body: some View {
        ZStack {
            CallTheme.Palette.canvasElevated

            VStack(spacing: stackSpacing) {
                CircularProfileImageView(avatarURL, size: .custom(avatarDiameter))
                    .opacity(isReconnecting ? 0.55 : 1)

                if !isReconnecting, showsWaveform, !isMuted {
                    CallAudioWaveformView(level: audioLevel, tint: color)
                        .scaleEffect(isCompact ? 0.55 : 1)
                }

                if !isCompact, let name, !name.isEmpty {
                    Text(name)
                        .font(CallTheme.TextStyle.remoteNameLarge)
                        .foregroundStyle(CallTheme.Palette.remoteName)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}
