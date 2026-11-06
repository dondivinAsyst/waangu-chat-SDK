//
//  ChatVideoSendPolicy.swift
//  FeatureChat
//

import Foundation

/// Chat-only video send limits (Status keeps its own 120s trimmer defaults).
enum ChatVideoSendPolicy {
    static let maxDurationSeconds: Double = 8 * 60 // 480
    static let minDurationSeconds: Double = 3
}

/// Status / stories trimmer default when no override is passed.
enum StatusVideoTrimPolicy {
    static let maxDurationSeconds: Double = 120
}
