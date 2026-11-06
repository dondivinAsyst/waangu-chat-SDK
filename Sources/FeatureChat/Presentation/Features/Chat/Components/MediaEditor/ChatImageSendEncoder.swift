//
//  ChatImageSendEncoder.swift
//  FeatureChat
//

import UIKit

enum ChatImageSendEncoder {
    static let standardMaxBytes = 800_000
    static let hdMaxBytes = 2_500_000
    static let standardMaxEdge: CGFloat = 1600
    static let hdMaxEdge: CGFloat = 2560

    /// Avatars are only ever shown in small circles, so they get a much tighter
    /// budget than a sent photo.
    static let avatarMaxBytes = 200_000
    static let avatarMaxEdge: CGFloat = 512

    /// Encodes a profile or group photo for upload. Without this a full
    /// resolution camera shot goes up untouched — several megabytes to render a
    /// 40pt circle.
    static func encodeAvatar(_ image: UIImage) -> Data {
        let resized = resize(image, maxLongEdge: avatarMaxEdge)

        var quality: CGFloat = 0.85
        var data = resized.jpegData(compressionQuality: quality) ?? Data()

        while data.count > avatarMaxBytes && quality > 0.4 {
            quality -= 0.1
            guard let next = resized.jpegData(compressionQuality: quality) else { break }
            data = next
        }

        return data
    }

    static func encode(_ image: UIImage, useHD: Bool) -> Data {
        let maxEdge = useHD ? hdMaxEdge : standardMaxEdge
        let maxBytes = useHD ? hdMaxBytes : standardMaxBytes
        let resized = resize(image, maxLongEdge: maxEdge)

        var quality: CGFloat = useHD ? 0.80 : 0.60
        var data = resized.jpegData(compressionQuality: quality) ?? Data()

        while data.count > maxBytes && quality > 0.35 {
            quality -= 0.08
            if let next = resized.jpegData(compressionQuality: quality) {
                data = next
            } else {
                break
            }
        }

        if data.count > maxBytes {
            let smaller = resize(resized, maxLongEdge: maxEdge * 0.75)
            quality = useHD ? 0.75 : 0.55
            data = smaller.jpegData(compressionQuality: quality) ?? data
        }

        return data
    }

    static func resize(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
