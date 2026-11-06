import Foundation
import SwiftUI
import Combine
import WaanguCoreKit

/// Global manager for audio playback across the app (WhatsApp-style)
@MainActor
public class GlobalAudioPlaybackManager: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = GlobalAudioPlaybackManager()
    
    // MARK: - Published Properties
    @Published public var currentlyPlayingAudio: PlayingAudioInfo?
    @Published public var showMiniPlayer: Bool = false
    @Published public var playbackQueue: [PlayingAudioInfo] = [] // Queue of consecutive voice notes
    
    // MARK: - Private Properties
    private var coordinators: [String: PlaybackCoordinator] = [:] // Cache coordinators by message ID
    private var currentChatRoomId: String? // Track which chat room user is viewing
    private var allMessages: [MessageDataItem] = [] // All messages in current chat
    private var progressSyncTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Chat Room Tracking
    
    /// Set current chat room (call when entering chat)
    public func setCurrentChatRoom(_ chatRoomId: String?, messages: [MessageDataItem] = []) {
        self.currentChatRoomId = chatRoomId
        self.allMessages = messages
        updateMiniPlayerVisibility()
    }
    
    /// Clear current chat room (call when leaving chat)
    public func clearCurrentChatRoom() {
        self.currentChatRoomId = nil
        self.allMessages = []
        updateMiniPlayerVisibility()
    }
    
    /// Update mini player visibility based on current chat
    private func updateMiniPlayerVisibility() {
        // Show mini player only if:
        // 1. Audio is playing
        // 2. User is NOT in the same chat room
        if let audio = currentlyPlayingAudio {
            let shouldShow = (currentChatRoomId != audio.chatRoomId)
            if showMiniPlayer != shouldShow {
                showMiniPlayer = shouldShow
                #if DEBUG
                print("🎵 Mini player visibility: \(shouldShow ? "SHOW" : "HIDE") (currentChat: \(currentChatRoomId ?? "nil"), audioChat: \(audio.chatRoomId))")
                #endif
            }
        } else {
            if showMiniPlayer {
                showMiniPlayer = false
                #if DEBUG
                print("🎵 Mini player visibility: HIDE (no audio playing)")
                #endif
            }
        }
    }
    
    // MARK: - Queue Management
    
    /// Build playback queue for consecutive voice notes
    private func buildPlaybackQueue(startingFrom messageId: String) {
        playbackQueue.removeAll()
        
        // Find the starting message index
        guard let startIndex = allMessages.firstIndex(where: { $0.id == messageId }) else {
            debugLog("🎵 Could not find starting message in queue")
            return
        }
        
        // Look ahead for consecutive voice messages (no text messages in between)
        var currentIndex = startIndex + 1
        while currentIndex < allMessages.count {
            let message = allMessages[currentIndex]
            
            // Check if it's a voice message. A view-once one is only ever played
            // in its viewer, never queued up from the thread.
            if (message.typeMessage == .AUDIO || message.typeMessage == .VOICE) && !message.isViewOnce {
                // Check if there's an audio URL
                if let audioURL = getAudioURL(for: message) {
                    let audioInfo = PlayingAudioInfo(
                        messageId: message.id,
                        audioURL: audioURL,
                        duration: message.message.audioDuration ?? 0,
                        waveform: message.message.waveform,
                        senderName: message.senderName,
                        chatName: "Chat", // We don't have chat name in message
                        chatRoomId: message.receiverId,
                        isPlaying: false,
                        progress: 0,
                        playbackSpeed: currentlyPlayingAudio?.playbackSpeed ?? 1.0
                    )
                    playbackQueue.append(audioInfo)
                    currentIndex += 1
                } else {
                    break // No audio URL, stop queue
                }
            } else {
                // Non-voice message found, stop building queue
                break
            }
        }
        
        debugLog("🎵 Built playback queue with \(playbackQueue.count) voice notes")
    }
    
    /// Get audio URL for a message
    private func getAudioURL(for message: MessageDataItem) -> URL? {
        guard let raw = message.message.audio?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let originalURL: URL? = if let url = URL(string: raw), url.scheme != nil {
            url
        } else {
            URL(fileURLWithPath: raw)
        }
       
        // Check if file exists
        if let url = originalURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // Try to load from disk
        if !message.codeMessage.isEmpty {
            let fileName = message.codeMessage
            if let diskURL = DiskMediaManager.shared.loadAudioFromDisk(
                fileName: fileName,
                ext: "opus",
                pathName: .CHAT
            ) {
                return diskURL
            }
        }
        
        return originalURL
    }
    
    /// Play next audio in queue
    private func playNextInQueue() {
        guard !playbackQueue.isEmpty else {
            debugLog("🎵 Queue empty, stopping playback")
            stop()
            return
        }
        
        let nextAudio = playbackQueue.removeFirst()
        debugLog("🎵 Auto-playing next audio: \(nextAudio.messageId)")
        
        // Notify that we want to play this audio
        // The BubbleVoiceView will handle the actual playback
        NotificationCenter.default.post(
            name: .autoPlayNextAudio,
            object: nil,
            userInfo: ["messageId": nextAudio.messageId]
        )
    }
    
    // MARK: - Public Methods
    
    /// Returns the cached coordinator for a message, if one exists.
    public func coordinator(for messageId: String) -> PlaybackCoordinator? {
        coordinators[messageId]
    }
    
    /// Get or create coordinator for a message
    public func getCoordinator(for messageId: String, audioDuration: Double = 0) -> PlaybackCoordinator {
        if let existing = coordinators[messageId] {
            existing.globalManager = self
            existing.messageId = messageId
            return existing
        }

        let coordinator = PlaybackCoordinator(audioDuration: audioDuration)
        coordinator.globalManager = self
        coordinator.messageId = messageId
        coordinators[messageId] = coordinator
        return coordinator
    }
    
    /// Start playing audio (pauses any currently playing audio)
    func play(
        audioInfo: PlayingAudioInfo,
        coordinator: PlaybackCoordinator?,
        buildQueue: Bool = true
    ) {
        // Pause previous audio if different
        if let current = currentlyPlayingAudio,
           current.messageId != audioInfo.messageId {
            if let prevCoordinator = coordinators[current.messageId] {
                prevCoordinator.pause()
            }
        }
        
        // Update state
        currentlyPlayingAudio = audioInfo
        
        // Store coordinator
        if let coordinator = coordinator {
            coordinator.messageId = audioInfo.messageId
            coordinators[audioInfo.messageId] = coordinator
        }
        
        // Build queue if requested
        if buildQueue {
            buildPlaybackQueue(startingFrom: audioInfo.messageId)
        }
        
        updateMiniPlayerVisibility()
        startProgressSync()
        
        // Start playback
        coordinator?.start()
    }
    
    /// Pause current audio
    public func pause() {
        guard let audio = currentlyPlayingAudio else { return }
        
        if let coordinator = coordinators[audio.messageId] {
            coordinator.pause()
        }
        
        if var updatedAudio = currentlyPlayingAudio {
            updatedAudio.isPlaying = false
            currentlyPlayingAudio = updatedAudio
        }
    }
    
    /// Seek the currently playing audio to a normalized position (0…1).
    public func seek(to fraction: CGFloat) {
        guard let audio = currentlyPlayingAudio,
              let coordinator = coordinators[audio.messageId] else { return }

        coordinator.seekTo(fraction)
        updateProgress(coordinator.progress)
    }

    /// Resume current audio
    public func resume() {
        guard let audio = currentlyPlayingAudio else { return }
        
        if let coordinator = coordinators[audio.messageId] {
            coordinator.start()
        }
        
        // Update state
        if var updatedAudio = currentlyPlayingAudio {
            updatedAudio.isPlaying = true
            currentlyPlayingAudio = updatedAudio
        }
    }
    
    /// Stop and clear current audio
    public func stop() {
        if let audio = currentlyPlayingAudio,
           let coordinator = coordinators[audio.messageId] {
            coordinator.stop()
        }
        
        currentlyPlayingAudio = nil
        playbackQueue.removeAll()
        stopProgressSync()
        updateMiniPlayerVisibility()
    }
    
    // MARK: - Progress Sync
    
    /// Keeps `currentlyPlayingAudio.progress` in sync with the active coordinator,
    /// independent of whether a BubbleVoiceView is on screen.
    private func startProgressSync() {
        stopProgressSync()
        progressSyncTask = Task { @MainActor in
            while !Task.isCancelled {
                syncProgressFromActiveCoordinator()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
    
    private func stopProgressSync() {
        progressSyncTask?.cancel()
        progressSyncTask = nil
    }
    
    private func syncProgressFromActiveCoordinator() {
        guard var audio = currentlyPlayingAudio,
              let coordinator = coordinators[audio.messageId] else { return }
        
        let progress = coordinator.progress
        let isPlaying = coordinator.isPlaying
        var didChange = false
        
        if abs(audio.progress - progress) > 0.001 {
            audio.progress = progress
            didChange = true
        }
        if audio.isPlaying != isPlaying {
            audio.isPlaying = isPlaying
            didChange = true
        }
        if didChange {
            currentlyPlayingAudio = audio
        }
    }
    
    /// Update progress (called by coordinator)
    public func updateProgress(_ progress: CGFloat) {
        guard var audio = currentlyPlayingAudio else { return }
        
        // Only update if changed significantly to avoid excessive UI updates
        if abs(audio.progress - progress) > 0.001 {
            audio.progress = progress
            currentlyPlayingAudio = audio
            #if DEBUG
            // Periodic logging (every ~10% progress)
            if Int(progress * 10) != Int((audio.progress - progress) * 10) {
                print("🎵 Mini player progress updated: \(Int(progress * 100))%")
            }
            #endif
        }
    }
    
    /// Update playing state (called by coordinator)
    public func updatePlayingState(_ isPlaying: Bool) {
        guard var audio = currentlyPlayingAudio else { return }
        
        // Only update if state actually changed
        if audio.isPlaying != isPlaying {
            audio.isPlaying = isPlaying
            currentlyPlayingAudio = audio
            
            #if DEBUG
            print("🎵 Mini player state updated: isPlaying=\(isPlaying)")
            #endif
            
            // When audio finishes, play next in queue or hide mini player
            if !isPlaying && audio.progress >= 0.99 {
                if !playbackQueue.isEmpty {
                    // Auto-play next audio after a short delay
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                        self.playNextInQueue()
                    }
                } else {
                    // No more audios, stop
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        self.stop()
                    }
                }
            }
        }
    }
    
    /// Cycle playback speed
    public func cyclePlaybackSpeed() {
        guard let audio = currentlyPlayingAudio else { return }
        
        if let coordinator = coordinators[audio.messageId] {
            coordinator.cyclePlaybackSpeed()
            
            if var updatedAudio = currentlyPlayingAudio {
                updatedAudio.playbackSpeed = coordinator.playbackSpeed
                currentlyPlayingAudio = updatedAudio
            }
        }
    }
    
    /// Clear coordinator cache (call when leaving chat or on memory warning)
    public func clearCoordinatorCache() {
        // Keep only the currently playing coordinator
        if let currentAudio = currentlyPlayingAudio {
            let currentCoordinator = coordinators[currentAudio.messageId]
            coordinators.removeAll()
            if let coordinator = currentCoordinator {
                coordinators[currentAudio.messageId] = coordinator
            }
        } else {
            coordinators.removeAll()
        }
    }
}

// MARK: - Playing Audio Info

public struct PlayingAudioInfo: Equatable {
    public let messageId: String
    public let audioURL: URL
    public let duration: TimeInterval
    public let waveform: [Float]?
    public let senderName: String
    public let chatName: String
    public let chatRoomId: String // Track which chat this audio belongs to
    public var isPlaying: Bool
    public var progress: CGFloat
    public var playbackSpeed: Float
    
    public init(
        messageId: String,
        audioURL: URL,
        duration: TimeInterval,
        waveform: [Float]?,
        senderName: String,
        chatName: String,
        chatRoomId: String,
        isPlaying: Bool = true,
        progress: CGFloat = 0,
        playbackSpeed: Float = 1.0
    ) {
        self.messageId = messageId
        self.audioURL = audioURL
        self.duration = duration
        self.waveform = waveform
        self.senderName = senderName
        self.chatName = chatName
        self.chatRoomId = chatRoomId
        self.isPlaying = isPlaying
        self.progress = progress
        self.playbackSpeed = playbackSpeed
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let autoPlayNextAudio = Notification.Name("autoPlayNextAudio")
}
