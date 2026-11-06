//
//  MediaGroupBubbleView.swift
//  Pods
//
//  Created by Don divin on 2/11/26.
//


import SwiftUI
import AVFoundation


// MARK: - Media Grid View (WhatsApp Style)
struct MediaGridBubbleView: View {
    let messages: [MessageDataItem]
    let isFromCurrentUser: Bool
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
//    @ObservedObject var uploadVM: UploadViewModel
    @ObservedObject var uploadVM: FileUploadViewModel
    let isSelectionMode: Bool

    let maxWidth: CGFloat = 300
    @State private var bubbleWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    /// NSCache auto-evicts under memory pressure, unlike a plain Dictionary
    private static let widthCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 500
        return cache
    }()

    init(messages: [MessageDataItem], isFromCurrentUser: Bool, chatVM: ChatRoomViewModel, uploadVM: FileUploadViewModel, isSelectionMode: Bool = false) {
        self.messages = messages
        self.isFromCurrentUser = isFromCurrentUser
        self.chatVM = chatVM
        self.uploadVM = uploadVM
        self.isSelectionMode = isSelectionMode
        let key = messages.first?.id ?? ""
        _bubbleWidth = State(initialValue: Self.widthCache.object(forKey: key as NSString).map { CGFloat(truncating: $0) } ?? 0)
    }

    private let spacing: CGFloat = 2

    private var direction: MessageDirection {
        isFromCurrentUser ? .sent : .received
    }

    private var firstMessage: MessageDataItem? {
        messages.first
    }

    /// Items still to be moved, split by which way they are moving.
    ///
    /// A batch is rarely uniform once anything has happened to it: one photo can be
    /// uploaded and its local copy gone — so it wants downloading — while the rest
    /// are still queued to upload. A single control cannot honestly drive both.
    private var messagesNeedingUpload: [MessageDataItem] {
        messages.filter { $0.mediaNeedsTransfer && !$0.mediaTransferIsDownload }
    }

    private var messagesNeedingDownload: [MessageDataItem] {
        messages.filter { $0.mediaNeedsTransfer && $0.mediaTransferIsDownload }
    }

    /// What the batch control acts on, and which way.
    ///
    /// Uploads win when both are present: media this device still owes the server
    /// is what the user just started, and finishing it is what unblocks the rest of
    /// the send. Taking the operation from whichever item happened to come first
    /// meant one already-uploaded photo relabelled the control as "download" and
    /// then ran a download against every message still waiting to be uploaded.
    private var batchTransfer: (messages: [MessageDataItem], isDownload: Bool)? {
        if !messagesNeedingUpload.isEmpty { return (messagesNeedingUpload, false) }
        if !messagesNeedingDownload.isEmpty { return (messagesNeedingDownload, true) }
        return nil
    }

    private var lastMessage: MessageDataItem? {
        messages.last
    }

    /// The item the batch's meta line speaks for.
    ///
    /// It was `messages.last`, chosen arbitrarily: a batch whose third photo had
    /// failed still showed the last one's ticks and read as fully sent. The least
    /// advanced item is the only one that cannot overstate the batch.
    private var metaMessage: MessageDataItem? {
        messages.min { statusRank(of: $0) < statusRank(of: $1) } ?? lastMessage
    }

    /// Lowest first. Failure sits below everything: it is the one outcome that must
    /// never be hidden behind a sibling that went through.
    private func statusRank(of message: MessageDataItem) -> Int {
        switch message.status {
        case .FAILED:                      return 0
        case .PENDING:                     return 1
        case .SENT:                        return 2
        case .DELIVERED, .UNSEEN, .MODIFY: return 3
        case .SEEN:                        return 4
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Reply preview (from first message)
            if let reply = firstMessage?.reply {
                switch reply {
                case .message(let repliedMessage?):
                    ReplyPreviewView(
                        repliedMessage: repliedMessage,
                        chatVM: chatVM,
                        parentWidth: $bubbleWidth,
                        isMediaParent: true
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture {
                        chatVM.handleReplyPreviewTap(repliedMessage)
                    }
                    .allowsHitTesting(!isSelectionMode)
                case .message(.none):
                    EmptyView()
                }
            }

            // Grid layout -- images clipped with their own rounded corners
            // so the bubble background is visible around them (tail sits on background)
            gridLayout
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if firstMessage?.message.text.isEmpty ?? true, let metaMessage {
                        BubbleMetaOverlay(message: metaMessage, style: .media, translationService: chatVM.translationService)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: BubbleWidthKey.self, value: geo.size.width)
                    }
                )
                .onAppear {
                    // Every item, through the one shared entry point. The allowance,
                    // the in-flight check, the disk lookup and the failure reporting
                    // all live in the executor now — this used to be a bespoke copy
                    // of that logic which had drifted from the retry button's copy.
                    for message in messages {
                        InlineMediaTransferExecutor.triggerAutoUploadIfNeeded(
                            config: .forMessage(
                                message,
                                onUploadSuccess: { remoteUrl in
                                    chatVM.clearPendingUpload(
                                        codeMessage: message.codeMessage,
                                        remoteUrl: remoteUrl
                                    )
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
                    }
                }

            // Bottom row: caption only (meta overlaid on caption or grid)
            bottomRow
        }
        .frame(maxWidth: maxWidth)
        .background(firstMessage?.backgroundColor ?? ChatBubbleStyle.background(for: direction))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .applyStrokeOnBubbleView()
        .applyTailView(direction)
        .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            ZStack {
                // One control for the whole batch — never one per tile. It used to
                // read `messages[0]` alone, so a batch whose first photo had gone
                // and whose third had failed offered no way to retry anything;
                // asking the whole batch fixes that without splitting the control.
                if let batchTransfer {
                    MediaTransferButton(
                        uploadVM: uploadVM,
                        // Only the items this control can actually act on, so its
                        // progress, its size label and its retry all describe the
                        // same operation.
                        messages: batchTransfer.messages,
                        isDownload: batchTransfer.isDownload,
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
        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
        .padding(.leading, isFromCurrentUser ? 60 : 10)
        .padding(.trailing, isFromCurrentUser ? 10 : 60)
        .onPreferenceChange(BubbleWidthKey.self) {
            let w = $0.isFinite && $0 > 0 ? $0 : 0
            if bubbleWidth == 0 {
                bubbleWidth = w
            }
            if w > 0 { Self.widthCache.setObject(NSNumber(value: Double(w)), forKey: (messages.first?.id ?? "") as NSString) }
        }
    }

    @ViewBuilder
    private var bottomRow: some View {
        if let caption = firstMessage?.message.text, !caption.isEmpty, let metaMessage {
            BubbleCaptionWithMeta(
                text: caption,
                message: metaMessage,
                colorScheme: colorScheme,
                horizontalPadding: 8,
                verticalPadding: 6
            )
        }
    }

    // MARK: - Grid Layout
    @ViewBuilder
    private var gridLayout: some View {
        let count = messages.count
        switch count {
        case 0:
            EmptyView()
        case 1:
            singleImage(at: 0)
        case 2:
            twoImagesLayout
        case 3:
            threeImagesLayout
        case 4:
            fourImagesLayout
        default:
            manyImagesLayout
        }
    }

    // MARK: - Single Image
    private func singleImage(at index: Int) -> some View {
        Group {
            if index < messages.count {
                let message = messages[index]
                let size = calculateImageSize(message.message.UIimage, maxWidth: maxWidth - 8)

                ResolvableMediaImage(message: message, contentMode: .fill, uploadVM: uploadVM)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay { videoOverlay(for: message) }
                    .heroAnchor(id: message.codeMessage, image: nil)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isSelectionMode else { return }
                        chatVM.onTapMedia(message)
                    }
                    .allowsHitTesting(!isSelectionMode)
                    .id(message.id)
            }
        }
    }

    // MARK: - Two Images (Side by Side)
    private var twoImagesLayout: some View {
        let cellWidth = (maxWidth - 8 - spacing) / 2
        return HStack(spacing: spacing) {
            ForEach(0..<min(2, messages.count), id: \.self) { index in
                imageCell(at: index, width: cellWidth, height: 150)
            }
        }
    }

    // MARK: - Three Images (1 top, 2 bottom)
    private var threeImagesLayout: some View {
        let cellWidth = (maxWidth - 8 - spacing) / 2
        return VStack(spacing: spacing) {
            if messages.count > 0 {
                imageCell(at: 0, width: maxWidth - 8, height: 150)
            }
            HStack(spacing: spacing) {
                ForEach(1..<min(3, messages.count), id: \.self) { index in
                    imageCell(at: index, width: cellWidth, height: 100)
                }
            }
        }
    }

    // MARK: - Four Images (2x2 Grid)
    private var fourImagesLayout: some View {
        let cellWidth = (maxWidth - 8 - spacing) / 2
        return VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(0..<min(2, messages.count), id: \.self) { index in
                    imageCell(at: index, width: cellWidth, height: 120)
                }
            }
            HStack(spacing: spacing) {
                ForEach(2..<min(4, messages.count), id: \.self) { index in
                    imageCell(at: index, width: cellWidth, height: 120)
                }
            }
        }
    }

    // MARK: - 5+ Images (Show 4 with "+N" overlay on last)
    private var manyImagesLayout: some View {
        let cellWidth = (maxWidth - 8 - spacing) / 2
        return VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(0..<min(2, messages.count), id: \.self) { index in
                    imageCell(at: index, width: cellWidth, height: 120)
                }
            }
            HStack(spacing: spacing) {
                if messages.count > 2 {
                    imageCell(at: 2, width: cellWidth, height: 120)
                }
                if messages.count > 3 {
                    ZStack {
                        imageCell(at: 3, width: cellWidth, height: 120)

                        if messages.count > 4 {
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: cellWidth, height: 120)
                                .overlay(
                                    Text("+\(messages.count - 4)")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                                // The "+N" tile opens at the first *hidden* item,
                                // not at the tile it is drawn over.
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isSelectionMode else { return }
                                    chatVM.onTapMedia(messages[4])
                                }
                                .allowsHitTesting(!isSelectionMode)
                        }
                    }
                    .frame(width: cellWidth, height: 120)
                    .clipped()
                }
            }
        }
    }

    // MARK: - Reusable Image Cell (bounds-safe)
    @ViewBuilder
    private func imageCell(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < messages.count {
            let message = messages[index]
            ResolvableMediaImage(message: message, contentMode: .fill, uploadVM: uploadVM)
                .frame(width: width, height: height)
                .clipped()
                .overlay { videoOverlay(for: message) }
                // Anchored on the clipped tile, so the hero flies from the tile
                // the user actually touched rather than from the whole bubble.
                .heroAnchor(id: message.codeMessage, image: nil)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isSelectionMode else { return }
                    chatVM.onTapMedia(message)
                }
                .allowsHitTesting(!isSelectionMode)
                .id(message.id)
        }
    }

    @ViewBuilder
    private func videoOverlay(for message: MessageDataItem) -> some View {
        if message.typeMessage.isVideo {
            ZStack {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(radius: 3)

                VStack {
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "video.fill")
                            if let d = message.message.videoDuration, d > 0 {
                                Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60))
                            }
                        }
                        .font(.caption2).bold()
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.black.opacity(0.3)).clipShape(Capsule())
                        .padding(4)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers
    private func placeholderImage(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }

    private func calculateImageSize(_ image: UIImage?, maxWidth: CGFloat) -> CGSize {
        guard let image = image else {
            return CGSize(width: maxWidth, height: 200)
        }

        let imageRatio = image.size.width / image.size.height
        let maxHeight: CGFloat = 350

        if image.size.width > image.size.height {
            let width = min(maxWidth, image.size.width)
            let height = width / imageRatio
            return CGSize(width: width, height: min(height, maxHeight))
        } else {
            let height = min(maxHeight, image.size.height)
            let width = height * imageRatio

            if width > maxWidth {
                return CGSize(width: maxWidth, height: maxWidth / imageRatio)
            } else {
                return CGSize(width: width, height: height)
            }
        }
    }
}

// MARK: - Resolvable Media Image (reuses BubbleImageView's shared NSCache)
/// Lightweight view that resolves an image from memory cache, disk, or base64 thumbnail
/// on a background thread — prevents blocking the main thread in grouped media grids.
private struct ResolvableMediaImage: View {
    let message: MessageDataItem
    let contentMode: ContentMode
    /// Held, not observed: the tile subscribes to one key's publisher below rather
    /// than to the whole view model, which would re-render every tile in the room
    /// on any transfer anywhere.
    let uploadVM: FileUploadViewModel
    @State private var resolved: UIImage?
    @State private var downloadState: DownloadState?

    private static let maxPixelWidth: CGFloat = UIScreen.main.bounds.width * UIScreen.main.scale

    var body: some View {
        Group {
            if let image = resolved {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .onAppear { resolveIfNeeded() }
        // A tile showed the message's inline preview and then never looked again:
        // `resolveIfNeeded` runs on appear and returns early once `resolved` is set,
        // which the preview already did. So a download could finish, the control
        // could disappear, and the tile would still be showing the blurry copy until
        // the row was recycled. The single-image bubble has watched for this all
        // along; the grid never did.
        .onReceive(uploadVM.downloadPublisher(for: message.codeMessage)) { state in
            guard downloadState != state else { return }
            downloadState = state
            if state == .success { loadFromDisk(fallingBackToPreview: false) }
        }
    }

    private func resolveIfNeeded() {
        if let uiImage = message.message.UIimage {
            if resolved !== uiImage { resolved = uiImage }
            return
        }
        if resolved != nil { return }

        if let cached = ChatImageMemoryCache.shared.image(forKey: message.codeMessage) {
            resolved = cached
            return
        }

        loadFromDisk(fallingBackToPreview: true)
    }

    /// Reads the real file, past the `resolved != nil` guard above.
    ///
    /// - Parameter fallingBackToPreview: whether the message's inline preview may
    ///   stand in when no file is found. False after a transfer: the tile is
    ///   already showing that preview, and replacing a picture with a blurrier
    ///   copy of itself is worse than leaving it alone.
    private func loadFromDisk(fallingBackToPreview: Bool) {
        let codeMessage = message.codeMessage
        let thumbnail = fallingBackToPreview ? message.message.thumbnail : nil
        let isVideo = message.typeMessage.isVideo
        let targetWidth = Self.maxPixelWidth

        Task.detached(priority: .userInitiated) {
            if let diskImage = DiskMediaManager.shared.loadImageFromDisk(fileName: codeMessage, pathName: .CHAT) {
                let prepared = await BubbleImageView.downsample(diskImage, toWidth: targetWidth)
                ChatImageMemoryCache.shared.store(prepared, forKey: codeMessage)
                await MainActor.run { resolved = prepared }
                return
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
                    let thumb = UIImage(cgImage: cgImage)
                    DiskMediaManager.shared.saveImageToDisk(thumb, fileName: codeMessage, pathName: .CHAT)
                    let prepared = await BubbleImageView.downsample(thumb, toWidth: targetWidth)
                    ChatImageMemoryCache.shared.store(prepared, forKey: codeMessage)
                    await MainActor.run { resolved = prepared }
                    return
                }
            }

            if let thumbnail, let decoded = decodeBase64ToUIImage(thumbnail) {
                let prepared = await BubbleImageView.downsample(decoded, toWidth: targetWidth)
                ChatImageMemoryCache.shared.store(prepared, forKey: codeMessage)
                await MainActor.run { resolved = prepared }
            }
        }
    }
}

// MARK: - Helper to Group Consecutive Media Messages
extension Array where Element == MessageDataItem {
    func groupedByConsecutiveMedia() -> [Either<MessageDataItem, MediaGroup>] {
        var result: [Either<MessageDataItem, MediaGroup>] = []
        var currentMediaGroup: [MessageDataItem] = []
        var currentDirection: MessageDirection?

        for message in self {
            let isMedia = message.typeMessage == .IMAGE || message.typeMessage.isVideo
            if isMedia {
                if currentDirection == message.direction || currentMediaGroup.isEmpty {
                    currentMediaGroup.append(message)
                    currentDirection = message.direction
                } else {
                    if !currentMediaGroup.isEmpty {
                        result.append(.right(MediaGroup(
                            messages: currentMediaGroup,
                            isFromCurrentUser: currentDirection == .sent
                        )))
                    }
                    currentMediaGroup = [message]
                    currentDirection = message.direction
                }
            } else {
                if !currentMediaGroup.isEmpty {
                    result.append(.right(MediaGroup(
                        messages: currentMediaGroup,
                        isFromCurrentUser: currentDirection == .sent
                    )))
                    currentMediaGroup = []
                    currentDirection = nil
                }
                result.append(.left(message))
            }
        }

        if !currentMediaGroup.isEmpty {
            result.append(.right(MediaGroup(
                messages: currentMediaGroup,
                isFromCurrentUser: currentDirection == .sent
            )))
        }

        return result
    }
}

// MARK: - Either Type for Mixed Content
enum Either<Left, Right> {
    case left(Left)
    case right(Right)

    var id: String {
        switch self {
        case .left(let message as MessageDataItem):
            return message.id
        case .right(let group as MediaGroup):
            return group.id
        default:
            return UUID().uuidString
        }
    }
}

