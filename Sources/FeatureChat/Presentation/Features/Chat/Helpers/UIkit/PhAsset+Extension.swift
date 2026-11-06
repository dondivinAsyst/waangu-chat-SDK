//
//  PhAsset+Extension.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


import Photos
import Foundation
import SwiftUI

// Extension pour PHAsset pour maintenir la compatibilité
extension PHAsset {
   public func getThumbnail(size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        
        var thumbnail: UIImage?
        PHImageManager.default().requestImage(
            for: self,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            thumbnail = image
        }
        return thumbnail
    }
}
