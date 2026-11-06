//
//  ChatVideoSendEncoder.swift
//  FeatureChat
//

import AVFoundation
import Foundation

enum ChatVideoSendEncoder {

    static func exportPreset(useHD: Bool) -> String {
        useHD ? AVAssetExportPreset1280x720 : AVAssetExportPresetMediumQuality
    }

    static func fallbackPresets(useHD: Bool) -> [String] {
        if useHD {
            return [
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPresetLowQuality
            ]
        }
        return [
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality
        ]
    }

    static func encode(
        asset: AVAsset,
        timeRange: CMTimeRange?,
        useHD: Bool,
        outputURL: URL
    ) async throws -> URL {
        let sourceAsset: AVAsset
        if let timeRange {
            sourceAsset = try await trimmedComposition(from: asset, timeRange: timeRange)
        } else {
            sourceAsset = asset
        }

        let trimDuration: Double = {
            if let timeRange {
                let seconds = CMTimeGetSeconds(timeRange.duration)
                return seconds.isFinite ? seconds : 1
            }
            let seconds = CMTimeGetSeconds(sourceAsset.duration)
            return seconds.isFinite && seconds > 0 ? seconds : 1
        }()

        try? FileManager.default.removeItem(at: outputURL)

        var encodedURL: URL?
        for preset in fallbackPresets(useHD: useHD) {
            guard let session = AVAssetExportSession(asset: sourceAsset, presetName: preset) else {
                continue
            }
            try? FileManager.default.removeItem(at: outputURL)
            session.outputURL = outputURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true

            let success = await export(session)
            if success, FileManager.default.fileExists(atPath: outputURL.path) {
                encodedURL = outputURL
                break
            }
        }

        guard let encodedURL else {
            throw ChatVideoSendEncoderError.exportFailed
        }

        // If still oversized vs WhatsApp-ish budget, re-export once with LowQuality.
        let budget = Int(Double(ChatVideoSendSizeEstimator.estimatedBytes(
            trimDuration: max(trimDuration, 1),
            useHD: useHD
        )) * 1.4)

        let currentSize = (try? FileManager.default.attributesOfItem(atPath: encodedURL.path)[.size] as? Int) ?? 0
        if currentSize > budget {
            let lowURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            if let lowSession = AVAssetExportSession(
                asset: sourceAsset,
                presetName: AVAssetExportPresetLowQuality
            ) {
                lowSession.outputURL = lowURL
                lowSession.outputFileType = .mp4
                lowSession.shouldOptimizeForNetworkUse = true
                let ok = await export(lowSession)
                if ok, FileManager.default.fileExists(atPath: lowURL.path) {
                    let lowSize = (try? FileManager.default.attributesOfItem(atPath: lowURL.path)[.size] as? Int) ?? Int.max
                    if lowSize < currentSize {
                        try? FileManager.default.removeItem(at: encodedURL)
                        try? FileManager.default.moveItem(at: lowURL, to: encodedURL)
                    } else {
                        try? FileManager.default.removeItem(at: lowURL)
                    }
                }
            }
        }

        return encodedURL
    }

    private static func trimmedComposition(from asset: AVAsset, timeRange: CMTimeRange) async throws -> AVAsset {
        let composition = AVMutableComposition()
        let tracks = try await asset.load(.tracks)

        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw ChatVideoSendEncoderError.missingVideoTrack
        }

        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ChatVideoSendEncoderError.compositionFailed
        }

        try compositionVideo.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if let audioTrack = tracks.first(where: { $0.mediaType == .audio }),
           let compositionAudio = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        return composition
    }

    private static func export(_ session: AVAssetExportSession) async -> Bool {
        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume(returning: session.status == .completed)
            }
        }
    }
}

enum ChatVideoSendEncoderError: Error {
    case exportFailed
    case missingVideoTrack
    case compositionFailed
}
