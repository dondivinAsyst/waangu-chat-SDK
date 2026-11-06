//
//  VideoTrimCacheStore.swift
//  FeatureChat
//

import SwiftUI
import UIKit

struct CachedVideoData {
    let thumbnails: [UIImage]
    let startTime: Double
    let endTime: Double
    let duration: Double
    let trimDuration: Double
}

@MainActor
final class VideoTrimCacheStore: ObservableObject {
    @Published var cache: [String: CachedVideoData] = [:]

    func clear(identifier: String? = nil) {
        if let identifier {
            cache.removeValue(forKey: identifier)
        } else {
            cache.removeAll()
        }
    }
}
