//
//  URL+Extensions.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//

import Foundation
import UIKit
import AVFoundation

extension URL {
    public  static var stubURL: URL {
        return URL(string:"https://www.google.com")!
    }
    
    public func generateVideoThumbnail() async throws -> UIImage? {
        let asset = AVAsset(url: self)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        
        return try await withCheckedThrowingContinuation { continuation in
            if #available(iOS 16.0, *) {
                imageGenerator.generateCGImageAsynchronously(for: time) { cgImage, _, error  in
                    if let cgImage = cgImage {
                        let thumbnailImage = UIImage(cgImage: cgImage)
                        continuation.resume(returning: thumbnailImage)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "", code: 0))
                    }
                }
            } else {
                // Fallback on earlier versions
            }
        }
    }
}
