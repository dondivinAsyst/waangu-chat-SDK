//
//  CallToneController.swift
//  FeatureChat
//
//  Ringback for outgoing calls.
//
//  The tone is synthesised rather than loaded from a file: the app ships no
//  audio assets, and the previous code silently played nothing because it looked
//  for `whatsapp_ringtone.mp3` / `ringtone.caf`, neither of which exists.
//
//  Incoming calls are not handled here — CallKit rings those with the system
//  ringtone. Playing our own on top would fight it and force the audio session
//  out of `.voiceChat`.
//

import Foundation
import AVFoundation

/// Plays the standard ringback pair (440 Hz + 480 Hz) on the usual
/// two-seconds-on, four-seconds-off cadence.
final class CallToneController {

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isRunning = false

    /// Ringback frequencies and cadence, per the standard call-progress tone.
    private let frequencies: (low: Double, high: Double) = (440, 480)
    private let onDuration: Double = 2.0
    private let offDuration: Double = 4.0

    private var phaseLow: Double = 0
    private var phaseHigh: Double = 0
    /// Position within one on+off cycle, in seconds.
    private var cyclePosition: Double = 0

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }

        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return }

        let cycleLength = onDuration + offDuration
        let lowIncrement = 2 * Double.pi * frequencies.low / sampleRate
        let highIncrement = 2 * Double.pi * frequencies.high / sampleRate
        let step = 1.0 / sampleRate

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                // Silent during the gap between rings.
                let isRinging = self.cyclePosition < self.onDuration
                var value: Float = 0

                if isRinging {
                    // Halved so the summed pair does not clip.
                    value = Float((sin(self.phaseLow) + sin(self.phaseHigh)) * 0.15)
                    self.phaseLow += lowIncrement
                    self.phaseHigh += highIncrement
                    if self.phaseLow > 2 * .pi { self.phaseLow -= 2 * .pi }
                    if self.phaseHigh > 2 * .pi { self.phaseHigh -= 2 * .pi }
                }

                self.cyclePosition += step
                if self.cyclePosition >= cycleLength { self.cyclePosition = 0 }

                for buffer in buffers {
                    let pointer = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < pointer.count { pointer[frame] = value }
                }
            }
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isRunning = true
        } catch {
            #if DEBUG
            print("Ringback failed to start: \(error)")
            #endif
            teardown()
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        teardown()
    }

    private func teardown() {
        if let sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
        phaseLow = 0
        phaseHigh = 0
        cyclePosition = 0
        isRunning = false
    }
}
