import SwiftUI
import AVKit
import Photos
import WaanguCoreKit

@available(iOS 16.0, *)
@MainActor
struct CustomVideoPlayer: View {
    // MARK: - Parameters
    var url: URL? = nil
    var phAsset: PHAsset? = nil
    var isPHAsset: Bool = false
    var autoPlay: Bool = true
    var showsControls: Bool = true
    var loop: Bool = false
    var fromServer: Bool = true
    var cornerRadius: CGFloat = 0
    var contentMode: ContentMode = .fit
    var mute: Bool = false
    var onFinished: (() -> Void)? = nil
    var showLoader: Bool = true
    var loaderColor: Color = .white
    var backgroundColor: Color = .black.opacity(0.9)
    var OnStartPlaying : ((_ duration:Double)-> Void)? = nil
    var OnReadyPlaying : (()-> Void)? = nil
    @ObservedObject var controller: VideoPlayerController

    // MARK: - State
    @State private var playerTimeObserver: Any?
    @State private var playerStatusObserver: NSKeyValueObservation?
    @State private var timeControlObserver: NSKeyValueObservation?
    @State private var endTimeObserver: NSObjectProtocol?
    @State private var currentURL: URL?
    @State private var observedPlayer: AVPlayer? // Track which player has the observer

    var body: some View {
        if #available(iOS 17.0, *) {
            ZStack {
                
                // Background
                backgroundColor.ignoresSafeArea()
                
                // Player display
                if let player = controller.player {
                    if showsControls {
                        VideoPlayer(player: player)
                            .cornerRadius(cornerRadius)
                            .aspectRatio(contentMode: contentMode)
                            .opacity(controller.isLoading ? 0 : 1)
                            .id(url) // Force recreation when URL changes
                            .frame(width:UIScreen.main.bounds.width).clipped()
                        
                    } else {
                        StoryVideoView(player: player)
                            .cornerRadius(cornerRadius)
                            .aspectRatio(contentMode: contentMode)
                            .opacity(controller.isLoading ? 0 : 1)
                            .id(url) // Force recreation when URL changes
                    }
                }
                
                // Loader overlay
                if showLoader && controller.isLoading {
                    AnimatedSpinner(StrokeColor: .white, lineWidth: 5, size: 70)
                }
            }
            .animation(.easeOut(duration: 0.25), value: controller.isLoading)
            .onAppear {
                Task {
                    await setupPlayer()
                }
            }
            .onChange(of: url) { oldUrl, newURL in
                debugLog("🔄 URL changed, reloading player old \(oldUrl)  new \(newURL)")
                cleanupPlayer()
                Task {
                    await setupPlayer()
                }
            }
            .onDisappear {
                cleanupPlayer()
            }
        } else {
            // Fallback on earlier versions
            ZStack {
                
                // Background
                backgroundColor.ignoresSafeArea()
                
                // Player display
                if let player = controller.player {
                    if showsControls {
                        VideoPlayer(player: player)
                            .cornerRadius(cornerRadius)
                            .aspectRatio(contentMode: contentMode)
                            .opacity(controller.isLoading ? 0 : 1)
                            .id(url) // Force recreation when URL changes
                            .frame(width:UIScreen.main.bounds.width).clipped()
                        
                    } else {
                        StoryVideoView(player: player)
                            .cornerRadius(cornerRadius)
                            .aspectRatio(contentMode: contentMode)
                            .opacity(controller.isLoading ? 0 : 1)
                            .id(url) // Force recreation when URL changes
                    }
                }
                
                // Loader overlay
                if showLoader && controller.isLoading {
                    AnimatedSpinner(StrokeColor: .white, lineWidth: 5, size: 70)
                }
            }
            .animation(.easeOut(duration: 0.25), value: controller.isLoading)
            .onAppear {
                Task {
                    await setupPlayer()
                }
            }
            .onChange(of: url) { newURL in
                debugLog("🔄 URL changed, reloading player  new \(newURL)")
                cleanupPlayer()
                Task {
                    await setupPlayer()
                }
            }
            .onDisappear {
                cleanupPlayer()
            }
        }
    }

    // MARK: - Player Setup
    private func setupPlayer() async {
        debugLog("🔥pass here it looks like it going to start loading video")
        // Prevent re-setup if URL hasn't changed
//        guard currentURL != url else { return }

//        print("🎬 Loading video from: \(url.absoluteString)")

        // Reset states
        controller.isLoading = true
        controller.hasError = false
        controller.isPlaying = false
        currentURL = url

        var newPlayer: AVPlayer!
        var playerItem: AVPlayerItem!
        var duration: Double = 0

        if self.fromServer {
            guard let url else {
                controller.isLoading = false
                controller.hasError = true
                return
            }
            // Load from server URL
            playerItem = AVPlayerItem(url: url)
            newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.isMuted = mute
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            controller.player = newPlayer
            duration = await controller.getDuration(videoURL: currentURL)
        } else {
            // Load from local asset
            let asset : AVAsset
            if isPHAsset {
                guard let phAsset else {
                    debugLog("🔥pass here it looks like PHAsset is not exist")
                    fatalError("PHAsset is nil")}
                debugLog("🔥pass here it looks like PHAsset is exist")
                let avAsset = await withCheckedContinuation { continuation in
                    let options = PHVideoRequestOptions()
                    options.version = .original
                    options.isNetworkAccessAllowed = true

                    PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                        continuation.resume(returning: asset)
                    }
                }
            guard let avAsset else { fatalError("Failed to load AVAsset from PHAsset") }
             asset = avAsset
                debugLog("🔥pass here it looks like PHAsset is assigned to avAsset \(avAsset)")
            }else{
                guard let url  else { fatalError("URL is nil") }
                // Load from local asset
                 asset = AVAsset(url: url)
            }
           
            controller.asset = asset
            playerItem = AVPlayerItem(asset: asset)
            newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.isMuted = mute
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            controller.player = newPlayer
            debugLog("🔥pass here it looks like it looks like AVAsset is assigned to newPlayer")
            // Load metadata (duration, timescale, etc.)
            if isPHAsset {
                await controller.loadVideo(PHAsset: phAsset)
            } else {
                await controller.loadVideo(videoURL: url)
            }

            // Ensure we start at the correct trim start
            let startTime = CMTime(seconds: controller.startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            await controller.player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)

            // Remove old observer from the OLD player (if it exists)
            if let existingObserver = self.playerTimeObserver, let oldPlayer = self.observedPlayer {
                oldPlayer.removeTimeObserver(existingObserver)
                self.playerTimeObserver = nil
                self.observedPlayer = nil
            }

            // Add new time observer to the NEW player
            let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            self.playerTimeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
               
                // ✅ Ignore updates if not playing
                guard self.controller.isPlaying else { return }
                debugLog("🔥pass here it looks like controller is updated")
                let currentSeconds = time.seconds
                self.controller.currentTime = currentSeconds

                // Calculate trim progress
                let relativeTime = currentSeconds - self.controller.startTime
                let trimmedDuration = self.controller.endTime - self.controller.startTime
                let trimWidth = CGFloat(trimmedDuration / self.controller.timePerPixel)
                let progress = max(0, min(relativeTime / trimmedDuration, 1.0))
                let trimX = CGFloat(self.controller.startTime / self.controller.timePerPixel)
                let playheadX = trimX + trimWidth * CGFloat(progress)
                self.controller.trimProgress = playheadX

//                print("⏱ progress \(progress) trimWidth \(trimWidth) playhead \(playheadX) trimX \(trimX) currentSec \(currentSeconds)")

                // Stop playback when exceeding trim end
                if currentSeconds >= self.controller.endTime {
                    newPlayer.pause()
                    self.controller.isPlaying = false

                    // Snap to start time
                    let startCMTime = CMTime(seconds: self.controller.startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    newPlayer.seek(to: startCMTime)
                    // Snap to end time
//                    let endCMTime = CMTime(seconds: self.controller.endTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
//                    newPlayer.seek(to: endCMTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            
            // Track which player this observer belongs to
            self.observedPlayer = newPlayer
            debugLog("🔥pass here it looks like new player is assigned to  observer")
            // Observe end of playback
            endTimeObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                debugLog("🏁 Playback finished")

                let startCMTime = CMTime(seconds: self.controller.startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                newPlayer.seek(to: startCMTime)

                if self.loop {
                    newPlayer.play()
                } else {
                    self.controller.isPlaying = false
                    self.onFinished?()
                }
            }
        }

        // Observe player status safely
        playerStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
//                    print("✅ Video ready to play: \(self.url.lastPathComponent)")
                    self.controller.isLoading = false
                    self.controller.hasError = false
                    self.OnReadyPlaying?()
                    // AutoPlay only after ready & seeked
                    if self.autoPlay {
                        if self.fromServer {
                            newPlayer.play()
                            self.controller.isPlaying = true
                            self.OnStartPlaying?(duration)
                        } else {
                            Task {
                                let startCMTime = CMTime(seconds: self.controller.startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                                await self.controller.player?.seek(to: startCMTime, toleranceBefore: .zero, toleranceAfter: .zero)
                                self.controller.player?.play()
                                self.controller.isPlaying = true
                                self.OnStartPlaying?(controller.duration)
                            }
                        }
                    }

                case .failed:
                    debugLog("❌ Failed to load video: \(item.error?.localizedDescription ?? "Unknown error")")
                    self.controller.isLoading = false
                    self.controller.hasError = true

                case .unknown:
                    debugLog("⏳ Player status unknown")

                @unknown default:
                    debugLog("⚠️ Unknown player status")
                }
            }
        }

        // Observe play/pause state changes
        timeControlObserver?.invalidate()
        timeControlObserver = controller.player?.observe(\.timeControlStatus, options: [.new, .initial]) { _, _ in
            DispatchQueue.main.async {
                switch self.controller.player?.timeControlStatus {
                case .playing:
                    self.controller.isPlaying = true
                case .paused:
                    self.controller.isPlaying = false
                default:
                    break
                }
            }
        }
    }

    // MARK: - Cleanup
    private func cleanupPlayer() {
        debugLog("🧹 Cleaning up player")
        
        // Remove time observer from the correct player instance
        if let observer = playerTimeObserver, let player = observedPlayer {
            player.removeTimeObserver(observer)
            playerTimeObserver = nil
            observedPlayer = nil
        }
        
        // Pause and clear player
        controller.player?.pause()
        controller.player?.replaceCurrentItem(with: nil)
        
        // Remove observers
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }
        
        controller.player = nil
        currentURL = nil
    }
}

// MARK: - Story Video View (no controls)
struct StoryVideoView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Always update the player layer when player changes
        if context.coordinator.playerLayer?.player !== player {
            // Remove old layer
            context.coordinator.playerLayer?.removeFromSuperlayer()
            context.coordinator.playerLayer = nil
            
            // Create new layer if player exists
            if let player = player {
                let playerLayer = AVPlayerLayer(player: player)
                playerLayer.videoGravity = .resizeAspectFill
                playerLayer.frame = uiView.bounds
                uiView.layer.addSublayer(playerLayer)
                context.coordinator.playerLayer = playerLayer
            }
        } else {
            // Just update frame if same player
            context.coordinator.playerLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}
