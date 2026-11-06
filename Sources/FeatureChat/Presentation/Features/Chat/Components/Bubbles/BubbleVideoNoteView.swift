import SwiftUI
import WaanguSharedUI

/// A `VIDEO_NOTE`: a video shown in a round frame instead of a bubble.
///
/// Sent, stored, uploaded and downloaded exactly like a video — only the type and
/// the shape differ — so it takes its thumbnail from the same place as
/// `BubbleImageView`, shows the same transfer control, and a tap opens the same
/// viewer.
struct BubbleVideoNoteView: View {
    let message: MessageDataItem
    @ObservedObject var uploadVM: FileUploadViewModel
    /// Held, not observed: see `BubbleImageView`.
    let chatVM: ChatRoomViewModel
    let isSelectionMode: Bool

    @State private var downloadState: DownloadState?
    @State private var hasCheckedCache = false
    /// The sharpest picture we have; the inline preview stands in until a frame
    /// from disk replaces it, as in `BubbleImageView`.
    @State private var resolvedImage: UIImage?
    @State private var previewImage: UIImage?

    private static let diameter: CGFloat = min(UIScreen.main.bounds.width * 0.6, 240)
    private static let thumbnailPixelWidth: CGFloat = diameter * UIScreen.main.scale

    init(message: MessageDataItem, uploadVM: FileUploadViewModel, chatVM: ChatRoomViewModel, isSelectionMode: Bool = false) {
        self.message = message
        self.uploadVM = uploadVM
        self.chatVM = chatVM
        self.isSelectionMode = isSelectionMode

        let full = ChatImageMemoryCache.shared.image(forKey: message.codeMessage)
        _resolvedImage = State(initialValue: full)
        _previewImage = State(
            initialValue: full ?? ChatMediaPreviewCache.shared.preview(
                forKey: message.codeMessage,
                encoded: message.message.thumbnail
            )
        )
    }

    private var displayedImage: UIImage? {
        resolvedImage ?? previewImage
    }

    var body: some View {
        HStack(spacing: 8) {
            if message.direction == .sent {
                sideControl
            }

            VStack(alignment: message.direction == .sent ? .trailing : .leading, spacing: 4) {
                forwardedIndicator(
                    for: message,
                    forwardedLabel: chatVM.translationService?.resolve(key: ChatTranslationKeys.FORWARDED, module: ChatTranslationKeys.MODULE).value ?? "Forwarded"
                )

                if case .message(let repliedMessage?) = message.reply {
                    ReplyPreviewView(
                        repliedMessage: repliedMessage,
                        chatVM: chatVM,
                        parentWidth: .constant(Self.diameter),
                        isMediaParent: true
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Self.diameter)
                    .padding(6)
                    .background(message.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        guard !isSelectionMode else { return }
                        chatVM.handleReplyPreviewTap(repliedMessage)
                    }
                    .allowsHitTesting(!isSelectionMode)
                }

                noteCircle
            }

            if message.direction == .received {
                sideControl
            }
        }
        .frame(maxWidth: .infinity, alignment: message.alignment)
        .id(message.id)
        .padding(.leading, message.direction == .received ? 10 : 60)
        .padding(.trailing, message.direction == .received ? 60 : 10)
        .onAppear {
            resolveImageIfNeeded()

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

            if message.direction != .sent, !hasCheckedCache {
                hasCheckedCache = true
                uploadVM.checkIfCached(cachedkey: message.codeMessage, type: .video) { isCached in
                    downloadState = isCached == true ? .success : .idle
                }
            }
        }
        .onReceive(uploadVM.downloadPublisher(for: message.codeMessage)) { state in
            if downloadState != state {
                downloadState = state
            }
        }
        .onChange(of: downloadState) { newState in
            guard newState == .success else { return }
            resolvedImage = nil
            resolveImageIfNeeded()
        }
        .onChange(of: message.codeMessage) { _ in
            resolvedImage = nil
            previewImage = ChatMediaPreviewCache.shared.preview(
                forKey: message.codeMessage,
                encoded: message.message.thumbnail
            )
            hasCheckedCache = false
        }
    }

    // MARK: - Round frame

    private var noteCircle: some View {
        ZStack {
            Group {
                if let image = displayedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .heroAnchor(id: message.codeMessage, image: image)
                } else {
                    MediaPlaceholderFill(isVideo: true)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .clipShape(Circle())
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }

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
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .overlay(
            Circle().stroke(AppColors.primary, lineWidth: 2)
        )
        .overlay(alignment: .bottom) {
            HStack(spacing: 6) {
                if let duration = message.message.videoDuration, duration > 0 {
                    Text(formatDuration(duration))
                        .modifier(ConditionalFontModifier())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                }
                BubbleMetaOverlay(message: message, style: .media, translationService: chatVM.translationService)
            }
            .padding(.bottom, 8)
        }
        .contentShape(Circle())
        .onTapGesture {
            guard !isSelectionMode, !message.mediaNeedsTransfer else { return }
            chatVM.onTapMedia(message)
        }
    }

    /// The retry marker or the forward button, beside the circle as beside a
    /// media bubble.
    @ViewBuilder
    private var sideControl: some View {
        if message.message.shouldRetry {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.red)
                .font(.headline)
        } else {
            bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
        }
    }

    // MARK: - Thumbnail

    private func resolveImageIfNeeded() {
        if resolvedImage != nil { return }

        if let cached = ChatImageMemoryCache.shared.image(forKey: message.codeMessage) {
            resolvedImage = cached
            return
        }

        let codeMessage = message.codeMessage
        let targetWidth = Self.thumbnailPixelWidth
        Task.detached(priority: .userInitiated) {
            guard let prepared = BubbleImageView.loadLocalThumbnail(
                codeMessage: codeMessage,
                isVideo: true,
                targetWidth: targetWidth
            ) else { return }
            await MainActor.run { resolvedImage = prepared }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
