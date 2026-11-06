import SwiftUI
import SDWebImageSwiftUI
import Combine
import AVFoundation


struct BubbleImageView: View {
    let message: MessageDataItem
    @ObservedObject var uploadVM: FileUploadViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var uploadState: UploadState?
    @State private var downloadState: DownloadState?
    @State private var observationToken: AnyCancellable?
    @State private var isDownloaded = false
    @State private var resolvedImage: UIImage?
    /// The tiny inline preview that ships with the message, decoded up front.
    ///
    /// Seeded in `init` rather than resolved in `onAppear` so the bubble has real
    /// content on the frame it first appears. Previously the inline preview was the
    /// *last* fallback inside a detached task, behind two disk probes, so every
    /// image began life as a stretched SF Symbol and the picture arrived one or
    /// more async hops later — the "popping out of nowhere".
    @State private var previewImage: UIImage?
    @State private var bubbleWidth: CGFloat
    private var safeBubbleWidth: CGFloat? {
        guard bubbleWidth.isFinite, bubbleWidth > 0 else { return nil }
        return bubbleWidth - 8
    }
    
    // Add flags to prevent repeated setup
    @State private var hasSetup = false
    @State private var hasCheckedCache = false
    
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    let isSelectionMode: Bool

    /// Persists bubble widths across LazyVStack cell recycling to prevent layout shifts.
    /// NSCache auto-evicts under memory pressure, unlike a plain Dictionary.
    private static let widthCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 500
        return cache
    }()

    /// Aspect ratios of images we have already decoded, for messages that arrived
    /// without dimensions on them.
    private static let aspectRatioCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 500
        return cache
    }()

    static func cacheAspectRatio(_ image: UIImage, for codeMessage: String) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        aspectRatioCache.setObject(
            NSNumber(value: Double(size.width / size.height)),
            forKey: codeMessage as NSString
        )
    }

    /// Shape to use when a message tells us nothing about its media and carries no
    /// preview either — rare, but the placeholder is a plain fill with no size of
    /// its own, so something has to give it one.
    private static let fallbackAspectRatio: CGFloat = 4.0 / 3.0

    /// The ratio actually handed to the layout.
    ///
    /// Nil is deliberate when a real image is present and its proportions are
    /// unknown: that reproduces the original `scaledToFit` behaviour rather than
    /// forcing a guessed shape onto a picture we can already measure.
    private var effectiveAspectRatio: CGFloat? {
        if let reserved = reservedAspectRatio { return reserved }
        return displayedImage == nil ? Self.fallbackAspectRatio : nil
    }

    /// What to draw right now: the sharpest thing we have.
    ///
    /// The preview stands in until the full image lands and is never allowed to
    /// replace it afterwards, so the picture only ever gets better.
    private var displayedImage: UIImage? {
        resolvedImage ?? previewImage
    }

    /// The width/height the bubble should hold before the image is available.
    ///
    /// Without this the bubble was sized by whatever was on screen at the time: an
    /// SF Symbol placeholder while loading, then the real photo. The two have
    /// nothing to do with each other, so every image that resolved changed its
    /// row's height — and in a `LazyVStack` a row changing height after layout
    /// shifts everything below it, which is what made scrolling back up jump.
    ///
    /// Prefers the dimensions the message was sent with; falls back to the ratio
    /// of an image we have decoded before, so a row keeps its height across cell
    /// recycling. Nil means we genuinely cannot know yet, and the view sizes
    /// itself from its content exactly as it used to.
    private var reservedAspectRatio: CGFloat? {
        if let width = message.message.width,
           let height = message.message.height,
           width > 0, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }

        // The inline preview is a scaled copy of the original, so its ratio is the
        // original's. This covers every message stored before dimensions were
        // carried through the mappers — which is all of them already on disk.
        if let preview = previewImage, preview.size.height > 0 {
            return preview.size.width / preview.size.height
        }

        return Self.aspectRatioCache
            .object(forKey: message.codeMessage as NSString)
            .map { CGFloat(truncating: $0) }
    }

    init(message: MessageDataItem, uploadVM: FileUploadViewModel, chatVM: ChatRoomViewModel, isSelectionMode: Bool = false) {
        self.message = message
        self.uploadVM = uploadVM
        self.chatVM = chatVM
        self.isSelectionMode = isSelectionMode
        _bubbleWidth = State(initialValue: Self.widthCache.object(forKey: message.id as NSString).map { CGFloat(truncating: $0) } ?? 0)

        // Full-resolution image first when we already hold it, so a bubble that has
        // been on screen before never steps back down to its preview.
        let full = message.message.UIimage
            ?? ChatImageMemoryCache.shared.image(forKey: message.codeMessage)
        _resolvedImage = State(initialValue: full)
        _previewImage = State(
            initialValue: full ?? ChatMediaPreviewCache.shared.preview(
                forKey: message.codeMessage,
                encoded: message.message.thumbnail
            )
        )
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if message.direction == .sent {
                    // `shouldRetry` alone: a failed upload is still pending too, so
                    // requiring `shouldUploadDownload == false` here meant the error
                    // marker never appeared for the case it exists for.
                    if message.message.shouldRetry {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.red)
                            .font(.headline)
                    } else {
                        VStack(spacing: 8) {
                            bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
                            shareButton()
                        }
                    }
                }
                if message.direction == .sent {
                    Spacer()
                }
                VStack(spacing: 0) {
                    // Forwarded indicator inside the clipped bubble
                    forwardedIndicator(for: message, forwardedLabel: chatVM.translationService?.resolve(key: ChatTranslationKeys.FORWARDED, module: ChatTranslationKeys.MODULE).value ?? "Forwarded")

                    // Reply preview (optional)
                    if let reply = message.reply {
                        switch reply {
                        case .message(let repliedMessage?):
                            ReplyPreviewView(repliedMessage: repliedMessage, chatVM: chatVM,parentWidth: $bubbleWidth,isMediaParent: true)
                                .fixedSize(horizontal: false, vertical: true)
    //                            .frame(width: safeBubbleWidth)
    //                            .padding(.horizontal,8)
    //                            .background(.red.opacity(0.6))
                                .onTapGesture {
                                    guard !isSelectionMode else { return }
                                    chatVM.handleReplyPreviewTap(repliedMessage)
                            }
                            .allowsHitTesting(!isSelectionMode)
        //                        .frame(maxWidth: bubbleWidth)
        //                        .applyCommonModifiers(message: message)
                        case .message(.none):
                            EmptyView()
        //
                        }
                    }
                    
                    messageView()
                              .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(key: BubbleWidthKey.self, value: geo.size.width.isFinite && geo.size.width > 0 ? geo.size.width : 0)
                                }
                            )
                }.padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(message.backgroundColor)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .applyStrokeOnBubbleView()
                    .applyTailView(message.direction)
                    .shadow(
                        color: Color(.systemGray3).opacity(0.1),
                        radius: 5,
                        x: 0,
                        y: 20
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        ZStack {
                            // Asked of the file rather than the sender: media
                            // this account sent from another device arrives as
                            // ours, and used to show no control at all.
                            if message.mediaNeedsTransfer {
                                MediaTransferButton(
                                    uploadVM: uploadVM,
                                    messages: [message],
                                    isDownload: message.mediaTransferIsDownload,
                                    translationService: chatVM.translationService,
                                    onRetryRequested: { code in
                                        chatVM.clearAutoTransferAttempts(codeMessage: code)
                                    },
                                    onUploadSuccess: { code, remoteUrl in
                                        chatVM.clearPendingUpload(codeMessage: code, remoteUrl: remoteUrl)
                                    },
                                    onAutoTransferAttempt: { code, attempts in
                                        chatVM.persistAutoTransferAttempts(codeMessage: code, attempts: attempts)
                                    }
                                )
                                .allowsHitTesting(!isSelectionMode)
                            }
                        }
                    }
                    .onPreferenceChange(BubbleWidthKey.self) {
                           let w = $0.isFinite && $0 > 0 ? $0 : 0
                           bubbleWidth = w
                           if w > 0 { Self.widthCache.setObject(NSNumber(value: Double(w)), forKey: message.id as NSString) }
                       }
                
              
                
                if message.direction == .received {
                    // `shouldRetry` alone: a failed upload is still pending too, so
                    // requiring `shouldUploadDownload == false` here meant the error
                    // marker never appeared for the case it exists for.
                    if message.message.shouldRetry {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.red)
                            .font(.headline)
                    } else {
                        VStack(spacing: 8) {
                            bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
                            shareButton()
                        }
                    }
                }
            }
        }

        .frame(maxWidth: .infinity, alignment: message.alignment)
        .id(message.id)
        .padding(.leading, message.direction == .received ? 10 : 60)
        .padding(.trailing, message.direction == .received ? 60 : 10)
        .onAppear {
            // Always resolve image on appear (re-resolve after scroll back)
            self.resolveImageIfNeeded()

            // The same shared entry point the grid and the retry button use.
            // This was a third copy of the allowance/in-flight/disk-lookup logic,
            // and the three had already drifted apart from one another.
            InlineMediaTransferExecutor.triggerAutoUploadIfNeeded(
                config: .forMessage(
                    message,
                    onUploadSuccess: { remoteUrl in
                        chatVM.clearPendingUpload(codeMessage: message.codeMessage, remoteUrl: remoteUrl)
                    },
                    onAutoTransferAttempt: { attempts in
                        chatVM.persistAutoTransferAttempts(
                            codeMessage: message.codeMessage,
                            attempts: attempts
                        )
                    }
                ),
                uploadVM: uploadVM
            )

            if message.direction != .sent {
                if !hasCheckedCache {
                    hasCheckedCache = true
                    let cachedkey = message.codeMessage
                    let cacheType: MediaType = message.typeMessage.isVideo ? .video : .image
                    uploadVM.checkIfCached(cachedkey: cachedkey, type: cacheType) { isCached in
                        if isCached == true {
                            downloadState = .success
                        } else {
                            downloadState = .idle
                        }
                    }
                }
            }
        }
        .onReceive(uploadVM.downloadPublisher(for: message.codeMessage)) { state in
            if downloadState != state {
                downloadState = state
            }
        }
        .onReceive(uploadVM.uploadPublisher(for: message.codeMessage)) { newState in
            // Only update if state actually changed
            if uploadState != newState {
                uploadState = newState
            }
        }
        .onChange(of: downloadState) { newState in
            guard newState == .success else { return }
            let codeMessage = message.codeMessage
            let targetWidth = Self.maxBubblePixelWidth
            Task.detached(priority: .userInitiated) {
                guard let diskImage = DiskMediaManager.shared.loadImageFromDisk(fileName: codeMessage, pathName: .CHAT) else { return }
                let prepared = Self.downsample(diskImage, toWidth: targetWidth)
                ChatImageMemoryCache.shared.store(prepared, forKey: codeMessage)
                Self.cacheAspectRatio(prepared, for: codeMessage)
                await MainActor.run { resolvedImage = prepared }
            }
        }
    }
    
    
    private func messageView() -> some View {
        VStack {
//            if let reply = message.reply {
//                switch reply {
//                case .message(let msg):
//                    if let message = msg {
//                        ReplyPreviewView(repliedMessage: message,parentWidth: 0)
//                    } else {
//                        EmptyView()
//                    }
//                }
//            }

           
            Group {
                // One image view, whose contents sharpen from preview to full
                // resolution. Keeping it a single view — rather than swapping
                // between a placeholder view and an image view — is what makes the
                // upgrade invisible: no identity change, so nothing re-lays out.
                if let image = displayedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .id(message.codeMessage + "_image")
                        .heroAnchor(id: message.codeMessage, image: image)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isSelectionMode else { return }
                            chatVM.onTapMedia(message)
                        }
                        .allowsHitTesting(!isSelectionMode)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                } else {
                    // Only reached when the message carries no usable preview at
                    // all. A neutral fill, not a stretched symbol: it occupies the
                    // reserved box exactly, so the real photo replaces it without
                    // changing the row's height.
                    MediaPlaceholderFill(isVideo: message.typeMessage.isVideo)
                        .id(message.codeMessage + "_placeholder")
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                }
            }
            .onChange(of: message.codeMessage) { _ in
                resolvedImage = nil
                previewImage = ChatMediaPreviewCache.shared.preview(
                    forKey: message.codeMessage,
                    encoded: message.message.thumbnail
                )
                hasSetup = false
                hasCheckedCache = false
            }
            // Nil ratio behaves exactly like `.scaledToFit()` — the view sizes from
            // its own content. A known ratio holds the row's height steady from the
            // first frame, so the photo landing does not move anything.
            .aspectRatio(effectiveAspectRatio, contentMode: .fit)
            .clipShape(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .frame(maxHeight: UIScreen.main.bounds.height * 0.35)
            .overlay {
                overlayInfoView()
            }
            
            // MARK: Message caption
            if !message.message.text.isEmpty {
                BubbleCaptionWithMeta(
                    text: message.message.text,
                    message: message,
                    colorScheme: colorScheme
                )
            }
        }
//        .padding(.horizontal, 5)
//        .padding(.vertical, 2)
//        .background(message.backgroundColor)
//        .clipShape(
//            RoundedRectangle(cornerRadius: 15, style: .continuous)
//        )
//        .applyStrokeOnBubbleView()
//        .applyTailView(message.direction)
//        .shadow(
//            color: Color(.systemGray3).opacity(0.1),
//            radius: 5,
//            x: 0,
//            y: 20
//        )
    }
    
    private func overlayInfoView() -> some View {
        ZStack {
            if message.typeMessage.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(radius: 4)
            }

            VStack {
                if message.typeMessage.isVideo {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                            if let duration = message.message.videoDuration, duration > 0 {
                                Text(formatDuration(duration))
                            }
                        }
                        .padding(5)
                        .modifier(ConditionalFontModifier())
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 4)
                        .background(Color.black.opacity(0.2)).clipShape(Capsule())
                        .padding(2)

                        Spacer()
                    }
                }
                Spacer()
                if message.message.text.isEmpty {
                    HStack {
                        Spacer()
                        BubbleMetaOverlay(message: message, style: .media, translationService: chatVM.translationService)
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static let maxBubblePixelWidth: CGFloat = UIScreen.main.bounds.width * UIScreen.main.scale

    private func resolveImageIfNeeded() {
        // If the message already has a full UIImage, use it directly
        if let uiImage = message.message.UIimage {
            if resolvedImage !== uiImage { resolvedImage = uiImage }
            Self.cacheAspectRatio(uiImage, for: message.codeMessage)
            return
        }

        // Already resolved — don't re-decode
        if resolvedImage != nil { return }

        // Check memory cache first (fast path — avoids any I/O or decode)
        if let cached = ChatImageMemoryCache.shared.image(forKey: message.codeMessage) {
            resolvedImage = cached
            Self.cacheAspectRatio(cached, for: message.codeMessage)
            return
        }

        // Everything below is expensive — move to background
        let codeMessage = message.codeMessage
        let targetWidth = Self.maxBubblePixelWidth

        let isVideo = message.typeMessage.isVideo

        Task.detached(priority: .userInitiated) {
            guard let prepared = Self.loadLocalThumbnail(
                codeMessage: codeMessage,
                isVideo: isVideo,
                targetWidth: targetWidth
            ) else { return }
            await MainActor.run { resolvedImage = prepared }

            // The inline base64 preview used to be decoded here, as the last resort
            // after both disk probes. It is now decoded synchronously in `init` via
            // `ChatMediaPreviewCache` and is already on screen by the time this task
            // runs, so decoding it again would only cost work and replace the
            // picture with a blurrier copy of itself.
        }
    }

    /// The sharpest picture held on disk for a media message: the image itself,
    /// else a frame of the video, which is then saved as the image for next time.
    ///
    /// Expensive — call it off the main thread. Shared with `BubbleVideoNoteView`,
    /// whose thumbnail comes from exactly the same place.
    static func loadLocalThumbnail(codeMessage: String, isVideo: Bool, targetWidth: CGFloat) -> UIImage? {
        if let diskImage = DiskMediaManager.shared.loadImageFromDisk(fileName: codeMessage, pathName: .CHAT) {
            let prepared = Self.downsample(diskImage, toWidth: targetWidth)
            ChatImageMemoryCache.shared.store(prepared, forKey: codeMessage)
            Self.cacheAspectRatio(prepared, for: codeMessage)
            return prepared
        }

        if isVideo,
           let videoURL = DiskMediaManager.shared.loadVideoFromDisk(fileName: codeMessage, pathName: .CHAT),
           FileManager.default.fileExists(atPath: videoURL.path) {
            let asset = AVAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: targetWidth, height: targetWidth)
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let videoThumb = UIImage(cgImage: cgImage)
                DiskMediaManager.shared.saveImageToDisk(videoThumb, fileName: codeMessage, pathName: .CHAT)
                let prepared = Self.downsample(videoThumb, toWidth: targetWidth)
                ChatImageMemoryCache.shared.store(prepared, forKey: codeMessage)
                Self.cacheAspectRatio(prepared, for: codeMessage)
                return prepared
            }
        }

        return nil
    }

    /// Downsamples a UIImage to the target pixel width, keeping aspect ratio.
    /// Uses iOS 15+ prepareThumbnail for hardware-accelerated decode when available.
    static func downsample(_ image: UIImage, toWidth targetWidth: CGFloat) -> UIImage {
        // If already smaller than target, return as-is
        let scale = UIScreen.main.scale
        let targetPixelWidth = targetWidth
        guard image.size.width > targetPixelWidth / scale else { return image }

        let targetSize = CGSize(
            width: targetPixelWidth / scale,
            height: image.size.height * (targetPixelWidth / scale) / image.size.width
        )

        // Prefer prepareThumbnail when available. Newer SDKs require a completionHandler.
        if #available(iOS 15.0, *) {
            // Use a semaphore to synchronously wait for the thumbnail generation
            let semaphore = DispatchSemaphore(value: 0)
            var result: UIImage?
            image.prepareThumbnail(of: targetSize) { thumbnail in
                result = thumbnail
                semaphore.signal()
            }
            // Wait for the completion (this runs on a background Task.detached caller in our usage)
            semaphore.wait()
            if let result { return result }
        }

        // Fallback: draw into a renderer
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized
    }
    
    private func shareButton() -> some View {
        Button {
            // Share action
        } label: {
            Image(systemName: "square.and.arrow.up.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(10)
                .foregroundColor(.white)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        // Its action is empty: VoiceOver should not announce a control that does nothing.
        .accessibilityHidden(true)
    }
}

struct ConditionalFontModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.font(.system(.caption, weight: .bold))
        } else {
            content.font(.system(size: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .bold))
        }
    }
}


