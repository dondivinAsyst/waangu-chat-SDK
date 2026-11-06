//
//  CallAudioWaveformView.swift
//  FeatureChat
//
//  Bars showing how loudly a peer is speaking, for tiles with no camera.
//

import SwiftUI

struct CallAudioWaveformView: View {

    /// How loudly this peer is speaking, `0…1`, from their RTP statistics.
    ///
    /// The bars used to be driven purely by the clock, so every tile animated
    /// identically and forever — it looked live without carrying any
    /// information, and there was no way to tell who was talking.
    var level: Float = 0

    /// Whether to animate at all. A muted or waiting peer sits flat.
    var isActive: Bool = true

    /// Keeps tiles out of phase with each other.
    ///
    /// The clock is shared, so without an offset per peer every waveform on
    /// screen moved in lockstep — the clearest tell that nothing real was
    /// behind them.
    var phaseSeed: Double = 0

    /// Colour of the bars — the participant's own, so the waveform doubles as
    /// identification.
    var tint: Color = .white

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let minHeight: CGFloat = 6
    private let maxHeight: CGFloat = 22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate + phaseSeed
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint.opacity(0.55 + 0.45 * Double(clampedLevel)))
                        .frame(width: barWidth, height: barHeight(index: index, phase: phase))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeOut(duration: 0.12), value: clampedLevel)
        }
        .accessibilityHidden(true)
    }

    private var clampedLevel: Float {
        min(max(level, 0), 1)
    }

    /// Loudness sets how far the bars can travel; the oscillation only shapes
    /// them, so silence reads as a flat line rather than a slower dance.
    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        guard isActive else { return minHeight }

        // Perceptual rather than linear: RTP audio levels bunch up near zero,
        // so a raw value would leave normal speech barely moving the bars.
        let loudness = CGFloat(sqrt(clampedLevel))
        guard loudness > 0 else { return minHeight }

        let offset = Double(index) * 0.35
        let wave = sin(phase * 3.2 + offset) * 0.5 + sin(phase * 5.1 + offset * 1.7) * 0.3
        let normalized = CGFloat((wave + 0.8) / 1.6)

        // Centre bars carry more of the movement, which is how a level meter
        // reads rather than a row of independent bars.
        let centreBias = 1 - abs(CGFloat(index) - CGFloat(barCount - 1) / 2)
            / CGFloat(barCount)

        let travel = (maxHeight - minHeight) * loudness * centreBias
        return minHeight + normalized * travel
    }
}
