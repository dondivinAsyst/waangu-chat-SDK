import SwiftUI
import AVKit
import Photos
import Combine

@available(iOS 16.0, *)
@MainActor
class VideoPlayerController: ObservableObject {
    weak var player: AVPlayer?
    @Published var dragMode: DragMode? = nil
    enum DragMode { case left, right, center }
    @Published var isPlaying = false
    /// Player buffer / AVPlayerItem readiness — never wait on thumbnails.
    @Published var isLoading = true
    /// Remote / offline load failed — viewer can show thumbnail + retry.
    @Published var hasError = false
    /// Filmstrip generation in progress — independent of playback.
    @Published var isGeneratingThumbnails = false
    @Published var asset: AVAsset?
    @Published var thumbnails: [UIImage] = []
    @Published var duration: Double = 0
    @Published var startTime: Double = 0
    @Published var endTime: Double = 0
    @Published var isExporting = false
    @Published var timePerPixel = 1.0
    @Published var currentTime = 0.0
    @Published var trimProgress = 0.0
    @Published var trimDuration = 0.0
    private var playerItem: AVPlayerItem?
    private var thumbnailGenerationTask: Task<Void, Never>?

    let cacheStore: VideoTrimCacheStore
    /// Max selectable / initial trim window (chat = 480s, Status = 120s).
    let maxTrimDuration: Double

    init(
        cacheStore: VideoTrimCacheStore,
        clearCache: Bool = false,
        maxTrimDuration: Double = StatusVideoTrimPolicy.maxDurationSeconds
    ) {
        if clearCache {
            cacheStore.cache.removeAll()
        }
        self.cacheStore = cacheStore
        self.maxTrimDuration = maxTrimDuration
    }

    convenience init(storieVM: StoriesViewModel, clearCache: Bool = false) {
        self.init(
            cacheStore: storieVM.videoTrimCache,
            clearCache: clearCache,
            maxTrimDuration: StatusVideoTrimPolicy.maxDurationSeconds
        )
    }
    

    
    // Cache structure to store both thumbnails and trim data
//    struct CachedVideoData {
//        let thumbnails: [UIImage]
//        let startTime: Double
//        let endTime: Double
//        let duration: Double
//        let trimDuration : Double
//    }
//    
//    // Enhanced cache - stores thumbnails AND trim points by video URL
//     static var videoCache: [String: CachedVideoData] = [:]
    
    @Published var showOverlay = false
    @Published var countdown = 5
    @Published var timer: Timer? = nil
    
    func startCountdown() {
        withAnimation{
            showOverlay = true
        }
        countdown = 3

        // Invalidate any existing timer
        timer?.invalidate()

        // Start countdown
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            Task { @MainActor in
                self.countdown -= 1
                if self.countdown <= 0 {
                    t.invalidate()
                    withAnimation {
                        self.showOverlay = false
                    }
                }
            }
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func resume() {
        player?.play()
        isPlaying = true
    }
    
    func CachedVideodata (){
        #if DEBUG
        print("cacheeeee video \(cacheStore.cache)")
        #endif
    }
    
    func getDuration(videoURL: URL?) async -> Double {
        guard let url = videoURL else { return 0 }

        let asset = AVAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            return seconds.isFinite ? seconds : 0
        } catch {
            #if DEBUG
            print("❌ Failed to read duration: \(error.localizedDescription)")
            #endif
            return 0
        }
    }
    func loadVideo(PHAsset: PHAsset?) async {
        guard let PHAsset else { return }

        self.isPlaying = false

        // Convert PHAsset → AVAsset
        if self.asset == nil {
            let options = PHVideoRequestOptions()
            options.version = .current
            options.isNetworkAccessAllowed = true

            await withCheckedContinuation { continuation in
                PHImageManager.default().requestAVAsset(forVideo: PHAsset, options: options) { avAsset, _, _ in
                    Task { @MainActor in
                        self.asset = avAsset
                        continuation.resume()
                    }
                }
            }
        }

        guard let asset = self.asset else { return }

        let cacheKey = PHAsset.localIdentifier

        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds
            self.duration = durationSeconds

            if let cachedData = cacheStore.cache[cacheKey] {
                self.thumbnails = cachedData.thumbnails
                self.startTime = cachedData.startTime
                self.endTime = cachedData.endTime
                self.duration = cachedData.duration
                self.trimDuration = cachedData.trimDuration
                self.isGeneratingThumbnails = false
            } else {
                self.startTime = 0
                self.endTime = min(durationSeconds, maxTrimDuration)
                self.trimDuration = self.endTime - self.startTime
                startThumbnailGeneration(for: asset, cacheKey: cacheKey)
            }
        } catch {
            #if DEBUG
            print("❌ Failed to load duration from AVAsset: \(error)")
            #endif
        }
    }

    func loadVideo(videoURL: URL?) async {
        guard let videoURL else { return }

        self.isPlaying = false

        if self.asset == nil {
            self.asset = AVAsset(url: videoURL)
        }

        let cacheKey = videoURL.absoluteString

        guard let asset = self.asset else { return }

        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds
            self.duration = durationSeconds

            if let cachedData = cacheStore.cache[cacheKey] {
                self.thumbnails = cachedData.thumbnails
                self.startTime = cachedData.startTime
                self.endTime = cachedData.endTime
                self.duration = cachedData.duration
                self.trimDuration = cachedData.trimDuration
                self.isGeneratingThumbnails = false
            } else {
                self.startTime = 0
                self.endTime = min(durationSeconds, maxTrimDuration)
                self.trimDuration = self.endTime - self.startTime
                startThumbnailGeneration(for: asset, cacheKey: cacheKey)
            }
        } catch {
            #if DEBUG
            print("❌ Failed to load asset: \(error)")
            #endif
        }
    }

    /// Kick off filmstrip generation without blocking playback (WhatsApp-style).
    private func startThumbnailGeneration(for asset: AVAsset, cacheKey: String) {
        thumbnailGenerationTask?.cancel()
        isGeneratingThumbnails = true

        let maxThumbnails = 20
        let count = min(max(Int(ceil(duration)), 1), maxThumbnails)
        let trimStart = startTime
        let trimEnd = endTime
        let trimDur = trimDuration
        let fullDuration = duration
        let store = cacheStore

        thumbnailGenerationTask = Task(priority: .userInitiated) { [weak self] in
            let images = await Self.generateThumbnailImages(
                for: asset,
                count: count,
                durationSeconds: fullDuration,
                onProgress: { partial in
                    Task { @MainActor in
                        guard let self, !Task.isCancelled else { return }
                        self.thumbnails = partial
                    }
                }
            )

            await MainActor.run {
                guard let self else { return }
                guard !Task.isCancelled else {
                    self.isGeneratingThumbnails = false
                    return
                }
                self.thumbnails = images
                self.isGeneratingThumbnails = false
                if !images.isEmpty {
                    store.cache[cacheKey] = CachedVideoData(
                        thumbnails: images,
                        startTime: trimStart,
                        endTime: trimEnd,
                        duration: fullDuration,
                        trimDuration: trimDur
                    )
                }
            }
        }
    }

    /// Generates filmstrip frames off the hot path; calls `onProgress` as frames arrive.
    nonisolated private static func generateThumbnailImages(
        for asset: AVAsset,
        count: Int,
        durationSeconds: Double,
        onProgress: @escaping @Sendable ([UIImage]) -> Void
    ) async -> [UIImage] {
        guard count > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 120)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        // Fast first frame so the strip isn't empty.
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            onProgress([UIImage(cgImage: cgImage)])
        }

        let safeDuration = durationSeconds > 0 ? durationSeconds : max(asset.duration.seconds, 1)
        let interval = safeDuration / Double(count)
        let times = (0..<count).map {
            NSValue(time: CMTime(seconds: Double($0) * interval, preferredTimescale: 600))
        }

        return await withCheckedContinuation { continuation in
            var slots = Array(repeating: Optional<UIImage>.none, count: count)
            var processedCount = 0
            let lock = NSLock()
            var didResume = false

            generator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, result, _ in
                lock.lock()
                defer { lock.unlock() }

                processedCount += 1

                if let cgImage, result == .succeeded {
                    let index = times.firstIndex(of: NSValue(time: requestedTime)) ?? 0
                    if index < slots.count {
                        slots[index] = UIImage(cgImage: cgImage)
                    }
                    onProgress(slots.compactMap { $0 })
                }

                if processedCount == times.count, !didResume {
                    didResume = true
                    continuation.resume(returning: slots.compactMap { $0 })
                }
            }
        }
    }

    func resetPlayer() {
        thumbnailGenerationTask?.cancel()
        thumbnailGenerationTask = nil
        isGeneratingThumbnails = false
        hasError = false
        isLoading = true
        player?.pause()
        player?.currentItem?.cancelPendingSeeks()
        player?.currentItem?.seek(to: .zero)
        player = nil
    }
    
    // Update cache with current trim points
    func updateCacheWithTrimPoints(for assetIdentifier: String?) {
        let cacheKey: String
        if let identifier = assetIdentifier {
            cacheKey = identifier
        } else if let urlAsset = self.asset as? AVURLAsset {
            cacheKey = urlAsset.url.absoluteString
        } else {
            return
        }
        
        guard !thumbnails.isEmpty else { return }
        
        let cachedData = CachedVideoData(
            thumbnails: thumbnails,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            trimDuration : trimDuration
        )
        
        cacheStore.cache[cacheKey] = cachedData
    }
    
    // Convenience method to get cache key for current asset
    func getCurrentCacheKey() -> String? {
        if let urlAsset = self.asset as? AVURLAsset {
            return urlAsset.url.absoluteString
        }
        return nil
    }
    
    // Clear cache for a specific video or all videos
    func clearCache(for identifier: String? = nil) {
        if let identifier = identifier {
            self.cacheStore.cache.removeValue(forKey: identifier)
        } else {
            self.cacheStore.cache.removeAll()
        }
    }

    func updateTrim(start: Double, end: Double,fromTrimimg: Bool = false,phAsset: PHAsset?) {
        let newStart = max(0, min(start, end))
        let newEnd = max(newStart, min(end, duration))

        startTime = newStart
        endTime = newEnd
        
        
        // Automatically update cache when trim changes
        updateCacheWithTrimPoints(for: phAsset?.localIdentifier ?? getCurrentCacheKey())

        guard let player = player else { return }

        let startCM = CMTime(seconds: newStart, preferredTimescale: 600)
        player.seek(to: startCM, toleranceBefore: .zero, toleranceAfter: .zero)
        player.actionAtItemEnd = .pause
        if fromTrimimg {
            player.play()
        }
    }
    
    func exportTrimmedVideo(
        to outputURL: URL,
        videoID: String,
        asset: AVAsset?,
        presetName: String = AVAssetExportPresetHighestQuality
    ) async -> Bool {
        guard let asset = asset else { return false }

        let cachedData = self.cacheStore.cache[videoID]
        let start = cachedData?.startTime ?? startTime
        let end = cachedData?.endTime ?? endTime

        await MainActor.run { isExporting = true }
        defer { Task { @MainActor in isExporting = false } }

        let composition = AVMutableComposition()

        guard
            let videoTrack = asset.tracks(withMediaType: .video).first,
            let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return false }

        let audioTrack = asset.tracks(withMediaType: .audio).first
        let compositionAudioTrack = audioTrack.flatMap {
            _ in composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        // 🔥 Use cached trimming range here
        let timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )

        do {
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

            if let audioTrack = audioTrack, let compositionAudioTrack = compositionAudioTrack {
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }

            try? FileManager.default.removeItem(at: outputURL)
        } catch {
            #if DEBUG
            print("Composition failed: \(error)")
            #endif
            return false
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName) else {
            return false
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        return await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                let success = exportSession.status == .completed

                #if DEBUG
                if !success {
                    print("❌ Export failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
                }
                #endif

                continuation.resume(returning: success)
            }
        }
    }
    
    // MARK: - Pre-generate thumbnails (called before entering editor)
    /// Pre-generates thumbnails for a PHAsset and stores them in the cache.
    /// This should be called during media preparation so thumbnails are ready
    /// when the editor screen opens (like WhatsApp).
    static func preGenerateThumbnails(
        for phAsset: PHAsset,
        cacheStore: VideoTrimCacheStore,
        maxTrimDuration: Double = StatusVideoTrimPolicy.maxDurationSeconds
    ) async {
        let cacheKey = phAsset.localIdentifier

        if cacheStore.cache[cacheKey] != nil { return }
        
        // Get AVAsset from PHAsset
        let options = PHVideoRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }
        
        guard let asset = avAsset else { return }
        
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds
            guard durationSeconds.isFinite, durationSeconds > 0 else { return }
            
            let maxThumbnails = 20
            let count = min(max(Int(ceil(durationSeconds)), 1), maxThumbnails)
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 120)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            
            let interval = durationSeconds / Double(count)
            let times = (0..<count).map {
                NSValue(time: CMTime(seconds: Double($0) * interval, preferredTimescale: 600))
            }
            
            let thumbnails: [UIImage] = await withCheckedContinuation { continuation in
                var generatedImages: [Int: UIImage] = [:]
                var processedCount = 0
                let lock = NSLock()
                
                generator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, _, _ in
                    lock.lock()
                    defer { lock.unlock() }
                    
                    processedCount += 1
                    
                    if let cgImage = cgImage {
                        let index = times.firstIndex(of: NSValue(time: requestedTime)) ?? 0
                        generatedImages[index] = UIImage(cgImage: cgImage)
                    }
                    
                    if processedCount == times.count {
                        let sorted = generatedImages.sorted(by: { $0.key < $1.key }).map { $0.value }
                        continuation.resume(returning: sorted)
                    }
                }
            }
            
            guard !thumbnails.isEmpty else { return }
            
            await MainActor.run {
                cacheStore.cache[cacheKey] = CachedVideoData(
                    thumbnails: thumbnails,
                    startTime: 0,
                    endTime: min(durationSeconds, maxTrimDuration),
                    duration: durationSeconds,
                    trimDuration: min(durationSeconds, maxTrimDuration)
                )
            }
        } catch {
            #if DEBUG
            print("❌ Pre-generation failed: \(error)")
            #endif
        }
    }

}
