//
//  WaveformExtractor.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//


import AVFoundation

public enum WaveformExtractor {

    public static func extract(from url: URL, barCount: Int = 40) async -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return [] }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return [] }

        do { try audioFile.read(into: buffer) } catch { return [] }
        guard let channelData = buffer.floatChannelData?[0] else { return [] }

        let totalSamples = Int(buffer.frameLength)
        let samplesPerBar = max(1, totalSamples / barCount)

        var amplitudes = [Float]()
        amplitudes.reserveCapacity(barCount)

        for i in 0..<barCount {
            let start = i * samplesPerBar
            let end = min(start + samplesPerBar, totalSamples)
            guard start < totalSamples else { break }
            var sum: Float = 0
            for j in start..<end { sum += abs(channelData[j]) }
            amplitudes.append(sum / Float(end - start))
        }

        let maxAmp = amplitudes.max() ?? 1
        guard maxAmp > 0 else { return amplitudes }
        return amplitudes.map { max(0.05, $0 / maxAmp) }
    }

    public static func downsample(_ samples: [Float], to barCount: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let chunkSize = max(1, samples.count / barCount)

        var result = [Float]()
        result.reserveCapacity(barCount)

        for i in 0..<barCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            guard start < samples.count else { break }
            let chunk = samples[start..<end]
            result.append(chunk.reduce(0, +) / Float(chunk.count))
        }

        let maxVal = result.max() ?? 1
        guard maxVal > 0 else { return result }
        return result.map { max(0.05, $0 / maxVal) }
    }
}
