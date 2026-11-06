import Foundation
import SwiftUI
import AVFoundation
import Combine
import WaanguSharedUI

private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinished: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished?()
    }
}

public final class PlaybackCoordinator: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var isPlaying = false
    @Published var isDragging = false
    @Published var amplitudes: [CGFloat] = []
    @Published var playbackSpeed: Float = 1.0

    var audioDuration: Double = 0
    var messageId: String?

    private(set) var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var sourceURL: URL?
    private var loadedPlaybackURL: URL?
    private let playerDelegate = AudioPlayerDelegate()

    weak var globalManager: GlobalAudioPlaybackManager?

    static let availableSpeeds: [Float] = [1.0, 1.5, 2.0]

    private static let waveformCache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 200
        return cache
    }()

    init(audioDuration: Double = 0) {
        self.audioDuration = audioDuration
        playerDelegate.onFinished = { [weak self] in
            self?.handlePlaybackFinished()
        }
    }

    var isOpusSource: Bool {
        sourceURL?.pathExtension.lowercased() == "opus"
    }

    var hasPlayablePlayer: Bool {
        player != nil && loadedPlaybackURL?.pathExtension.lowercased() != "opus"
    }

    func loadAudio(from url: URL, cacheKey: String? = nil, precomputedWaveform: [Float]? = nil, audioID: String? = nil) {
        sourceURL = url
        let isOpus = url.pathExtension.lowercased() == "opus"

        if !isOpus {
            installPlayer(from: url)
        }

        loadWaveform(for: url, cacheKey: cacheKey, precomputedWaveform: precomputedWaveform)
    }

    func installDecodedPlayer(from wavURL: URL, cacheKey: String? = nil, precomputedWaveform: [Float]? = nil) {
        loadedPlaybackURL = wavURL
        installPlayer(from: wavURL)
        loadWaveform(for: wavURL, cacheKey: cacheKey, precomputedWaveform: precomputedWaveform)
    }

    func start() {
        guard let player else {
            startFakePlayback()
            return
        }

        isDragging = false
        isPlaying = true

        if player.duration > 0 {
            player.currentTime = Double(progress) * player.duration
        }

        player.rate = playbackSpeed
        player.play()
        startProgressSync()
        notifyGlobalManager { $0.updatePlayingState(true) }
    }

    func pause() {
        isPlaying = false
        player?.pause()
        stopProgressSync()

        if let player, player.duration > 0 {
            progress = CGFloat(player.currentTime / player.duration)
        }

        notifyGlobalManagerIfActive { manager in
            manager.updatePlayingState(false)
            manager.updateProgress(self.progress)
        }
    }

    func stop() {
        isPlaying = false
        player?.pause()
        stopProgressSync()
    }

    func cyclePlaybackSpeed() {
        let currentIndex = Self.availableSpeeds.firstIndex(of: playbackSpeed) ?? 0
        let nextIndex = (currentIndex + 1) % Self.availableSpeeds.count
        playbackSpeed = Self.availableSpeeds[nextIndex]
        player?.rate = playbackSpeed
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.rate = speed
    }

    func seekTo(_ fraction: CGFloat) {
        let clamped = max(0, min(1, fraction))
        if let player, player.duration > 0 {
            player.currentTime = Double(clamped) * player.duration
        }
        progress = clamped

        if !isDragging {
            notifyGlobalManagerIfActive { $0.updateProgress(clamped) }
        }
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            player?.pause()
            stopProgressSync()
        } else {
            if let player, player.duration > 0 {
                player.currentTime = Double(progress) * player.duration
                if isPlaying {
                    player.play()
                    startProgressSync()
                }
            }
            notifyGlobalManagerIfActive { $0.updateProgress(self.progress) }
        }
    }

    // MARK: - Private

    private func installPlayer(from url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = playerDelegate
            newPlayer.enableRate = true
            newPlayer.rate = playbackSpeed
            newPlayer.prepareToPlay()

            player = newPlayer
            loadedPlaybackURL = url
            audioDuration = newPlayer.duration
        } catch {
            #if DEBUG
            print("Error loading audio: \(error)")
            #endif
            player = nil
        }
    }

    private func loadWaveform(for url: URL, cacheKey: String?, precomputedWaveform: [Float]?) {
        let key = (cacheKey ?? url.absoluteString) as NSString

        if let waveform = precomputedWaveform, !waveform.isEmpty {
            let cgAmps = waveform.map { CGFloat($0) }
            amplitudes = cgAmps
            Self.waveformCache.setObject(cgAmps as NSArray, forKey: key)
            return
        }

        if let cached = Self.waveformCache.object(forKey: key) as? [CGFloat] {
            amplitudes = cached
            return
        }

        Task.detached(priority: .utility) {
            let extracted = await WaveformExtractor.extract(from: url, barCount: 40)
            let cgAmps = extracted.map { CGFloat($0) }
            Self.waveformCache.setObject(cgAmps as NSArray, forKey: key)
            await MainActor.run { [weak self] in
                self?.amplitudes = cgAmps
            }
        }
    }

    private func handlePlaybackFinished() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.progress = 0
            self.isPlaying = false
            self.stopProgressSync()
            self.notifyGlobalManagerIfActive { $0.updatePlayingState(false) }
        }
    }

    private func startProgressSync() {
        stopProgressSync()
        displayLink = CADisplayLink(target: self, selector: #selector(syncProgress))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopProgressSync() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func syncProgress() {
        guard !isDragging, let player, player.isPlaying, player.duration > 0 else { return }

        let newProgress = CGFloat(player.currentTime / player.duration)
        if abs(newProgress - progress) > 0.001 {
            progress = newProgress
            notifyGlobalManagerIfActive { $0.updateProgress(self.progress) }
        }
    }

    private func notifyGlobalManagerIfActive(_ action: @escaping @MainActor (GlobalAudioPlaybackManager) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, let globalManager = self.globalManager else { return }
            guard let messageId = self.messageId,
                  globalManager.currentlyPlayingAudio?.messageId == messageId else { return }
            action(globalManager)
        }
    }

    private func notifyGlobalManager(_ action: @escaping @MainActor (GlobalAudioPlaybackManager) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, let globalManager = self.globalManager else { return }
            action(globalManager)
        }
    }

    private func startFakePlayback() {
        guard audioDuration > 0 else { return }
        stopProgressSync()
        isDragging = false
        isPlaying = true
        displayLink = CADisplayLink(target: self, selector: #selector(updateFake))
        displayLink?.add(to: .main, forMode: .common)
        notifyGlobalManager { $0.updatePlayingState(true) }
    }

    @objc private func updateFake() {
        guard !isDragging else { return }
        let delta = CGFloat(1.0 / 60.0 / audioDuration)
        progress += delta
        notifyGlobalManagerIfActive { $0.updateProgress(self.progress) }

        if progress >= 1.0 {
            progress = 0
            isPlaying = false
            stopProgressSync()
            notifyGlobalManagerIfActive { $0.updatePlayingState(false) }
        }
    }
}
