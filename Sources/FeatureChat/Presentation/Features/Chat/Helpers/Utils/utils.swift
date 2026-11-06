//
//  GestureStates.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  utils.swift
//  Chat
//
//  Created by asyst on 10/15/25.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import AVKit
import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

func timeString(from seconds : Int)-> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    
    return String(format: "%02d:%02d", minutes,seconds)
}

public enum GestureStates {
    case leftDrag
    case UpwardDrag
    case longPressed
    case noInput
}
public func applyFilter(to image: UIImage, filter: ImageFilterType) -> UIImage {
    guard filter != .none, let ciImage = CIImage(image: image) else { return image }
    let context = CIContext()
    var outputImage: CIImage?
    
    switch filter {
    case .vivid:
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(1.3, forKey: kCIInputSaturationKey)
            f.setValue(0.1, forKey: kCIInputBrightnessKey)
            outputImage = f.outputImage
        }
    case .warm:
        if let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 8000, y: 0), forKey: "inputTargetNeutral")
            outputImage = f.outputImage
        }
    case .cool:
        if let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 5000, y: 0), forKey: "inputTargetNeutral")
            outputImage = f.outputImage
        }
    case .bw:
        if let f = CIFilter(name: "CIPhotoEffectMono") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            outputImage = f.outputImage
        }
    case .pop:
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(1.5, forKey: kCIInputSaturationKey)
            f.setValue(0.2, forKey: kCIInputContrastKey)
            outputImage = f.outputImage
        }
    default:
        return image
    }
    
    guard let output = outputImage,
          let cgImage = context.createCGImage(output, from: output.extent) else {
        return image
    }
    
    return UIImage(cgImage: cgImage)
}
public func getFileSizeString(for fileURL: URL) -> String {
    // Try to get file size in bytes
    var sizeInBytes: Int64 = 0
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let fileSize = attributes[.size] as? NSNumber {
            sizeInBytes = fileSize.int64Value
        }
    } catch {
        debugLog("❌ Error getting file size: \(error)")
        return "Unknown size"
    }

    // Convert to KB, MB, GB as needed
    let kb = Double(sizeInBytes) / 1024
    let mb = kb / 1024
    let gb = mb / 1024

    if gb >= 1 {
        return String(format: "%.2f GB", gb)
    } else if mb >= 1 {
        return String(format: "%.2f MB", mb)
    } else {
        return String(format: "%.2f KB", kb)
    }
}






public enum LoadedMedia {
    case image(UIImage)
    case video(URL)
    case audio(URL)
}

public func loadMedia(from source: Any) async throws -> LoadedMedia {
    switch source {
    // MARK: - UIImage (already loaded)
    case let image as UIImage:
        return .image(image)

    // MARK: - Data (try decode as image)
    case let data as Data:
        if let image = UIImage(data: data) {
            return .image(image)
        } else {
            throw NSError(domain: "MediaLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported data format"])
        }

    // MARK: - URL (remote or local)
    case let url as URL:
        if url.isFileURL {
            if url.pathExtension.lowercased().matchesAny(of: ["jpg", "jpeg", "png", "heic", "heif"]) {
                if let image = UIImage(contentsOfFile: url.path) {
                    return .image(image)
                }
            } else if url.pathExtension.matchesAny(of: ["mp4", "mov", "avi"]) {
                return .video(url)
            } else if url.pathExtension.matchesAny(of: ["mp3", "m4a", "wav"]) {
                return .audio(url)
            }
        } else {
            // Remote URL (try download)
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                return .image(image)
            }
        }

        throw NSError(domain: "MediaLoader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unsupported URL or file type"])

    // MARK: - String (path or URL)
    case let path as String:
        if let url = URL(string: path),
           url.scheme?.lowercased().hasPrefix("http") == true {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                return .image(image)
            }
        } else if FileManager.default.fileExists(atPath: path) {
            if let image = UIImage(contentsOfFile: path) {
                return .image(image)
            }
            let url = URL(fileURLWithPath: path)
            if url.pathExtension.matchesAny(of: ["mp4", "mov", "avi"]) {
                return .video(url)
            } else if url.pathExtension.matchesAny(of: ["mp3", "m4a", "wav"]) {
                return .audio(url)
            }
        } else if let image = UIImage(named: path) {
            return .image(image)
        }

        throw NSError(domain: "MediaLoader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid path or resource name"])

    // MARK: - NSItemProvider
    case let provider as NSItemProvider:
        // Try image first
        if provider.canLoadObject(ofClass: UIImage.self) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let image = object as? UIImage {
                        continuation.resume(returning: .image(image))
                    } else {
                        continuation.resume(throwing: NSError(domain: "MediaLoader", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to load UIImage"]))
                    }
                }
            }
        }

        // Try video
        let videoTypes: [UTType] = [.movie, .video]
        for type in videoTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let tempURL = url else {
                        continuation.resume(throwing: NSError(domain: "MediaLoader", code: -5, userInfo: [NSLocalizedDescriptionKey: "No file URL for video"]))
                        return
                    }
                    let destURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(tempURL.pathExtension)
                    try? FileManager.default.copyItem(at: tempURL, to: destURL)
                    continuation.resume(returning: .video(destURL))
                }
            }
        }

        // Try audio
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let tempURL = url else {
                        continuation.resume(throwing: NSError(domain: "MediaLoader", code: -6, userInfo: [NSLocalizedDescriptionKey: "No file URL for audio"]))
                        return
                    }
                    let destURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(tempURL.pathExtension)
                    try? FileManager.default.copyItem(at: tempURL, to: destURL)
                    continuation.resume(returning: .audio(destURL))
                }
            }
        }

        throw NSError(domain: "MediaLoader", code: -7, userInfo: [NSLocalizedDescriptionKey: "Unsupported NSItemProvider type"])

    // MARK: - Unknown
    default:
        throw NSError(domain: "MediaLoader", code: -99, userInfo: [NSLocalizedDescriptionKey: "Unsupported source type \(type(of: source))"])
    }
}

public func generateThumbnail(url: URL) async -> UIImage? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .background).async {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    continuation.resume(returning: uiImage)
                }
            } catch {
                debugLog("❌ Failed to generate thumbnail: \(error)")
                DispatchQueue.main.async {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}


public func imageToDataURL(_ image: UIImage, quality: CGFloat = 0.005, maxDimension: CGFloat = 150) -> String? {
    // Resize image first
    let resizedImage = resizeImage(image, maxDimension: maxDimension)
    
    // Convert to JPEG data
    guard let jpegData = resizedImage.jpegData(compressionQuality: quality) else {
        return nil
    }
    
    let base64String = jpegData.base64EncodedString()
    return "data:image/jpeg;base64,\(base64String)"
}
public func imageFromDataURL(_ dataURL: String) -> UIImage? {
    guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
    let base64 = String(dataURL[dataURL.index(after: commaIndex)...])

    guard let data = Data(base64Encoded: base64) else { return nil }
    return UIImage(data: data)
}

private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let size = image.size
    let aspectRatio = size.width / size.height
    
    var newSize: CGSize
    if size.width > size.height {
        newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
    } else {
        newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
    }
    
    // Only resize if image is larger than target
    if size.width <= maxDimension && size.height <= maxDimension {
        return image
    }
    
    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return resizedImage ?? image
}




private extension String {
    func matchesAny(of exts: [String]) -> Bool {
        exts.contains(self.lowercased())
    }
}

