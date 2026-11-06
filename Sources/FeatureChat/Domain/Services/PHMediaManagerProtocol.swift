//
//  PHMediaManagerProtocol.swift
//  FeatureChat
//
//  Created by Refactoring on 5/5/26.
//

import Foundation
import Photos
import UIKit
import AVFoundation

//// MARK: - Media Album
//
//public struct MediaAlbum: Identifiable {
//    public let id: String
//    public let title: String
//    public let count: Int
//    public let collection: PHAssetCollection
//    
//    public init(id: String, title: String, count: Int, collection: PHAssetCollection) {
//        self.id = id
//        self.title = title
//        self.count = count
//        self.collection = collection
//    }
//}
//
//// MARK: - Media File
//
//public struct MediaFile {
//    public let uri: String
//    public let fileName: String
//    public let sizeKb: Int
//    public let mimeType: String
//    
//    public init(uri: String, fileName: String, sizeKb: Int, mimeType: String) {
//        self.uri = uri
//        self.fileName = fileName
//        self.sizeKb = sizeKb
//        self.mimeType = mimeType
//    }
//}

// MARK: - PHMediaManager Protocol

public protocol PHMediaManagerProtocol {
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func fetchAlbums() -> [MediaAlbum]
    func fetchMedia(from album: MediaAlbum?, limit: Int) -> [MediaAsset]
    func getFullMedia(asset: PHAsset, completion: @escaping (MediaFile?) -> Void)
    func getThumbnailBase64(asset: PHAsset, size: CGSize, completion: @escaping (String?) -> Void)
}

// MARK: - PHMediaManager Implementation

public final class PHMediaManager: PHMediaManagerProtocol {
    
    public init() {}
    
    public func requestAuthorization(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            completion(status == .authorized)
        }
    }
    
    public func fetchAlbums() -> [MediaAlbum] {
        var albums: [MediaAlbum] = []
        
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .albumRegular,
            options: nil
        )
        
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        
        [smartAlbums, userAlbums].forEach { collections in
            collections.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                
                if assets.count > 0 {
                    let album = MediaAlbum(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Unknown",
                        count: assets.count,
                        collection: collection
                    )
                    albums.append(album)
                }
            }
        }
        
        return albums
    }
    
    // MARK: Fetch media from album
    public func fetchMedia(from album: MediaAlbum?, limit: Int = 50) -> [MediaAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let assets: PHFetchResult<PHAsset> = {
            if let album { return PHAsset.fetchAssets(in: album.collection, options: options) }
            return PHAsset.fetchAssets(with: options)
        }()

        var list: [MediaAsset] = []

        assets.enumerateObjects { asset, _, _ in
            // Get the real compressed file size from PHAssetResource — fast, no image data loaded
            let resources = PHAssetResource.assetResources(for: asset)
            let resource = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first
            let fileSizeBytes = resource.flatMap { $0.value(forKey: "fileSize") as? Int } ?? 0

            let media = MediaAsset(
                id: asset.localIdentifier,
                asset: asset,
                creationDate: asset.creationDate ?? Date(),
                type: asset.mediaType == .video ? .video : .image,
                fileSizeBytes: fileSizeBytes
            )
            list.append(media)
        }

        return list
    }
    
    public func getFullMedia(asset: PHAsset, completion: @escaping (MediaFile?) -> Void) {
        if asset.mediaType == .image {
            getImageData(asset: asset, completion: completion)
        } else if asset.mediaType == .video {
            getVideoData(asset: asset, completion: completion)
        } else {
            completion(nil)
        }
    }
    
    private func getImageData(asset: PHAsset, completion: @escaping (MediaFile?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        // Get real compressed file size from PHAssetResource before fetching data
        let resources = PHAssetResource.assetResources(for: asset)
        let resource = resources.first(where: { $0.type == .photo }) ?? resources.first
        let fileSizeBytes = resource.flatMap { $0.value(forKey: "fileSize") as? Int } ?? 0

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }
            
            let fileName = "IMG_\(Date().timeIntervalSince1970).jpg"
            // dataUTI is a UTI string (e.g. "public.jpeg"), not a MIME type.
            // Convert it to a proper MIME type so downstream mimeType.hasPrefix("image") works.
            let mimeType = Self.mimeType(fromUTI: dataUTI)
            
            // Save to temp directory
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? data.write(to: tempURL)
            
            let mediaFile = MediaFile(
                uri: tempURL.path,
                fileName: fileName,
                sizeKb: fileSizeBytes / 1024,  // PHAssetResource size, not data.count (which is raw pixel buffer)
                mimeType: mimeType,
                type: .image
            )
        
            completion(mediaFile)
        }
    }
    
    private func getVideoData(asset: PHAsset, completion: @escaping (MediaFile?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let urlAsset = avAsset as? AVURLAsset else {
                completion(nil)
                return
            }
            
            let fileName = "VID_\(Date().timeIntervalSince1970).mp4"
            let fileSize = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)[.size] as? Int ?? 0
            
            let mediaFile = MediaFile(
                uri: urlAsset.url.path,
                fileName: fileName,
                sizeKb: (fileSize ?? 0) / 1024,
                mimeType: "video/mp4",
                type: .video
            )
            completion(mediaFile)
        }
    }
    
    // MARK: - UTI → MIME conversion

    private static func mimeType(fromUTI uti: String?) -> String {
        guard let uti else { return "image/jpeg" }
        let map: [String: String] = [
            "public.jpeg":               "image/jpeg",
            "public.png":                "image/png",
            "public.heic":               "image/heic",
            "public.heif":               "image/heif",
            "public.webp":               "image/webp",
            "public.tiff":               "image/tiff",
            "com.compuserve.gif":        "image/gif",
            "public.raw-image":          "image/x-raw",
            "com.apple.quicktime-image": "image/jpeg",
            "public.mpeg-4":             "video/mp4",
            "com.apple.quicktime-movie": "video/quicktime",
        ]
        return map[uti] ?? "image/jpeg"
    }

    public func getThumbnailBase64(asset: PHAsset, size: CGSize, completion: @escaping (String?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image,
                  let data = image.jpegData(compressionQuality: 0.7) else {
                completion(nil)
                return
            }
            completion(data.base64EncodedString())
        }
    }
}
