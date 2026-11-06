import SwiftUI
import Photos
import Combine
import WaanguCoreKit

public struct GalleryMedia: Identifiable, Equatable, Hashable {
    public  let id: String
    let asset: PHAsset
    let creationDate: Date
public let type: MediaType
    var highQualityImage: UIImage?
    var uri: String?
    var size: Int?
    var fileName: String?
    var mimeType: String?
    var caption: String?
    
    // Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable conformance
    public static func == (lhs: GalleryMedia, rhs: GalleryMedia) -> Bool {
        lhs.id == rhs.id
    }
}

// struct MediaAlbums {
//    let id: UUID
//     let title: String
//    public let count: Int
//    public let collection: PHAssetCollection
//}

public class PHMediaManagerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var mediaItems: [GalleryMedia] = []
    @Published var selectedMedia: [GalleryMedia] = []
    @Published var currentOverlayMedia: GalleryMedia?
    @Published var isLoading = false
    @Published var albums: [MediaAlbum] = []
    @Published var selectedAlbum: MediaAlbum?
    
//    @Published var contactsList: [UserContactProps] = []
    @Published var selectedTab: TabAction = .gallery
    
    // MARK: - Private Properties
    private var selectedMediaIds = Set<String>()
    private let mediaManager: PHMediaManagerProtocol

    
    // MARK: - Initialization
    public  init(
      
        mediaManager: PHMediaManagerProtocol,

    ) {
        
        self.mediaManager = mediaManager
     
    }
    
    
//    func getFileSize(asset: PHAsset, completion: @escaping (Int64?) -> Void) {
//        let options = PHImageRequestOptions()
//        options.isSynchronous = false
//        options.isNetworkAccessAllowed = true
//        options.version = .original
//        
//        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
//            guard let data = data else {
//                completion(nil)
//                return
//            }
//            completion(Int64(data.count)) // size in bytes
//        }
//    }
    func getFileSize(asset: PHAsset? = nil,
                     url: URL? = nil,
                     completion: @escaping (Int64?) -> Void) {

        // ---- CASE 1: URL provided ----
        if let fileURL = url {
            // Local file
            if fileURL.isFileURL {
                do {
                    let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
                    completion(size)
                } catch {
                    completion(nil)
                }
            } else {
                // Remote file → HEAD request (fast, does NOT download)
                var request = URLRequest(url: fileURL)
                request.httpMethod = "HEAD"

                URLSession.shared.dataTask(with: request) { _, response, _ in
                    if let httpResponse = response as? HTTPURLResponse,
                       let lengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                       let length = Int64(lengthStr) {
                        completion(length)
                    } else {
                        completion(nil)
                    }
                }.resume()
            }
            return
        }

        // ---- CASE 2: PHAsset provided ----
        if let phAsset = asset {
            // Use PHAssetResource to get the actual on-disk file size of the compressed JPEG/HEIC.
            // requestImageDataAndOrientation returns raw decoded pixel data (~27MB for 12MP),
            // not the compressed file size (~2-3MB). PHAssetResource gives the real size.
            let resources = PHAssetResource.assetResources(for: phAsset)
            // Prefer the original file resource; fall back to any resource
            let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
                ?? resources.first
            if let resource = resource,
               let fileSize = resource.value(forKey: "fileSize") as? Int64 {
            
                completion(fileSize)
                return
            }
            // Fallback: estimate from pixel dimensions (assumes ~0.5 bytes/pixel for JPEG)
            let estimatedSize = Int64(Double(phAsset.pixelWidth * phAsset.pixelHeight) * 0.5)
            completion(estimatedSize > 0 ? estimatedSize : nil)
            return
        }

        // Neither URL nor PHAsset passed
        completion(nil)
    }

    
    
    // MARK: - Contacts Management
   
    func resetSelectedMedia() {
        selectedMediaIds.removeAll()
        selectedMedia.removeAll()
    }
    // MARK: - Photo Library Access
    func requestPhotoLibraryAccess() {
        mediaManager.requestAuthorization { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.loadAlbums()
                    self?.loadMediaFromLibrary()
                } else {
                    debugLog("Photo library access denied")
                }
            }
        }
    }
    
    // MARK: - Album Management
    func loadAlbums() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let albums = self.mediaManager.fetchAlbums()
            
            DispatchQueue.main.async {
                self.albums = albums
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Media Loading
    func loadMediaFromLibrary() {
        loadMedia(from: nil)
    }
    
    func loadMedia(from album: MediaAlbum?) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let mediaAssets = self.mediaManager.fetchMedia(from: album, limit: 50)
            let galleryMedia = mediaAssets.map { asset in
                GalleryMedia(
                    id: asset.id,
                    asset: asset.asset,
                    creationDate: asset.creationDate,
                    type: asset.type,
//                    size: asset.fileSizeBytes / 1024  // Convert bytes to KB
                    size: asset.fileSizeBytes 
                )
            }
            debugLog("the current file size is   \(galleryMedia.first?.size ?? 0)")
            DispatchQueue.main.async {
                self.mediaItems = galleryMedia
                self.selectedAlbum = album
                self.isLoading = false
            }
           
        }
    }
    
    // MARK: - Media Selection
    func toggleSelection(for media: GalleryMedia) {
        if selectedMediaIds.contains(media.id) {
            deselectMedia(media)
        } else {
            selectMedia(media)
        }
    }
    
    private func selectMedia(_ media: GalleryMedia) {
        var selected = media
        selectedMediaIds.insert(media.id)
        selectedMedia.append(selected)

        loadHighQualityMedia(asset: media.asset) { highQuality in
            if let index = self.selectedMedia.firstIndex(where: { $0.id == selected.id }) {
                self.selectedMedia[index].highQualityImage = highQuality
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.getMediaUri(for: selected.asset) { uri, fileName, _, mimeType in
                    DispatchQueue.main.async {
                        if let index = self.selectedMedia.firstIndex(where: { $0.id == selected.id }) {
                            self.selectedMedia[index].uri = uri
                            self.selectedMedia[index].fileName = fileName
                            // DO NOT overwrite size — already set correctly from asset.fileSizeBytes in loadMedia()
                            self.selectedMedia[index].mimeType = mimeType
                        }
                        self.sendSelectedMedia()
                    }
                }
            }
        }
    }
    
    private func deselectMedia(_ media: GalleryMedia) {
        if let index = selectedMedia.firstIndex(where: { $0.id == media.id }) {
            selectedMedia.remove(at: index)
        }
        selectedMediaIds.remove(media.id)
        sendSelectedMedia()
    }
    
    func clearSelection() {
        selectedMedia.removeAll()
        selectedMediaIds.removeAll()
    }

    /// Loads full-resolution data for a library item before opening the preview screen.
    func prepareMediaForPreview(_ media: GalleryMedia, completion: @escaping (GalleryMedia) -> Void) {
        if media.type == .image {
            loadHighQualityMedia(asset: media.asset) { image in
                var prepared = media
                prepared.highQualityImage = image
                self.fillMediaURI(for: prepared, completion: completion)
            }
        } else {
            fillMediaURI(for: media, completion: completion)
        }
    }

    private func fillMediaURI(for media: GalleryMedia, completion: @escaping (GalleryMedia) -> Void) {
        getMediaUri(for: media.asset) { uri, fileName, _, mimeType in
            var updated = media
            updated.uri = uri
            updated.fileName = fileName
            updated.mimeType = mimeType
            completion(updated)
        }
    }

    static let previewMaxEdge: CGFloat = 2048

    static func previewTargetSize(for asset: PHAsset) -> CGSize {
        let width = CGFloat(asset.pixelWidth)
        let height = CGFloat(asset.pixelHeight)
        guard width > 0, height > 0 else {
            return CGSize(width: previewMaxEdge, height: previewMaxEdge)
        }
        let longEdge = max(width, height)
        guard longEdge > previewMaxEdge else {
            return CGSize(width: width, height: height)
        }
        let scale = previewMaxEdge / longEdge
        return CGSize(width: width * scale, height: height * scale)
    }

    static func loadPreviewImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: previewTargetSize(for: asset),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    // MARK: - Media Processing
    func loadHighQualityMedia(asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        // Pour les images uniquement
        guard asset.mediaType == .image else {
            completion(nil)
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: Self.previewTargetSize(for: asset),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    private func getMediaUri(for asset: PHAsset, completion: @escaping (String, FileName, SizeKb, MimeType) -> Void) {
        mediaManager.getFullMedia(asset: asset) { mediaFile in
            guard let mediaFile = mediaFile else {
                completion("", "", 0, "")
                return
            }
            
            completion(mediaFile.uri, mediaFile.fileName, mediaFile.sizeKb, mediaFile.mimeType)
        }
    }
    
    public func generateAndSaveThumbnail(for asset: PHAsset, completion: @escaping (String?) -> Void) {
        getThumbnailUri(for: asset) { thumbnailPath in
            completion(thumbnailPath)
        }
    }

    private func getThumbnailUri(for asset: PHAsset, completion: @escaping (String?) -> Void) {
        let size = CGSize(width: 60, height: 60)
        
        mediaManager.getThumbnailBase64(asset: asset, size: size) { base64String in
            completion(base64String)
        }
    }

//    func onSendMedia() {
//        guard !selectedMedia.isEmpty else { return }
//        
//        for media in selectedMedia {
//            Task.detached(priority: .userInitiated) { [weak self] in
//                guard let self else { return }
//                
//                await withCheckedContinuation { continuation in
//                    self.generateAndSaveThumbnail(for: media.asset) { thumbnailPath in
//                        Task { @MainActor in
//                            if let path = thumbnailPath {
//                                let mediaData: [String: Any] = [
//                                    "thumbnail": path,
//                                    "uri": media.uri ?? "",
//                                    "file_name": media.fileName ?? "",
//                                    "caption": media.caption ?? "",
//                                    "size": media.size ?? 0,
//                                    "mimeType": media.mimeType ?? "",
//                                    "type": media.type
//                                ]
//                                self.coordinator.onSendMessage("", dic: mediaData)
//                            }
//                            continuation.resume()
//                        }
//                    }
//                }
//            }
//        }
//    }
    
    // MARK: - Data Export
    private func sendSelectedMedia() {
        // Logique pour envoyer les médias sélectionnés
    }
}
