//
//  UploadViewModel.swift
//  Pods
//
//  Created by Asyst on 8/18/25.
//

import Foundation
import Combine
import SDWebImageSwiftUI
import OSLog

// MARK: - Models
struct UploadFile: Equatable, Sendable {
    /// Unique per-message key for in-memory upload state (`codeMessage`).
    let trackingKey: String
    let fileURL: String
    let filename: String
    let mimeType: String
    var remoteURL: String?
    let receiverID: String
    /// The real file size in bytes, read from GRDB (MessageContent.size).
    /// When provided, this is sent to the server instead of re-calculating from disk data.
    var sizeBytes: Int?
    var url: URL {
      if fileURL.starts(with: "file://") {
          return URL(string: fileURL)!
      } else {
          return URL(fileURLWithPath: fileURL)
      }
  }
}

enum DownloadState: Equatable {
    case idle
    case downloading(progress: Double)
    case success
    case failure(error: String)
}

enum UploadState: Equatable, Sendable {
    case idle
    case loading
    case uploading(progress: Double)
    case success(url: String)
//    case failure(error: String)
    case failure(error: String)
    
    var isActive: Bool {
        if case .uploading = self { return true }
        return false
    }
}

// MARK: - Error Handling
enum UploadViewModelError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)
    case cancelled
    case presignedURLError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return ChatErrorStrings.invalidURL
        case .invalidResponse: return ChatErrorStrings.invalidServerResponse
        case .serverError(let code): return "Server error (HTTP \(code))"
        case .cancelled: return "Upload cancelled"
        case .presignedURLError(let error): return String(format: ChatErrorStrings.uploadURLFailed, error.localizedDescription)
        }
    }
}

// MARK: - Optimized ViewModel
@MainActor
public final class UploadViewModel: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.yourapp.upload", category: "networking")
    
    // MARK: - Published Properties
    @Published private(set) var uploads: [String: UploadState] = [:]
    @Published private(set) var downloads: [String: DownloadState] = [:]
    
    

    var uploadFiles : [String : UploadFile] = [:]
    
//    public let coordinator: ChatRoomCoordinator
   
    
    // MARK: - Private Properties
    private let uploadTasks = Protected<[String: URLSessionUploadTask]>([:])
    private let downloadTasks = Protected<[String: URLSessionDownloadTask]>([:])
    private let session: URLSession

    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
             
//        self.coordinator = coordinator
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        super.init() // appelle l'init de NSObject
    }
    // MARK: - Public Methods
    
    /// Starts uploading a file
    func upload(file: UploadFile) async {
        logger.debug("Starting upload for file: \(file.filename)")
    
      
        await updateState(for: file.filename, state: .loading)
        
        do {
            let responseData = try await requestPresignedURL(filename: file.filename)
                        guard let presignedUrl = URL(string: responseData.url) else {
                throw UploadViewModelError.invalidURL
            }
            
          
            
            await setUploadData(for: file.filename, upld: file, remoteURL: responseData.fileUrl)
            
            await startUpload(file: file, presignedUrl: presignedUrl)
        } catch {
            logger.error("Upload failed: \(error.localizedDescription)")
            await handleError(error, for: file.filename)
        }
    }
    
    /// Pauses an upload
    func pauseUpload(for filename: String) {
        logger.debug("Pausing upload for: \(filename)")
        uploadTasks.write { tasks in
            tasks[filename]?.suspend()
        }
    }
    
    /// Resumes a paused upload
    func resumeUpload(for filename: String) {
        logger.debug("Resuming upload for: \(filename)")
        uploadTasks.write { tasks in
            tasks[filename]?.resume()
        }
    }
    
    /// Cancels an upload
    func cancelUpload(for filename: String) {
        logger.debug("Cancelling upload for: \(filename)")
        uploadTasks.write { tasks in
            tasks[filename]?.cancel()
            tasks[filename] = nil
        }
        Task { await updateState(for: filename, state: .idle) }
    }
    
    // MARK: - Private Methods
    
    private func startUpload(file: UploadFile, presignedUrl: URL) async {
        
        let filename = file.filename
        var request = URLRequest(url: presignedUrl)
        request.httpMethod = "PUT"
        request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        let token = await CurrentSessionInfo.shared.currentToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let task = session.uploadTask(with: request, fromFile: file.url) { [weak self] data, response, error in
            self?.handleUploadCompletion(filename: filename, response: response, error: error)
        }
        
        uploadTasks.write { $0[filename] = task }
        uploads[filename] = .uploading(progress: 0.0)
        
        Task { [weak self] in
            await self?.trackProgress(for: task, filename: filename)
        }
        
        task.resume()
    }
    
    private func trackProgress(for task: URLSessionUploadTask, filename: String) async {
        let progressSequence = AsyncStream(Double.self) { continuation in
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let value = progress.fractionCompleted
                DispatchQueue.main.async {
                    continuation.yield(value)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                observation.invalidate()
            }
        }
        
        for await progress in progressSequence {
            uploads[filename] = .uploading(progress: progress)
        }
    }
    

    private func sendToJs(filename: String, shouldUploadDownload:Bool){
//        coordinator.onUploadFileComplete(message: [
//            "remoteUri" : self.uploadFiles[filename]?.remoteURL ?? "",
//            "file_name" : self.uploadFiles[filename]?.filename ?? "",
//            "shouldUploadDownload": shouldUploadDownload,
//            "shouldRetry": shouldUploadDownload,
//            "receiverID" :  self.uploadFiles[filename]?.receiverID ?? ""
//        ], result: [:])
    }
    
    private func handleUploadCompletion(filename: String, response: URLResponse?, error: Error?) {
        Task { [weak self] in
            guard let self = self else { return }
            
            self.uploadTasks.write { $0[filename] = nil }
            
            if let error = error as? NSError {
                if error.code == NSURLErrorCancelled {
                    self.logger.debug("Upload cancelled for: \(filename)")
                    self.uploads[filename] = .idle
                    
                    self.sendToJs(filename: filename, shouldUploadDownload: true)
                } else {
                    self.logger.error("Upload failed for \(filename): \(error.localizedDescription)")
                    self.uploads[filename] = .failure(error: error.localizedDescription)
            
                    self.sendToJs(filename: filename, shouldUploadDownload: true)
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response for \(filename)")
                self.uploads[filename] = .failure(error: UploadViewModelError.invalidResponse.errorDescription ?? "Unknown error")
                
                self.sendToJs(filename: filename, shouldUploadDownload: true)
                
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                let successURL = httpResponse.url?.absoluteString ?? ""
                self.logger.debug("Upload succeeded for \(filename), URL: \(successURL)")
                self.uploads[filename] = .success(url: successURL)
                self.sendToJs(filename: filename, shouldUploadDownload: false)
            } else {
                self.logger.error("Server error for \(filename): HTTP \(httpResponse.statusCode)")
                self.uploads[filename] = .failure(error: UploadViewModelError.serverError(statusCode: httpResponse.statusCode).errorDescription ?? "Unknown error")
                self.sendToJs(filename: filename, shouldUploadDownload: true)
            }
        }
    }
    
    private func handleError(_ error: Error, for filename: String) async {
        let errorMessage: String
        
        if let uploadError = error as? UploadViewModelError {
            errorMessage = uploadError.errorDescription ?? "Unknown error"
        } else {
            errorMessage = error.localizedDescription
        }
        
        uploads[filename] = .failure(error: errorMessage)
    }
    
    private func updateState(for filename: String, state: UploadState) {
        uploads[filename] = state
    }
    
    private func setUploadData(for filename: String, upld: UploadFile, remoteURL: String) {
          var newFile = upld
           newFile.remoteURL = remoteURL
           self.uploadFiles[filename] = newFile
    }
    

    
    // MARK: - Combine Publisher
    func uploadPublisher(for filename: String) -> AnyPublisher<UploadState, Never> {
        $uploads
            .compactMap { $0[filename] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // MARK: - Cleanup
    deinit {
        logger.debug("Deinitializing UploadViewModel")
        uploadFiles = [:]
        uploadTasks.read { tasks in
            tasks.values.forEach { $0.cancel() }
        }
        downloadTasks.read { tasks in
            tasks.values.forEach { $0.cancel() }
        }
        session.finishTasksAndInvalidate()
    }
    
    //MARK: -Downloading jobs
    
   

}

// MARK: - Thread Safety Wrapper
final class Protected<T> {
    private var value: T
    private let queue: DispatchQueue
    
    init(_ value: T, labelPrefix: String? = nil) {
        self.value = value
        let bundleID = Bundle.main.bundleIdentifier ?? "com.waangu"
        let prefix = labelPrefix ?? bundleID
        self.queue = DispatchQueue(
            label: "\(prefix).protected",
            qos: .default,
            attributes: .concurrent
        )
    }
    
    func read<U>(_ operation: (T) -> U) -> U {
        queue.sync {
            operation(value)
        }
    }
    
    func write(_ operation: @escaping (inout T) -> Void) {
        queue.async(flags: .barrier) {
            operation(&self.value)
        }
    }
    
    @discardableResult
    func mutate<U>(_ operation: @escaping (inout T) -> U) -> U {
        queue.sync(flags: .barrier) {
            operation(&self.value)
        }
    }
    
    var currentValue: T {
        read { $0 }
    }
}




extension UploadViewModel {
    
    // MARK: - Enhanced Download Methods
    
    func downloadImage(urlString: String, cacheKey: String) {
        let downloadKey = urlString
        
        checkIfCached(cachedkey: cacheKey, type: .image) { [weak self] isCached in
            guard let self else { return }
            Task {
                if isCached {
                    self.downloads[downloadKey] = .success
                } else {
                    self.startDownload(urlString: urlString, cacheKey: cacheKey, isVideo: false)
                }
            }
        }
    }

    func downloadVideo(urlString: String, cacheKey: String) {
        let downloadKey = urlString

        checkIfCached(cachedkey: cacheKey, type: .video) { [weak self] isCached in
            guard let self else { return }
            Task {
                if isCached {
                    self.downloads[downloadKey] = .success
                } else {
                    self.startDownload(urlString: urlString, cacheKey: cacheKey, isVideo: true)
                }
            }
        }
    }
    
    private func startDownload(urlString: String, cacheKey: String, isVideo: Bool = false) {
        guard let url = URL(string: urlString) else {
            downloads[urlString] = .failure(error: "URL invalide")
            return
        }
        
        downloads[urlString] = .downloading(progress: 0.0)
        
        let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            self?.handleDownloadCompletion(downloadKey: urlString, cacheKey: cacheKey, tempURL: tempURL, response: response, error: error, isVideo: isVideo)
        }
        
        downloadTasks.write { $0[urlString] = task }
        task.resume()
        
        // Track progression
        Task { [weak self] in
            await self?.trackDownloadProgress(for: task, key: urlString)
        }
    }
    
    private func trackDownloadProgress(for task: URLSessionDownloadTask, key: String) async {
        let progressSequence = AsyncStream(Double.self) { continuation in
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let value = progress.fractionCompleted
                DispatchQueue.main.async {
                    continuation.yield(value)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                observation.invalidate()
            }
        }
        
        for await progress in progressSequence {
            downloads[key] = .downloading(progress: progress)
        }
    }
    
    private func handleDownloadCompletion(downloadKey: String, cacheKey: String, tempURL: URL?, response: URLResponse?, error: Error?, isVideo: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            
            if let error {
                self.downloads[downloadKey] = .failure(error: error.localizedDescription)
                self.downloadTasks.write { $0[downloadKey] = nil }
                return
            }
            
            guard let tempURL else {
                self.downloads[downloadKey] = .failure(error: "Fichier temporaire introuvable")
                self.downloadTasks.write { $0[downloadKey] = nil }
                return
            }
            
            if isVideo {
                DiskMediaManager.shared.saveVideoToDisk(from: tempURL, fileName: cacheKey, pathName: .CHAT)
                self.downloads[downloadKey] = .success
            } else if let data = try? Data(contentsOf: tempURL),
                      let image = UIImage(data: data) {
                DiskMediaManager.shared.saveImageToDisk(image, fileName: cacheKey, pathName: .CHAT)
                self.downloads[downloadKey] = .success
            } else {
                self.downloads[downloadKey] = .failure(error: "Impossible de charger l'image")
            }
            
            self.downloadTasks.write { $0[downloadKey] = nil }
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    // MARK: - Control Methods
    
    func pauseDownload(for key: String) {
        downloadTasks.write { tasks in
            tasks[key]?.suspend()
        }
        downloads[key] = .idle
    }
    
    func resumeDownload(for key: String) {
        downloadTasks.write { tasks in
            tasks[key]?.resume()
        }
        let currentProgress = downloads[key]?.progressValue ?? 0.0
        downloads[key] = .downloading(progress: currentProgress)
    }
    
    func cancelDownload(for key: String) {
        downloadTasks.write { tasks in
            tasks[key]?.cancel()
            tasks[key] = nil
        }
        downloads[key] = .idle
    }
    
    // MARK: - Cache Management
    
    func checkIfCached(cachedkey:String,type:MediaType, completion: @escaping (Bool) -> Void) {
//        guard let url = URL(string: urlString) else {
//            completion(false)
//            return
//        }
        
        
//        let cacheKey = SDWebImageManager.shared.cacheKey(for: url)
        if type == .image {
            completion(DiskMediaManager.shared.hasDiskImage(for: cachedkey, pathName: .CHAT))
        } else if type == .video {
            completion(DiskMediaManager.shared.hasDiskVideo(for: cachedkey, pathName: .CHAT))
        }
//        SDImageCache.shared.containsImage(forKey: cacheKey, cacheType: .all) { cacheType in
//            completion(cacheType != .none)
//        }
        
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
    
    
    func getCachedImage(key: String) -> UIImage? {
//        guard let url = URL(string: urlString) else { return nil }
        logger.debug("Getting cached image for key: \(key) is exist \(DiskMediaManager.shared.hasDiskImage(for: key, pathName: .CHAT))")
        return DiskMediaManager.shared.loadImageFromDisk(fileName: key, pathName: .CHAT)
//        let cacheKey = SDWebImageManager.shared.cacheKey(for: url)
//        return SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey) ??
//               SDImageCache.shared.imageFromDiskCache(forKey: cacheKey)
    }
    func getCachedMedia(key: String) -> URL? {
//        guard let url = URL(string: urlString) else { return nil }
        logger.debug("Getting cached video for key: \(key) is exist \(DiskMediaManager.shared.hasDiskVideo(for: key, pathName: .CHAT))")
        return DiskMediaManager.shared.loadVideoFromDisk(fileName: key, pathName: .CHAT)
//        let cacheKey = SDWebImageManager.shared.cacheKey(for: url)
//        return SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey) ??
//               SDImageCache.shared.imageFromDiskCache(forKey: cacheKey)
    }
    
    // MARK: - Download Publisher
    
    func downloadPublisher(for urlString: String) -> AnyPublisher<DownloadState, Never> {
        $downloads
            .compactMap { $0[urlString] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

// MARK: - Extension pour accéder à la valeur de progression
extension DownloadState {
    var progressValue: Double {
        if case .downloading(let progress) = self {
            return progress
        }
        return 0.0
    }
    
    var isDownloading: Bool {
        if case .downloading = self {
            return true
        }
        return false
    }
    
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
    
    var errorMessage: String? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}
