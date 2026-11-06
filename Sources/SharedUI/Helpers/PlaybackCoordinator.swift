//
//  PlaybackCoordinator.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//


import Foundation
import SwiftUI
import AVFoundation
import Combine

public final class PlaybackCoordinator: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var isPlaying = false
    @Published var isDragging = false
    @Published var amplitudes: [CGFloat] = []
    @Published var playbackSpeed: Float = 1.0 // 1x, 1.5x, 2x

    var audioDuration: Double = 0

    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var audioURL: URL?
    
    // Available playback speeds (like WhatsApp)
    public static let availableSpeeds: [Float] = [1.0, 1.5, 2.0]

    private static let waveformCache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 200
        return cache
    }()

    init(audioDuration: Double = 0) {
        self.audioDuration = audioDuration
    }

    func loadAudio(from url: URL, cacheKey: String? = nil, precomputedWaveform: [Float]? = nil) {
        audioURL = url
        
        // Check if file is Opus format
        let isOpus = url.pathExtension.lowercased() == "opus"
        
        if isOpus {
            // Opus files need to be decoded first
            // For now, just load the waveform and duration from metadata
            // Actual playback will use fake playback until we implement decoding
            loadOpusMetadata(from: url, cacheKey: cacheKey, precomputedWaveform: precomputedWaveform)
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.enableRate = true // Enable playback rate control
            player?.rate = playbackSpeed // Set initial speed
            player?.prepareToPlay()
            audioDuration = player?.duration ?? 0
        } catch {
            #if DEBUG
            print("Error loading audio: \(error)")
            #endif
        }

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
    
    private func loadOpusMetadata(from url: URL, cacheKey: String?, precomputedWaveform: [Float]?) {
        // For Opus files, we can't use AVAudioPlayer
        // Use precomputed waveform and estimate duration from file size
        
        let key = (cacheKey ?? url.absoluteString) as NSString
        
        if let waveform = precomputedWaveform, !waveform.isEmpty {
            let cgAmps = waveform.map { CGFloat($0) }
            amplitudes = cgAmps
            Self.waveformCache.setObject(cgAmps as NSArray, forKey: key)
            
            // Estimate duration: ~3KB per second for Opus at default bitrate
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                audioDuration = Double(fileSize) / 3000.0 // Rough estimate
            }
        } else {
            // Try to extract waveform from Opus file
            Task.detached(priority: .utility) {
                let extracted = await WaveformExtractor.extract(from: url, barCount: 40)
                let cgAmps = extracted.map { CGFloat($0) }
                Self.waveformCache.setObject(cgAmps as NSArray, forKey: key)
                await MainActor.run { [weak self] in
                    self?.amplitudes = cgAmps
                }
            }
            
            // Estimate duration from file size
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                audioDuration = Double(fileSize) / 3000.0
            }
        }
        
        #if DEBUG
        print("⚠️ Opus playback not fully supported - using visual-only mode. Duration: \(audioDuration)s")
        #endif
    }

    func start() {
        guard let player = player else {
            startFakePlayback()
            return
        }

        isDragging = false
        isPlaying = true
        player.play()
        startProgressSync()
    }

    func pause() {
        isPlaying = false
        player?.pause()
        stopProgressSync()
    }

    func stop() {
        isPlaying = false
        player?.stop()
        stopProgressSync()
    }
    
    /// Cycle through playback speeds (1x → 1.5x → 2x → 1x)
    func cyclePlaybackSpeed() {
        let currentIndex = Self.availableSpeeds.firstIndex(of: playbackSpeed) ?? 0
        let nextIndex = (currentIndex + 1) % Self.availableSpeeds.count
        playbackSpeed = Self.availableSpeeds[nextIndex]
        
        // Apply to player if available
        player?.rate = playbackSpeed
        
        #if DEBUG
        print("🎵 Playback speed changed to \(playbackSpeed)x")
        #endif
    }
    
    /// Set specific playback speed
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.rate = speed
    }

    func seekTo(_ fraction: CGFloat) {
        guard let player = player else { return }
        let time = Double(fraction) * player.duration
        player.currentTime = time
        progress = fraction
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            player?.pause()
            stopProgressSync()
        } else {
            if let player = player {
                let time = Double(progress) * player.duration
                player.currentTime = time
                if isPlaying {
                    player.play()
                    startProgressSync()
                }
            }
        }
    }

    // MARK: - Progress sync with real player

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
        guard !isDragging, let player = player else { return }

        if player.isPlaying {
            let duration = player.duration
            guard duration > 0 else { return }
            progress = CGFloat(player.currentTime / duration)
        } else if isPlaying {
            progress = 0
            isPlaying = false
            player.stop()
            stopProgressSync()
        }
    }

    // MARK: - Fallback for when no audio file is available

    private func startFakePlayback() {
        guard audioDuration > 0 else { return }
        stopProgressSync()
        isDragging = false
        isPlaying = true
        displayLink = CADisplayLink(target: self, selector: #selector(updateFake))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateFake() {
        guard !isDragging else { return }
        let delta = CGFloat(1.0 / 60.0 / audioDuration)
        progress += delta

        if progress >= 1.0 {
            progress = 0.0
            isPlaying = false
            stopProgressSync()
        }
    }
}
