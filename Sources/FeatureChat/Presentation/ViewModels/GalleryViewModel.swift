//
//  GalleryViewModel.swift
//  Pods
//
//  Created by Asyst on 8/11/25.
//

import SwiftUI
import Photos
import Combine
import WaanguCoreKit


typealias FileName = String
typealias MimeType = String
typealias SizeKb = Int

struct MediaPayload {
    let thumbnail: String
    let image: String
    let fileName: String
    let caption: String
    let size: Int
    let mimeType: String
    var mediaType: MediaType = .image
    var uiImage: UIImage? = nil
    var jpegData: Data? = nil  // Original JPEG data to save to disk (not re-encoded PNG)
    /// Pixel dimensions of the media, carried so the receiving bubble can reserve
    /// its height before the image has been downloaded or decoded.
    var width: Int? = nil
    var height: Int? = nil
}



class GalleryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var images: [GalleryImage] = []
    @Published var selectedImages: [GalleryImage] = []
    @Published var currentOverlayImage: GalleryImage?
    @Published var albums: [PhotoAlbum] = []
    @Published var selectedAlbum: PhotoAlbum?
    @Published var isLoading = false
    @Published var contactsList: [UserContactProps] = []
    @Published  var selectedTab:TabAction = .gallery
    @Published var messages: [MessageDataItem] = []
    
    // Error notification
    @Published var showErrorNotification: Bool = false
    @Published var errorNotificationMessage: String = ""
    
    private var conversationId: String = ""
    private var discussionsUseCases : DiscussionUseCasesProtocol
    private var currentReceiverUser: UserRoom?
    private var isGroup: Bool = false
    
   
    
//    public let coordinator: ChatRoomCoordinator

    
    // MARK: - Private Properties
    private var selectedImageIds = Set<String>()
    
    init(
        user: UserRoom?,
        isGroup: Bool,
        conversationId: String,
        discussionsUseCase: DiscussionUseCasesProtocol,
//        coordinator:ChatRoomCoordinator,
        devicesContacts:[UserContactProps],
        waanguContacts:[UserContactProps]
      ) {
          self.currentReceiverUser = user
          self.isGroup = isGroup
          self.conversationId = conversationId
          self.discussionsUseCases = discussionsUseCase
//          self.coordinator = coordinator
          self.updateWaanguUsers(waanguUsers: waanguContacts, devicesContacts: devicesContacts)
       }
    
    
    func updateWaanguUsers(
        waanguUsers: [UserContactProps],
        devicesContacts: [UserContactProps]
    ) {
        
        let waanguPhoneNumbers = Set(waanguUsers.map { $0.phone.onlyDigits })
        
//        let filteredDeviceContacts = devicesContacts
//            .filter { !waanguPhoneNumbers.contains($0.phone.onlyDigits) }
        
        let filteredDeviceContacts = devicesContacts
            .filter { !waanguPhoneNumbers.contains($0.phone.onlyDigits) }
            .map { contact -> UserContactProps in
                var copy = contact
                copy.idContact = ""
                return copy
            }




        
        let mergedContacts = waanguUsers + filteredDeviceContacts
        
        self.contactsList =  mergedContacts
    }
    
    
    func sendContacts(selectedContacts:Set<String>){
        let selectedContactArray: [[String: Any]] = self.contactsList
            .filter { selectedContacts.contains($0.phone) }
            .map { contact in
                [
                    "id": contact.idContact ?? "",
                    "phone": contact.phone,
                    "name": contact.name,
                    "avatar": contact.avatar ?? ""
                ]
            }
        
//        self.coordinator.onSendMessage("", dic: ["contact" : selectedContactArray])
        
    }

    
    
    // MARK: - Photo Library Access
    func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    self.loadAlbums()
                    self.loadImagesFromLibrary()
                case .denied, .restricted:
                    debugLog("Photo library access denied")
                case .notDetermined:
                    debugLog("Photo library access not determined")
                @unknown default:
                    break
                }
            }
        }
    }
    
    // MARK: - Album Management
    func loadAlbums() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var allAlbums: [PhotoAlbum] = []
            
            // Fetch smart albums (like Favorites, Panoramas, etc.)
            let smartAlbums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .any,
                options: nil
            )
            
            // Fetch user-created albums
            let userAlbums = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .any,
                options: nil
            )
            
            // Process smart albums
            smartAlbums.enumerateObjects { collection, _, _ in
                if let album = self.createPhotoAlbum(from: collection) {
                    allAlbums.append(album)
                }
            }
            
            // Process user albums
            userAlbums.enumerateObjects { collection, _, _ in
                if let album = self.createPhotoAlbum(from: collection) {
                    allAlbums.append(album)
                }
            }
            
            // Sort by album title
            allAlbums.sort { $0.title < $1.title }
            
            DispatchQueue.main.async {
                self.albums = allAlbums
                self.isLoading = false
            }
        }
    }
    
    private func createPhotoAlbum(from collection: PHAssetCollection) -> PhotoAlbum? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        guard assets.count > 0 else { return nil }
        
        // Obtenir l'image de couverture (première image de l'album)
        var coverImage: UIImage?
        if let firstAsset = assets.firstObject {
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            
            PHImageManager.default().requestImage(
                for: firstAsset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                coverImage = image
            }
        }
        
        return PhotoAlbum(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "Sans titre",
            count: assets.count,
            collection: collection,
            coverImage: coverImage
        )
    }
    
    // MARK: - Image Loading
    func loadImagesFromLibrary() {
        loadImages(from: nil)
    }
    
    func loadImages(from album: PhotoAlbum?) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 50
            
            let assets: PHFetchResult<PHAsset>
            if let album = album {
                assets = PHAsset.fetchAssets(in: album.collection, options: fetchOptions)
            } else {
                assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }
            
            var fetchedImages: [GalleryImage] = []
            
            assets.enumerateObjects { asset, _, _ in
                if let creationDate = asset.creationDate {
                    let galleryImage = GalleryImage(
                        id: asset.localIdentifier,
                        asset: asset,
                        creationDate: creationDate
                    )
                    fetchedImages.append(galleryImage)
                }
            }
            
            DispatchQueue.main.async {
                self.images = fetchedImages
                self.selectedAlbum = album
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Image Selection
    func toggleSelection(for image: GalleryImage) {
        if selectedImageIds.contains(image.id) {
            deselectImage(image)
        } else {
            selectImage(image)
        }
    }
    
    private func selectImage(_ image: GalleryImage) {
        var selected = image
        selectedImageIds.insert(image.id)
        
        loadHighQualityImage(asset: image.asset) { highQuality in
            selected.highQualityImage = highQuality
            self.selectedImages.append(selected)
            
            // Get the real compressed file size from PHAssetResource before fetching URI
            let resources = PHAssetResource.assetResources(for: image.asset)
            let resource = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first
            let fileSizeKb = (resource.flatMap { $0.value(forKey: "fileSize") as? Int } ?? 0) / 1024

            DispatchQueue.global(qos: .userInitiated).async {
                self.getImageUri(for: selected.asset) { uri, fileName, _, mimeType in
                    DispatchQueue.main.async {
                        if let index = self.selectedImages.firstIndex(where: { $0.id == selected.id }) {
                            self.selectedImages[index].uri = uri
                            self.selectedImages[index].fileName = fileName
                            self.selectedImages[index].size = fileSizeKb  // PHAssetResource size, not data.count
                            self.selectedImages[index].mimeType = mimeType
                        }
                        self.sendSelectedImages()
                    }
                }
            }
        }
    }
    
    private func deselectImage(_ image: GalleryImage) {
        if let index = selectedImages.firstIndex(where: { $0.id == image.id }) {
            selectedImages.remove(at: index)
        }
        selectedImageIds.remove(image.id)
        sendSelectedImages()
    }
    
    func clearSelection() {
        selectedImages.removeAll()
        selectedImageIds.removeAll()
    }
    
    // MARK: - Image Processing
    func loadHighQualityImage(asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    private let universalMimeTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif"
    ]
    

    
    private func getImageUri(for asset: PHAsset, completion: @escaping (String, FileName, SizeKb, MimeType) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
            guard let data = data else {
                completion("", "", 0, "")
                return
            }
            
            // Get real compressed file size from PHAssetResource (not data.count which is raw pixel buffer)
            let resources = PHAssetResource.assetResources(for: asset)
            let resource = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first
            let fileSizeKb = (resource.flatMap { $0.value(forKey: "fileSize") as? Int } ?? 0) / 1024
            
            // Détecte le MIME si possible
            var mimeType: String
            if let uti = uti {
                mimeType = self.mimeTypeFromUTI(uti)
            } else {
                mimeType = "" // UTI nil → on forcera JPG
            }
            
            var finalData = data
            var fileExtension: String
            
            // Si le MIME n’est pas universel ou UTI nil → conversion JPEG
            if uti == nil || !self.universalMimeTypes.contains(mimeType) {
                if let image = UIImage(data: data),
                   let jpegData = image.jpegData(compressionQuality: 1.0) {
                    finalData = jpegData
                    mimeType = "image/jpeg"
                    fileExtension = "jpg"
                } else {
                    // fallback si échec conversion
                    completion("", "", 0, "")
                    return
                }
            } else {
                // MIME universel → garde l’extension correspondante
                switch mimeType {
                case "image/png": fileExtension = "png"
                case "image/gif": fileExtension = "gif"
                default: fileExtension = "jpg"
                }
            }
            
            let fileName = self.generateFileName(for: asset, extension: fileExtension)
            
            if let tempUrl = self.saveImageToTempDirectory(data: finalData, fileName: fileName) {
                // Return PHAssetResource size, not data.count (raw pixel buffer size)
                completion(tempUrl.absoluteString, fileName, fileSizeKb, mimeType)
            } else {
                completion("", "", 0, "")
            }
        }
    }
    
    

    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        let newSize = widthRatio > heightRatio ?
            CGSize(width: size.width * heightRatio, height: size.height * heightRatio) :
            CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }

    private func saveImageToTempDirectory(data: Data, fileName:FileName) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileUrl = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileUrl)
            return fileUrl
        } catch {
            debugLog("Error saving image to temp directory: \(error)")
            return nil
        }
    }
    func sendMedia(media: MediaPayload,caption: String? = nil,groupId:String) {
        debugLog("madia payload  \(media.fileName)  and caption  \(caption ?? "no caption")")
       let mediaContent = createMediaMessageContent(media, caption: caption)
        sendMediaAndTextMessage(mediaContent,type: .IMAGE,groupId: groupId)
        
    }
    

    func createMediaMessageContent(_ media: MediaPayload,caption: String? = nil) -> MessageContent {
        return MessageContent(
            text:caption ?? "",
            image: media.image,
            shouldUploadDownload: true,
            shouldRetry: false,
            fileName: media.fileName,
            size: media.size,
            thumbnail: media.thumbnail,
            caption: caption,
            mimeType: media.mimeType,
        )
    }
    
    func saveCachedMedia(url:String,key:String,type:MediaType,UIimage:UIImage?) {
        if type == .image {
            DiskMediaManager.shared.saveImageToDisk(UIimage ?? UIImage(), fileName: key, pathName: .CHAT)
        } else if type == .video {
            // Was `URL(string: url)!` — a force unwrap on a value that is a bare
            // filesystem path, which URL(string:) turns into an unreadable
            // scheme-less URL. See LocalMediaURL.
            guard let videoURL = LocalMediaURL.resolve(url) else { return }
            DiskMediaManager.shared.saveVideoToDisk(from: videoURL, fileName: key, pathName: .CHAT)
        }
    }
    
    // MARK: - Error Notification
    private func showErrorNotification(_ message: String) {
        errorNotificationMessage = message
        showErrorNotification = true
        
        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showErrorNotification = false
        }
    }
    
    func sendMediaAndTextMessage(_ content: MessageContent,type:MessageTypeProps,groupId:String) {
       
//         coordinator.onSendMessage(text,dic: [:])
        

             let code = String(Date().timeIntervalSince1970 * 1000)

             let msg = MessageDataItem(
                 codeMessage: code,
                 senderId: CurrentSessionInfo.shared.currentUid,
                 senderAvatar:  CurrentSessionInfo.shared.userProfile,
                 senderPhone:  CurrentSessionInfo.shared.userPhoneNumber,
                 senderName:  CurrentSessionInfo.shared.userName,
                 receiverId: "",
                 groupId:  currentReceiverUser?.idContact ?? "", // MARK: TO DO we will add group functionality
                 typeMessage: type,
                 message:content,
                 forwarded: false, // MARK: TO DO
                 status: .PENDING,
                 isMoney: false,
                 createdAt: Date(),
            
             
//                 reply: nil
             )
        
        if type == .IMAGE {
            guard let imageUrlString = content.image, !imageUrlString.isEmpty else {
                showErrorNotification(ChatErrorStrings.sendImageInvalidPath)
                return
            }
            
            // Handle both local file paths and URL strings
            let imageURL: URL?
            if imageUrlString.hasPrefix("file://") {
                imageURL = URL(string: imageUrlString)
            } else if imageUrlString.hasPrefix("/") {
                imageURL = URL(fileURLWithPath: imageUrlString)
            } else {
                imageURL = URL(string: imageUrlString)
            }
            
            guard let url = imageURL,
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                showErrorNotification(String(format: ChatErrorStrings.imageLoadFailed, imageUrlString))
                return
            }
            
            saveCachedMedia(url: imageUrlString, key: code, type: .image, UIimage: image)
        }
        
        
     
             // Keep in current chat
             messages.append(msg)
//         self.groupedMessages = groupMessagesByDay(messages)
   
         
             // Persist per conversation
         let conversation = DiscussionChatItem(lastMessage: msg,
                            conversationId: self.conversationId,
                            contact: ContactChannel(
                                userName: currentReceiverUser?.name ?? "",
                                phone: currentReceiverUser?.phone ?? "",
                                image: currentReceiverUser?.avatar ?? "",
                                isBlocked: currentReceiverUser?.isBlocked ?? false,
                                isGroup: self.isGroup,
                                id: currentReceiverUser?.idContact ?? "",
                                userId: currentReceiverUser?.userId ?? ""
                            )
         )
         Task {
             do {
                 try await discussionsUseCases.createDiscussion.execute(discussion: conversation)
                 debugLog("have created discussion  \(messages.count)  and is it cached?  \(DiskMediaManager.shared.hasDiskImage(for: code, pathName: .CHAT))")
             } catch {
                 debugLog("❌ Error occur while creating discussion : \(error)")
             }
         }
      

             // Update conversation list
//             conversationStore.addConversation(
//                 contactId: selectedUserId,
//                 lastMessage: msg
//             )

             // Send to backend
//             await sendToBackend(msg, input: input)
         

         
    }
    

//    func onSendImage(caption: String? = nil) {
//        print("we are sending images",selectedImages.count)
//        guard !selectedImages.isEmpty else { return }
//        
//        for image in selectedImages {
//            Task.detached(priority: .userInitiated) { [weak self] in
//                guard let self else { return }
//                
//                await withCheckedContinuation { continuation in
//                    self.generateAndSaveThumbnail(for: image.asset) { thumbnailPath in
//                        Task { @MainActor in
//                            if let path = thumbnailPath {
//                                let payLoad: MediaPayload = MediaPayload(thumbnail: path, image: image.uri ?? "", fileName: image.fileName ?? "", caption: image.caption ?? "", size: image.size ?? 0, mimeType: image.mimeType ?? "")
//                                self.sendMedia(media: payLoad, caption: caption)
////                                self.chatRoomViewModel.sendMedia(media: payLoad,caption: caption)
////                                self.coordinator.onSendMessage(
////                                    "",
////                                    dic: [
////                                        "thumbnail": path,
////                                        "image": image.uri ?? "",
////                                        "file_name": image.fileName ?? "",
////                                        "caption": image.caption ?? "",
////                                        "size": image.size ?? 0,
////                                        "mimeType": image.mimeType ?? "",
////                                    ]
////                                )
//                            }
//                            continuation.resume()
//                        }
//                    }
//                }
//            }
//        }
//        self.messages = []
//        
//    }
//
//    
    // MARK: - Data Export
    private func sendSelectedImages() {
        // Implement your logic for sending selected images
        // For example:
        // let uris = selectedImages.compactMap { $0.uri }
        // delegate?.didSelectImages(uris)
    }
}

extension GalleryViewModel {
 
    private func mimeTypeFromUTI(_ uti: String?) -> String {
        guard let uti = uti else { return "application/octet-stream" }
        
        let utiToMime: [String: String] = [
            "public.jpeg": "image/jpeg",
            "public.png": "image/png",
            "public.heic": "image/heic",
            "public.heif": "image/heif",
            "public.webp": "image/webp",
            "public.tiff": "image/tiff",
            "com.compuserve.gif": "image/gif",
            "public.raw-image": "image/x-raw",
            "com.apple.quicktime-image": "image/jpeg"
        ]
        
        return utiToMime[uti] ?? "application/octet-stream"
    }

    private func generateFileName(for asset: PHAsset, extension fileExtension: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "IMG_\(dateString).\(fileExtension)"
    }
}

// MARK: - Data Models
struct GalleryImage: Identifiable, Equatable {
    let id: String
    let asset: PHAsset
    let creationDate: Date
    var highQualityImage: UIImage?
    var uri: String?
    var size: Int?
    var fileName: String?
    var mimeType: String?
    var caption: String?
}

struct PhotoAlbum: Identifiable {
    let id: String
    let title: String
    let count: Int
    let collection: PHAssetCollection
    let coverImage: UIImage?
}




struct ResultSendImage {
    let thumbnailUri: String
    let asset: GalleryImage
    let caption: String?
}
