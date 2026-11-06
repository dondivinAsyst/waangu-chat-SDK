import SwiftUI
import Combine
import WaanguSharedUI
import WaanguCoreKit
import UIKit

struct BubbleVoiceView: View {
    let message: MessageDataItem
    @ObservedObject var uploadVM: FileUploadViewModel
    let isSelectionMode: Bool
    let opusPlaybackService: any OpusPlaybackServiceProtocol
    let chatRoomId: String
    let globalAudioManager: GlobalAudioPlaybackManager
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel

    private let barCount = 40
    private let barWidth: CGFloat = 3
    private let waveformMinWidth: CGFloat = 130
    private let waveformHeight: CGFloat = 30
    /// One slot for the control in every state — play, transfer arrow, progress
    /// ring — the size of the avatar beside it. It used to be 28, 40 or 56 pt
    /// depending on the state, so the waveform moved sideways on each change.
    private let controlSlotSize: CGFloat = 36

    @ObservedObject private var playback: PlaybackCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var isDecodingOpus = false
    @State private var autoPlayObserver: NSObjectProtocol?

    private var transferConfig: InlineMediaTransferConfig {
        .voice(
            message: message,
            localFileURL: localUploadURL,
            onUploadSuccess: { [codeMessage = message.codeMessage] remoteUrl in
                chatVM.clearPendingUpload(codeMessage: codeMessage, remoteUrl: remoteUrl)
            },
            onAutoTransferAttempt: { [codeMessage = message.codeMessage] attempts in
                chatVM.persistAutoTransferAttempts(codeMessage: codeMessage, attempts: attempts)
            }
        )
    }

    private var isOutgoing: Bool { message.direction == .sent }

    private var showSpeedInsteadOfAvatar: Bool {
        playback.isPlaying || playback.playbackSpeed != 1.0
    }

    private var avatarImageUrl: String? {
        if isOutgoing {
            return message.senderAvatar ?? CurrentSessionInfo.shared.userProfile
        }
        return message.senderAvatar
    }

    init(
        message: MessageDataItem,
        uploadVM: FileUploadViewModel,
        isSelectionMode: Bool,
        opusPlaybackService: any OpusPlaybackServiceProtocol,
        chatRoomId: String,
        globalAudioManager: GlobalAudioPlaybackManager,
        chatVM: ChatRoomViewModel
    ) {
        self.message = message
        self.uploadVM = uploadVM
        self.isSelectionMode = isSelectionMode
        self.opusPlaybackService = opusPlaybackService
        self.chatRoomId = chatRoomId
        self.globalAudioManager = globalAudioManager
        self.chatVM = chatVM

        let audioDuration = message.message.audioDuration ?? 0
        self.playback = globalAudioManager.getCoordinator(for: message.id, audioDuration: audioDuration)
    }

    private var audioURL: URL? {
        let raw = message.message.audio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let originalURL: URL? = if !raw.isEmpty {
            if let url = URL(string: raw), url.scheme != nil {
                url
            } else {
                URL(fileURLWithPath: raw)
            }
        } else {
            nil
        }

        if let url = originalURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

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

        let ext = Self.resolveExtension(from: message.message.fileName, fallbackURL: originalURL)

        if !ext.isEmpty, !message.codeMessage.isEmpty,
           let diskURL = DiskMediaManager.shared.loadFileFromDisk(
               fileName: message.codeMessage, ext: ext, pathName: .CHAT
           ) {
            return diskURL
        }

        if let storedName = originalURL?.deletingPathExtension().lastPathComponent,
           !storedName.isEmpty, !ext.isEmpty,
           let diskURL = DiskMediaManager.shared.loadFileFromDisk(
               fileName: storedName, ext: ext, pathName: .CHAT
           ) {
            return diskURL
        }

        return originalURL
    }

    private static func resolveExtension(from fileName: String?, fallbackURL: URL?) -> String {
        if let name = fileName {
            let e = (name as NSString).pathExtension.lowercased()
            if !e.isEmpty { return e }
        }
        return fallbackURL?.pathExtension.lowercased() ?? ""
    }

    /// Stable on-disk URL for upload — never uses remote or stale temp paths.
    private var localUploadURL: URL? {
        guard let url = audioURL, url.isFileURL else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var currentTime: Double {
        Double(playback.progress) * playback.audioDuration
    }

    private var displayAmplitudes: [CGFloat] {
        let amps = playback.amplitudes
        if amps.isEmpty {
            return [CGFloat](repeating: 0.15, count: barCount)
        }
        if amps.count == barCount { return amps }
        if amps.count > barCount {
            let chunkSize = Double(amps.count) / Double(barCount)
            return (0..<barCount).map { i in
                let start = Int(Double(i) * chunkSize)
                let end = min(Int(Double(i + 1) * chunkSize), amps.count)
                let chunk = amps[start..<end]
                return chunk.reduce(0, +) / CGFloat(chunk.count)
            }
        }
        return (0..<barCount).map { i in
            amps[min(Int(CGFloat(i) / CGFloat(barCount) * CGFloat(amps.count)), amps.count - 1)]
        }
    }

    private var isTransferFailed: Bool {
        message.message.shouldRetry == true && message.message.shouldUploadDownload == false
    }

    private var canSeekWaveform: Bool {
        guard !isSelectionMode else { return false }
        if isOutgoing {
            return !message.message.shouldUploadDownload && !message.message.shouldRetry
        }
        return audioURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                if isOutgoing {
                    if isTransferFailed {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.red)
                            .font(.headline)
                    } else {
                        VStack(spacing: 8) {
                            bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
                        }
                    }
                }
                if isOutgoing { Spacer(minLength: 0) }

                bubbleContent

                if !isOutgoing {
                    if isTransferFailed {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.red)
                            .font(.headline)
                    } else {
                        VStack(spacing: 8) {
                            bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.alignment)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, isOutgoing ? 60 : 5)
        .padding(.trailing, isOutgoing ? 5 : 60)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .id(message.id)
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .onChange(of: globalAudioManager.currentlyPlayingAudio?.messageId) { newId in
            if let newId, newId != message.id, playback.isPlaying {
                playback.pause()
            }
        }
    }

    // MARK: - Bubble layout (WhatsApp-style)

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Forwarded indicator inside the bubble
            forwardedIndicator(for: message, forwardedLabel: chatVM.translationService?.resolve(key: ChatTranslationKeys.FORWARDED, module: ChatTranslationKeys.MODULE).value ?? "Forwarded")

            // Centred on the waveform line, not on the column with the time below
            // it: the avatar is taller than the waveform, so top alignment left it
            // lower than the play button.
            HStack(alignment: .voiceWaveformCenter, spacing: 6) {
                if isOutgoing {
                    leadingAvatarOrSpeedSlot
                    playbackControl
                    waveformColumn
                } else {
                    playbackControl
                    waveformColumn
                    trailingAvatarOrSpeedSlot
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, message.forwarded == true ? 4 : 15)
            .padding(.bottom, 15)
        }
        .background(message.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .applyStrokeOnBubbleView()
        .applyTailView(message.direction)
        .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
        .overlay(alignment: .bottomTrailing) {
            bubbleMetaFooter
        }
    }

    @ViewBuilder
    private var leadingAvatarOrSpeedSlot: some View {
        if showSpeedInsteadOfAvatar {
            speedPillButton
        } else {
            voiceAvatar
        }
    }

    @ViewBuilder
    private var trailingAvatarOrSpeedSlot: some View {
        if showSpeedInsteadOfAvatar {
            speedPillButton
        } else {
            voiceAvatar
        }
    }

    private var voiceAvatar: some View {
        VoiceBubbleAvatarView(
            imageUrl: avatarImageUrl,
            fallbackName: message.senderName,
            isOutgoing: isOutgoing
        )
    }

    private var speedPillButton: some View {
        Button {
            playback.cyclePlaybackSpeed()
        } label: {
            Text(speedLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSelectionMode)
        .accessibilityLabel(a11yName(ChatTranslationKeys.CHAT_A11Y_PLAYBACK_SPEED, fallback: "Playback speed"))
        .accessibilityValue(speedLabel)
    }

    private var speedLabel: String {
        let speed = playback.playbackSpeed
        if speed == 1.0 { return "1x" }
        if speed == floor(speed) { return "\(Int(speed))x" }
        return String(format: "%.1fx", speed)
    }

    @ViewBuilder
    private var playbackControl: some View {
        InlineMediaTransferControl(
            uploadVM: uploadVM,
            config: transferConfig,
            isSelectionMode: isSelectionMode,
            controlSize: controlSlotSize,
            progressControlSize: controlSlotSize,
            translator: chatVM.translationService,
            readyContent: {
                Button(action: togglePlayback) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ChatBubbleStyle.secondaryForeground(for: colorScheme))
                        .frame(width: controlSlotSize, height: controlSlotSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isSelectionMode)
                .accessibilityLabel(a11yName(
                    playback.isPlaying ? ChatTranslationKeys.CHAT_A11Y_PAUSE_VOICE : ChatTranslationKeys.CHAT_A11Y_PLAY_VOICE,
                    fallback: playback.isPlaying ? "Pause voice message" : "Play voice message"
                ))
            }
        )
        .frame(width: controlSlotSize, height: controlSlotSize)
    }

    private func a11yName(_ key: String, fallback: String) -> String {
        chatVM.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE)
            .value ?? fallback
    }

    private var waveformColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            wavesSliderView()
                .alignmentGuide(.voiceWaveformCenter) { $0[VerticalAlignment.center] }
            HStack(spacing: 4) {
                Text(timeString(from: waveformDisplayTime))
                    .font(.caption)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(ChatBubbleStyle.secondaryForeground(for: colorScheme))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
            }
            .padding(.trailing, 72)
        }
        .frame(minWidth: waveformMinWidth)
    }

    private var bubbleMetaFooter: some View {
        BubbleMetaOverlay(message: message, style: .bubble(colorScheme: colorScheme), translationService: chatVM.translationService)
            .padding(.trailing, 4)
            .padding(.bottom, 2)
    }

    private var waveformDisplayTime: Double {
        if playback.isPlaying || playback.isDragging || playback.progress > 0 {
            return currentTime
        }
        return playback.audioDuration
    }

    private var showsScrubber: Bool {
        playback.audioDuration > 0 || playback.progress > 0 || playback.isPlaying || playback.isDragging
    }

    // MARK: - Waveform

    private func wavesSliderView() -> some View {
        GeometryReader { geo in
            let spacing = max(0, (geo.size.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1))
            let totalWaveformWidth = geo.size.width
            let midY = geo.size.height / 2
            let playedColor = ChatBubbleStyle.foreground(for: colorScheme).opacity(colorScheme == .dark ? 0.9 : 0.6)
            let unplayedColor = ChatBubbleStyle.secondaryForeground(for: colorScheme).opacity(colorScheme == .dark ? 0.45 : 0.35)
            let scrubberColor = AppColors.primary

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for (i, amp) in displayAmplitudes.enumerated() {
                        let x = CGFloat(i) * (barWidth + spacing)
                        let barHeight = amp * size.height * 0.6
                        let y = midY - barHeight / 2
                        let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                        let progressIndex = Int(playback.progress * CGFloat(displayAmplitudes.count))
                        let color = (progressIndex >= 0 && i <= progressIndex) ? playedColor : unplayedColor
                        context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                    }
                }
                .frame(width: totalWaveformWidth, height: waveformHeight)

                if showsScrubber {
                    Circle()
                        .fill(scrubberColor)
                        .frame(width: 16, height: 16)
                        .offset(
                            x: max(0, min(playback.progress * totalWaveformWidth, totalWaveformWidth - 16)),
                            y: 8
                        )
                        .shadow(radius: 2)
                }
            }
            .frame(height: waveformHeight)
            .contentShape(Rectangle())
            .gesture(waveformSeekGesture(width: totalWaveformWidth))
        }
        .frame(height: waveformHeight)
    }

    private func waveformSeekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canSeekWaveform else { return }
                let fraction = fractionAt(x: value.location.x, width: width)
                handleWaveformSeekChanged(fraction: fraction)
            }
            .onEnded { value in
                guard canSeekWaveform else { return }
                let fraction = fractionAt(x: value.location.x, width: width)
                Task { await handleWaveformSeekEnded(fraction: fraction) }
            }
    }

    private func fractionAt(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return max(0, min(1, x / width))
    }

    private func handleWaveformSeekChanged(fraction: CGFloat) {
        let isActiveMessage = globalAudioManager.currentlyPlayingAudio?.messageId == message.id

        if isActiveMessage, playback.isPlaying, !playback.isDragging {
            playback.setDragging(true)
        } else if !playback.isDragging {
            playback.isDragging = true
        }

        playback.seekTo(fraction)

        if isActiveMessage {
            globalAudioManager.updateProgress(fraction)
        } else if globalAudioManager.currentlyPlayingAudio != nil {
            globalAudioManager.pause()
        }
    }

    private func handleWaveformSeekEnded(fraction: CGFloat) async {
        let savedFraction = fraction
        await ensureAudioDecoded()

        playback.seekTo(savedFraction)
        playback.setDragging(false)

        if globalAudioManager.currentlyPlayingAudio?.messageId == message.id {
            globalAudioManager.seek(to: savedFraction)
        }
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        let isCurrentlyPlaying = globalAudioManager.currentlyPlayingAudio?.messageId == message.id

        if playback.player == nil {
            if let url = audioURL {
                playback.loadAudio(
                    from: url,
                    cacheKey: message.codeMessage,
                    precomputedWaveform: message.message.waveform,
                    audioID: message.id
                )
                if let audioDuration = message.message.audioDuration, audioDuration > 0 {
                    playback.audioDuration = audioDuration
                } else if playback.audioDuration == 0,
                          url.pathExtension.lowercased() == "opus",
                          let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                    playback.audioDuration = Double(fileSize) / 3000.0
                }
            } else if let waveform = message.message.waveform, !waveform.isEmpty {
                playback.amplitudes = waveform.map { CGFloat($0) }
                if let audioDuration = message.message.audioDuration, audioDuration > 0 {
                    playback.audioDuration = audioDuration
                }
            }
            }

        if isCurrentlyPlaying, globalAudioManager.currentlyPlayingAudio != nil {
            _ = globalAudioManager.currentlyPlayingAudio
        }

        playback.globalManager = globalAudioManager
        playback.messageId = message.id

        autoPlayObserver = NotificationCenter.default.addObserver(
            forName: .autoPlayNextAudio,
            object: nil,
            queue: .main
        ) { notification in
            if let messageId = notification.userInfo?["messageId"] as? String,
               messageId == message.id {
                Task { @MainActor in
                    await handleAutoPlay()
                }
            }
        }

        if message.direction == .sent {
            InlineMediaTransferExecutor.triggerAutoUploadIfNeeded(
                config: transferConfig,
                uploadVM: uploadVM
            )
        }
    }

    private func handleDisappear() {
        if globalAudioManager.currentlyPlayingAudio?.messageId != message.id {
            playback.stop()
        }
        if let observer = autoPlayObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        guard !isSelectionMode else { return }

        if playback.isPlaying {
            globalAudioManager.pause()
        } else {
            Task { @MainActor in
                await playVoiceMessage()
            }
        }
    }

    @MainActor
    private func playVoiceMessage() async {
        if playback.progress >= 1.0 { playback.progress = 0 }
        playback.isDragging = false

        guard await prepareForPlayback() else { return }
        startPlayback()
    }

    @MainActor
    private func handleAutoPlay() async {
        if playback.progress >= 1.0 { playback.progress = 0 }
        playback.isDragging = false

        guard await prepareForPlayback() else { return }
        startPlayback()
    }

    @MainActor
    private func prepareForPlayback() async -> Bool {
        guard let url = audioURL else { return false }

        if url.pathExtension.lowercased() == "opus" {
            if playback.hasPlayablePlayer { return true }

            while isDecodingOpus {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            isDecodingOpus = true
            defer { isDecodingOpus = false }

            do {
                let wavURL = try await opusPlaybackService.decodeForPlayback(opusURL: url)
                loadDecodedAudio(from: wavURL)
                return playback.hasPlayablePlayer
            } catch {
                debugLog("Failed to decode Opus: \(error.localizedDescription)")
                return false
            }
        }

        if playback.player == nil {
            playback.loadAudio(
                from: url,
                cacheKey: message.codeMessage,
                precomputedWaveform: message.message.waveform,
                audioID: message.id
            )
        }

        return playback.hasPlayablePlayer || playback.audioDuration > 0
    }

    private func startPlayback() {
        guard let url = audioURL else { return }

        let audioInfo = PlayingAudioInfo(
            messageId: message.id,
            audioURL: url,
            duration: playback.audioDuration,
            waveform: message.message.waveform,
            senderName: message.senderName,
            chatName: "Chat",
            chatRoomId: chatRoomId,
            isPlaying: true,
            progress: playback.progress,
            playbackSpeed: playback.playbackSpeed
        )

        globalAudioManager.play(audioInfo: audioInfo, coordinator: playback, buildQueue: true)
    }

    @MainActor
    private func ensureAudioDecoded() async {
        _ = await prepareForPlayback()
    }

    private func loadDecodedAudio(from wavURL: URL) {
        let savedProgress = playback.progress

        playback.installDecodedPlayer(
            from: wavURL,
            cacheKey: message.codeMessage + "_decoded",
            precomputedWaveform: message.message.waveform
        )

        if let audioDuration = message.message.audioDuration, audioDuration > 0 {
            playback.audioDuration = audioDuration
        }

        if savedProgress > 0 {
            playback.seekTo(savedProgress)
        }
    }

    private func timeString(from seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

private extension VerticalAlignment {
    /// The centre line of a voice bubble's waveform, which the avatar and the
    /// play control sit on.
    enum VoiceWaveformCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            d[VerticalAlignment.center]
        }
    }

    static let voiceWaveformCenter = VerticalAlignment(VoiceWaveformCenter.self)
}
