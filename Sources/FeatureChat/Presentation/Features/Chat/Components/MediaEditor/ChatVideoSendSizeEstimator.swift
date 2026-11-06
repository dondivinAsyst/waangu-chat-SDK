//
//  ChatVideoSendSizeEstimator.swift
//  FeatureChat
//

import Foundation

enum ChatVideoSendSizeEstimator {
    static let standardBitsPerSecond: Double = 800_000
    static let hdBitsPerSecond: Double = 1_500_000
    static let standardAudioBitsPerSecond: Double = 96_000
    static let hdAudioBitsPerSecond: Double = 128_000

    static func estimatedBytes(trimDuration: Double, useHD: Bool) -> Int {
        guard trimDuration > 0 else { return 0 }
        let videoBps = useHD ? hdBitsPerSecond : standardBitsPerSecond
        let audioBps = useHD ? hdAudioBitsPerSecond : standardAudioBitsPerSecond
        let totalBps = videoBps + audioBps
        return Int(trimDuration * totalBps / 8.0)
    }

    static func formattedSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 KB" }
        let kb = Double(bytes) / 1024.0
        if kb >= 1024 {
            return String(format: "%.1f MB", kb / 1024.0)
        }
        return String(format: "%.0f KB", kb)
    }
}
