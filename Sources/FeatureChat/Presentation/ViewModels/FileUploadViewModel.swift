import SwiftUI
import Combine
import WaanguCoreKit
import OSLog

enum UploadStatus: Equatable {
    case idle
    case uploading(progress: Double)
    case success(fileUrl: String)
    case failed(error: AppError)

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var progress: Double {
        switch self {
        case .uploading(let p): return p
        case .success: return 1.0
        default: return 0.0
        }
    }
}

@MainActor
public class FileUploadViewModel: ObservableObject {

    // MARK: - Single-file state (legacy / profile upload)
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var uploadProgress: Double = 0
    @Published var uploadedFileUrl: String?
    @Published var uploadStatus: UploadStatus = .idle

    // MARK: - Per-file keyed state (chat bubbles)
    /// Keyed by message `codeMessage` — one upload slot per message.
    @Published private(set) var uploads: [String: UploadState] = [:]
    /// Keyed by message `codeMessage` — one download slot per message (same as disk cache key).
    @Published private(set) var downloads: [String: DownloadState] = [:]

    // MARK: - Transfer outcome reporting

    /// Reports a transfer that ended in failure, so the owner can persist it onto
    /// the message. Set once by the room; every failure path routes through
    /// `failUpload`/`failDownload`, so no call site has to remember to report.
    ///
    /// Without this the outcome lived only in the dictionaries above, which are
    /// memory — a photo that failed to upload came back from a relaunch looking
    /// exactly like one that had never been tried.
    var onTransferFailed: ((_ codeMessage: String) -> Void)?

    /// Reports a transfer that succeeded. Carries the remote URL for an upload and
    /// nil for a download, which is what lets the room tell the two apart.
    ///
    /// The URL matters: a manual retry from a bubble called `upload(file:)` with no
    /// success callback, so an upload that finally worked never cleared
    /// `pendingUpload` and the message was never published. Reporting it here fixes
    /// every path at once rather than asking each call site to remember.
    var onTransferRecovered: ((_ codeMessage: String, _ remoteURL: String?) -> Void)?

    // MARK: - Automatic transfer attempts

    /// How many times a transfer is retried on its own before it waits for the user.
    static let maxAutoTransferAttempts = 3

    /// Attempts spent this session, keyed by message `codeMessage`.
    ///
    /// Deliberately **not** `@Published`: a counter bump has nothing to show, and
    /// publishing it would invalidate every bubble observing this object.
    ///
    /// This is the in-session authority. The persisted count on the message seeds
    /// it — see `canAutoTransfer(key:persistedAttempts:)` — so a cap survives
    /// relaunch without every attempt needing to round-trip through the database
    /// before the next one can be judged.
    private var autoTransferAttempts: [String: Int] = [:]

    /// Whether an automatic transfer may still be started for this message.
    ///
    /// Without this a failed transfer re-attempted on every single appearance —
    /// scrolling a thread past a media message that could not be sent kicked off a
    /// fresh request each time it came back on screen, forever.
    func canAutoTransfer(key: String, persistedAttempts: Int?) -> Bool {
        spentAttempts(key: key, persistedAttempts: persistedAttempts) < Self.maxAutoTransferAttempts
    }

    /// Attempts spent so far, taking the higher of what this session has seen and
    /// what was persisted — a relaunch must not hand back an allowance the message
    /// already used up.
    func spentAttempts(key: String, persistedAttempts: Int?) -> Int {
        max(autoTransferAttempts[key] ?? 0, persistedAttempts ?? 0)
    }

    /// Records an automatic attempt and returns the new total, so the caller can
    /// persist it onto the message.
    @discardableResult
    func recordAutoTransferAttempt(key: String, persistedAttempts: Int?) -> Int {
        let next = spentAttempts(key: key, persistedAttempts: persistedAttempts) + 1
        autoTransferAttempts[key] = next
        return next
    }

    /// Clears the allowance — on success, and whenever the user asks for a retry
    /// themselves. A manual tap is an explicit instruction, so it always proceeds
    /// and restores the full automatic allowance behind it.
    func resetAutoTransferAttempts(key: String) {
        autoTransferAttempts.removeValue(forKey: key)
    }

    private let fileUplaodUseCases: FileUplaodUseCasesProtocol
    private var progressTimer: Timer?
    private let logger = Logger(subsystem: "com.waangu.upload", category: "FileUploadViewModel")

    // Active URLSession for per-file download tasks (upload goes through use-case layer)
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    private let downloadTasks = Protected<[String: URLSessionDownloadTask]>([:])

    init(fileUplaodUseCases: FileUplaodUseCasesProtocol) {
        self.fileUplaodUseCases = fileUplaodUseCases
    }

    // MARK: - Upload File

    func uploadFile(
        fileName: String,
        fileData: Data,
        fileType: String,
        folder: FileUploadRequest.Folder = .message
    ) async -> Bool {
        guard !isLoading else { return false }

        let maxSize = FileSizeLimits.limit(for: fileType)
        guard fileData.count <= maxSize else {
            errorMessage = "File too large. Max: \(maxSize / (1024 * 1024))MB"
            uploadStatus = .failed(error: .unknown("File too large"))
            return false
        }

        isLoading = true
        errorMessage = nil
        uploadStatus = .uploading(progress: 0)
        uploadProgress = 0
        startProgressSimulation()

        let request = FileUploadRequest(
            fileName: fileName,
            fileType: fileType,
            fileSize: fileData.count,
            folder: folder
        )

        let result = await fileUplaodUseCases.uploadFileUseCase.execute(
            for: request,
            fileData: fileData
        )

        isLoading = false
        stopProgressSimulation()

        switch result {
        case .success(let fileUrl):
            uploadedFileUrl = fileUrl
            uploadProgress = 1.0
            uploadStatus = .success(fileUrl: fileUrl)
            return true
        case .failure(let error):
            errorMessage = error.localizedDescription
            uploadStatus = .failed(error: error)
            return false
        }
    }

    // MARK: - Upload Image (UIImage)

    func uploadImage(
        fileName: String,
        image: UIImage,
        folder: FileUploadRequest.Folder = .message,
        compressionQuality: CGFloat = 0.8
    ) async -> Bool {
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            errorMessage = ChatErrorStrings.imageConversionFailed
            return false
        }
        return await uploadFile(
            fileName: fileName,
            fileData: imageData,
            fileType: "image",
            folder: folder
        )
    }

    // MARK: - Upload Document from URL

    func uploadDocument(
        fileUrl: URL,
        folder: FileUploadRequest.Folder = .chatFile
    ) async -> Bool {
        do {
            let fileData = try Data(contentsOf: fileUrl)
            let fileName = fileUrl.lastPathComponent
            return await uploadFile(
                fileName: fileName,
                fileData: fileData,
                fileType: "document",
                folder: folder
            )
        } catch {
            errorMessage = String(format: ChatErrorStrings.fileReadFailed, error.localizedDescription)
            return false
        }
    }

    // MARK: - Upload Profile Image

    func uploadProfileImage(
        userId: String,
        imageData: Data,
        fileName: String
    ) async -> Bool {
        guard !isLoading else { return false }

        isLoading = true
        errorMessage = nil
        uploadStatus = .uploading(progress: 0)
        uploadProgress = 0
        startProgressSimulation()

        let result = await fileUplaodUseCases.uploadProfileImageUseCase.execute(
            userId: userId,
            imageData: imageData,
            fileName: fileName
        )

        isLoading = false
        stopProgressSimulation()

        switch result {
        case .success(let fileUrl):
            uploadedFileUrl = fileUrl
            uploadProgress = 1.0
            uploadStatus = .success(fileUrl: fileUrl)
            return true
        case .failure(let error):
            errorMessage = error.localizedDescription
            uploadStatus = .failed(error: error)
            return false
        }
    }

    // MARK: - Validation

    func validateFileSize(_ fileSize: Int, maxSize: Int = 10 * 1024 * 1024) -> Bool {
        fileSize <= maxSize
    }

    func validateFileType(_ fileExtension: String, allowedTypes: [String]) -> Bool {
        allowedTypes.contains(fileExtension.lowercased())
    }

    func generateFileName(originalName: String, userId: String? = nil) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let uuid = UUID().uuidString.prefix(8)
        let ext = (originalName as NSString).pathExtension
        let baseName = userId.map { "\($0)_\(timestamp)_\(uuid)" } ?? "\(timestamp)_\(uuid)"
        return ext.isEmpty ? baseName : "\(baseName).\(ext)"
    }

    // MARK: - Per-file upload (chat bubbles — mirrors UploadViewModel.upload(file:))

    /// Uploads a media file described by an `UploadFile` value.
    /// Progress and final state are published through `uploads[file.trackingKey]`.
    /// `onSuccess` is called on the main actor when the upload completes successfully.
    func upload(file: UploadFile, onSuccess: (@MainActor (String) -> Void)? = nil) async {
        guard !file.trackingKey.isEmpty else { return }

        uploads[file.trackingKey] = .loading
        logger.debug("Starting upload for message: \(file.trackingKey) file: \(file.filename)")

        // Use sizeBytes if available (from GRDB MessageContent.size),
        // otherwise read from disk and use fileData.count
        let fileData: Data
        let fileSizeBytes: Int
        if let knownSize = file.sizeBytes {
            // Size already known from GRDB — still need to read file data for upload
            do {
                guard file.url.isFileURL else {
                    logger.error("Cannot read non-file URL (scheme: \(file.url.scheme ?? "nil")). Skipping upload.")
                    failUpload(
                        file.trackingKey,
                        error: "File not accessible at path: \(file.url.absoluteString)",
                        persist: false
                    )
                    return
                }
                fileData = try Data(contentsOf: file.url)
            } catch {
                logger.error("Cannot read local file (code \((error as NSError).code))")
                failUpload(file.trackingKey, error: error.localizedDescription, persist: false)
                return
            }
            fileSizeBytes = knownSize
        } else {
            // Legacy path: no known size — read from disk and use fileData.count
            do {
                guard file.url.isFileURL else {
                    logger.error("Cannot read non-file URL (scheme: \(file.url.scheme ?? "nil")). Skipping upload.")
                    failUpload(
                        file.trackingKey,
                        error: "File not accessible at path: \(file.url.absoluteString)",
                        persist: false
                    )
                    return
                }
                fileData = try Data(contentsOf: file.url)
            } catch {
                logger.error("Cannot read local file (code \((error as NSError).code))")
                failUpload(file.trackingKey, error: error.localizedDescription, persist: false)
                return
            }
            fileSizeBytes = fileData.count
        }

        // Derive a fileType string from the mimeType for the use-case layer
        let fileType: String

        if file.mimeType.hasPrefix("image") || file.mimeType.hasPrefix("public.image") || file.mimeType == "public.jpeg" {
            fileType = "image"
        } else if file.mimeType.hasPrefix("video") || file.mimeType.hasPrefix("public.movie") || file.mimeType.hasPrefix("public.video") {
            fileType = "video"
        } else if file.mimeType.hasPrefix("audio") || file.mimeType.hasPrefix("public.audio") {
            fileType = "audio"
        } else {
            fileType = "document"
        }


        // Simulate smooth progress while the real upload runs
        startPerFileProgressSimulation(trackingKey: file.trackingKey)

        let request = FileUploadRequest(
            fileName: file.filename,
            fileType: fileType,
            fileSize: fileSizeBytes,  // Use GRDB size if available, else fileData.count
            folder: .message
        )
        let result = await fileUplaodUseCases.uploadFileUseCase.execute(for: request, fileData: fileData)

        stopProgressSimulation()

        switch result {
        case .success(let fileUrl):
            succeedUpload(file.trackingKey, url: fileUrl)
            resetAutoTransferAttempts(key: file.trackingKey)
            logger.debug("Upload succeeded for \(file.trackingKey): \(fileUrl)")
            onSuccess?(fileUrl)
        case .failure(let error):
            failUpload(file.trackingKey, error: error.localizedDescription)
            logger.error("Upload failed for \(file.trackingKey): \(error.localizedDescription)")
        }
    }

    /// Cancels an in-progress per-message upload (resets its state to idle).
    func cancelUpload(for trackingKey: String) {
        uploads[trackingKey] = .idle
    }

    /// Marks a message upload as failed with the given error message.
    /// Used by bubbles when the local file cannot be found on disk.
    ///
    /// Deliberately **not** persisted. This is a precondition the bubble checks
    /// before it even attempts, and it is routinely transient: the send path writes
    /// each file to disk around the time the row first renders, so a later item in
    /// a batch can be looked for a moment before it lands.
    ///
    /// Persisting it set `shouldRetry`, and the auto-upload guard is
    /// `shouldUploadDownload == true && shouldRetry == false` — so one early look
    /// stopped the rest of the batch from ever uploading on its own again. In
    /// memory it simply heals on the next appearance, which is what it did before.
    func markUploadFailed(trackingKey: String, error: String) {
        failUpload(trackingKey, error: error, persist: false)
    }

    // MARK: - Outcome funnels

    /// The single place an upload becomes `.failure`, so persisting the outcome
    /// can never be forgotten at a call site.
    ///
    /// - Parameter persist: whether this outcome should be written onto the
    ///   message. False for local preconditions — a file not on disk *yet* is not
    ///   the same thing as a transfer the server refused, and only the second is
    ///   worth remembering across launches.
    func failUpload(_ trackingKey: String, error: String, persist: Bool = true) {
        uploads[trackingKey] = .failure(error: error)
        guard persist else { return }
        onTransferFailed?(trackingKey)
    }

    /// The single place an upload becomes `.success`.
    func succeedUpload(_ trackingKey: String, url: String) {
        uploads[trackingKey] = .success(url: url)
        onTransferRecovered?(trackingKey, url)
    }

    /// The single place a download becomes `.failure`.
    ///
    /// - Parameter persist: as `failUpload` — false for the checks made before a
    ///   request is ever sent.
    func failDownload(_ cacheKey: String, error: String, persist: Bool = true) {
        downloads[cacheKey] = .failure(error: error)
        guard persist else { return }
        onTransferFailed?(cacheKey)
    }

    /// The single place a download becomes `.success`.
    func succeedDownload(_ cacheKey: String) {
        downloads[cacheKey] = .success
        onTransferRecovered?(cacheKey, nil)
    }

    // MARK: - Per-file download (chat bubbles — mirrors UploadViewModel.downloadImage/downloadVideo)

    func downloadImage(urlString: String, cacheKey: String) {
        guard !cacheKey.isEmpty else { return }
        checkIfCached(cachedkey: cacheKey, type: .image) { [weak self] isCached in
            guard let self else { return }
            Task { @MainActor in
                if isCached {
                    self.succeedDownload(cacheKey)
                } else {
                    self.startDownload(urlString: urlString, cacheKey: cacheKey, saveAs: .image)
                }
            }
        }
    }

    func downloadVideo(urlString: String, cacheKey: String) {
        guard !cacheKey.isEmpty else { return }
        checkIfCached(cachedkey: cacheKey, type: .video) { [weak self] isCached in
            guard let self else { return }
            Task { @MainActor in
                if isCached {
                    self.succeedDownload(cacheKey)
                } else {
                    self.startDownload(urlString: urlString, cacheKey: cacheKey, saveAs: .video)
                }
            }
        }
    }

    func downloadDocument(urlString: String, cacheKey: String, fileExtension: String) {
        guard !cacheKey.isEmpty else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            failDownload(cacheKey, error: ChatErrorStrings.downloadURLMissing, persist: false)
            return
        }

        let ext = fileExtension.lowercased()
        guard !ext.isEmpty else {
            failDownload(cacheKey, error: "Unknown file type", persist: false)
            return
        }

        if DiskMediaManager.shared.hasDiskFile(for: cacheKey, ext: ext, pathName: .CHAT) {
            succeedDownload(cacheKey)
        } else {
            startDownload(urlString: trimmedURL, cacheKey: cacheKey, saveAs: .document(ext: ext))
        }
    }

    /// Downloads a voice/audio message and persists it under the audio disk path
    /// (`CHAT/{codeMessage}.{ext}`) that `BubbleVoiceView` reads.
    func downloadAudio(urlString: String, cacheKey: String, fileExtension: String) {
        guard !cacheKey.isEmpty else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            failDownload(cacheKey, error: ChatErrorStrings.downloadURLMissing, persist: false)
            return
        }

        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedExt = ext.isEmpty ? "opus" : ext

        if DiskMediaManager.shared.hasDiskAudio(for: cacheKey, ext: resolvedExt, pathName: .CHAT) {
            succeedDownload(cacheKey)
            return
        }

        startDownload(urlString: trimmedURL, cacheKey: cacheKey, saveAs: .audio(ext: resolvedExt))
    }

    func cancelDownload(for cacheKey: String) {
        guard !cacheKey.isEmpty else { return }
        downloadTasks.write { tasks in
            tasks[cacheKey]?.cancel()
            tasks[cacheKey] = nil
        }
        downloads[cacheKey] = .idle
    }

    // MARK: - Cache check (mirrors UploadViewModel.checkIfCached)

    func checkIfCached(cachedkey: String, type: MediaType, completion: @escaping (Bool) -> Void) {
        if type == .image {
            completion(DiskMediaManager.shared.hasDiskImage(for: cachedkey, pathName: .CHAT))
        } else {
            completion(DiskMediaManager.shared.hasDiskVideo(for: cachedkey, pathName: .CHAT))
        }
    }

    // MARK: - Cache read helpers (mirrors UploadViewModel)

    func getCachedImage(key: String) -> UIImage? {
        logger.debug("Getting cached image for key: \(key)")
        return DiskMediaManager.shared.loadImageFromDisk(fileName: key, pathName: .CHAT)
    }

    func getCachedMedia(key: String) -> URL? {
        logger.debug("Getting cached video for key: \(key)")
        return DiskMediaManager.shared.loadVideoFromDisk(fileName: key, pathName: .CHAT)
    }

    // MARK: - Combine publishers (mirrors UploadViewModel)

    func uploadPublisher(for trackingKey: String) -> AnyPublisher<UploadState, Never> {
        $uploads
            .compactMap { $0[trackingKey] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func downloadPublisher(for cacheKey: String) -> AnyPublisher<DownloadState, Never> {
        $downloads
            .compactMap { $0[cacheKey] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - Private download helpers

    private enum DownloadSaveKind {
        case image
        case video
        case document(ext: String)
        case audio(ext: String)
    }

    private func startDownload(urlString: String, cacheKey: String, saveAs: DownloadSaveKind) {
        guard !cacheKey.isEmpty else { return }
        guard let url = URL(string: urlString) else {
            failDownload(cacheKey, error: ChatErrorStrings.invalidURL, persist: false)
            return
        }

        // Avoid duplicate in-flight work for the same message.
        if let existing = downloads[cacheKey] {
            switch existing {
            case .downloading, .success:
                return
            case .idle, .failure:
                break
            }
        }

        downloads[cacheKey] = .downloading(progress: 0.0)

        let task = downloadSession.downloadTask(with: url) { [weak self] tempURL, response, error in
            self?.handleDownloadCompletion(
                cacheKey: cacheKey,
                tempURL: tempURL,
                response: response,
                error: error,
                saveAs: saveAs
            )
        }

        downloadTasks.write { $0[cacheKey] = task }
        task.resume()

        Task { [weak self] in
            await self?.trackDownloadProgress(for: task, cacheKey: cacheKey)
        }
    }

    private func trackDownloadProgress(for task: URLSessionDownloadTask, cacheKey: String) async {
        let progressStream = AsyncStream(Double.self) { continuation in
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                DispatchQueue.main.async { continuation.yield(progress.fractionCompleted) }
            }
            continuation.onTermination = { @Sendable _ in observation.invalidate() }
        }
        for await progress in progressStream {
            if let state = downloads[cacheKey] {
                switch state {
                case .success, .failure:
                    return
                case .idle, .downloading:
                    break
                }
            }
            downloads[cacheKey] = .downloading(progress: progress)
        }
    }

    private func handleDownloadCompletion(
        cacheKey: String,
        tempURL: URL?,
        response: URLResponse?,
        error: Error?,
        saveAs: DownloadSaveKind
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.downloadTasks.write { $0[cacheKey] = nil }

            if let error {
                self.failDownload(cacheKey, error: error.localizedDescription)
                return
            }
            guard let tempURL else {
                self.failDownload(cacheKey, error: "Temporary file not found")
                return
            }

            // The response was discarded, and `downloadTask` only reports `error`
            // for transport failures — an HTTP 403 or 404 arrives here as a
            // perfectly successful download of an error page.
            //
            // For an image that surfaced as "Cannot decode downloaded image", which
            // says nothing about the real cause; for a document or a voice note it
            // was worse, because the error body saved to disk without complaint and
            // the file read as downloaded.
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                #if DEBUG
                // The body is the useful part: an S3/MinIO refusal says exactly why
                // in its XML, and that is invisible from the status code alone.
                let body = String((try? String(contentsOf: tempURL, encoding: .utf8))?.prefix(300) ?? "")
                let address = http.url?.absoluteString ?? "?"
                self.logger.error("Download failed for \(cacheKey, privacy: .public): HTTP \(http.statusCode, privacy: .public) from \(address, privacy: .public) — \(body, privacy: .public)")
                #endif
                self.failDownload(cacheKey, error: "Download failed (\(http.statusCode))")
                try? FileManager.default.removeItem(at: tempURL)
                return
            }

            switch saveAs {
            case .video:
                DiskMediaManager.shared.saveVideoToDisk(from: tempURL, fileName: cacheKey, pathName: .CHAT)
                self.succeedDownload(cacheKey)

            case .image:
                if let data = try? Data(contentsOf: tempURL),
                   let image = UIImage(data: data) {
                    DiskMediaManager.shared.saveImageToDisk(image, fileName: cacheKey, pathName: .CHAT)
                    self.succeedDownload(cacheKey)
                } else {
                    self.failDownload(cacheKey, error: ChatErrorStrings.imageDecodeFailed)
                }

            case .document(let ext):
                if let data = try? Data(contentsOf: tempURL),
                   DiskMediaManager.shared.saveFileDataToDisk(data: data, fileName: cacheKey, ext: ext, pathName: .CHAT) != nil {
                    self.succeedDownload(cacheKey)
                } else {
                    self.failDownload(cacheKey, error: ChatErrorStrings.documentSaveFailed)
                }

            case .audio(let ext):
                if let data = try? Data(contentsOf: tempURL),
                   DiskMediaManager.shared.saveAudioDataToDisk(
                       data: data,
                       fileName: cacheKey,
                       ext: ext,
                       pathName: .CHAT
                   ) != nil {
                    self.succeedDownload(cacheKey)
                } else {
                    self.failDownload(cacheKey, error: ChatErrorStrings.audioSaveFailed)
                }
            }

            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - State

    func reset() {
        isLoading = false
        errorMessage = nil
        uploadProgress = 0
        uploadedFileUrl = nil
        uploadStatus = .idle
    }

    // MARK: - Progress Simulation (single-file / profile)

    private func startProgressSimulation() {
        uploadProgress = 0.1
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isLoading else { return }
                if self.uploadProgress < 0.9 {
                    self.uploadProgress += 0.03
                    self.uploadStatus = .uploading(progress: self.uploadProgress)
                }
            }
        }
    }

    // MARK: - Progress Simulation (per-file)

    private func startPerFileProgressSimulation(trackingKey: String) {
        uploads[trackingKey] = .uploading(progress: 0.1)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if case .uploading(let p) = self.uploads[trackingKey], p < 0.9 {
                    self.uploads[trackingKey] = .uploading(progress: p + 0.03)
                }
            }
        }
    }

    private func stopProgressSimulation() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    

    deinit {
        progressTimer?.invalidate()
    }
    
    
}

// MARK: - Extensions utiles

extension FileUploadViewModel {
    /// Types de fichiers communs
    struct FileTypes {
        static let images = ["jpg", "jpeg", "png", "gif", "webp"]
        static let documents = ["pdf", "doc", "docx", "txt", "xlsx"]
        static let videos = ["mp4", "mov", "avi", "mkv"]
        static let audio = ["mp3", "wav", "m4a", "aac"]
        
        static func allowedTypes(for fileType: String) -> [String] {
            switch fileType {
            case "image": return images
            case "document": return documents
            case "video": return videos
            case "audio": return audio
            default: return []
            }
        }
    }
    
    /// Tailles maximum par type de fichier
    struct FileSizeLimits {
        static let image = 10 * 1024 * 1024 // 10MB
        static let document = 20 * 1024 * 1024 // 20MB
        static let video = 100 * 1024 * 1024 // 100MB
        static let audio = 50 * 1024 * 1024 // 50MB
        
        static func limit(for fileType: String) -> Int {
            switch fileType {
            case "image": return image
            case "document": return document
            case "video": return video
            case "audio": return audio
            default: return 10 * 1024 * 1024 // 10MB par défaut
            }
        }
    }
}
