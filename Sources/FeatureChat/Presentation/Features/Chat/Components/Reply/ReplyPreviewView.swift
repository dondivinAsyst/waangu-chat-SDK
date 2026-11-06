import SwiftUI
import WaanguSharedUI
import WaanguCoreKit
import SDWebImageSwiftUI

struct ReplyPreviewView: View {
    let repliedMessage: MessageDataItem?
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    @State private var mediaCount: Int
    @Binding var parentWidth: CGFloat
    let isMediaParent: Bool

    // Cached thumbnail so we don't Base64-decode on every body evaluation
    @State private var cachedThumbnail: UIImage?

    init(repliedMessage: MessageDataItem?, chatVM: ChatRoomViewModel, parentWidth: Binding<CGFloat>, isMediaParent: Bool) {
        self.repliedMessage = repliedMessage
        self.chatVM = chatVM
        self._parentWidth = parentWidth
        self.isMediaParent = isMediaParent
        // Initialize from caches at init time to avoid flash on LazyVStack recycle
        _cachedThumbnail = State(initialValue: Self.decodeThumbnail(for: repliedMessage))
        _mediaCount = State(initialValue: chatVM.cachedMediaCount(for: repliedMessage?.groupId ?? ""))
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // Sender name
                Text((repliedMessage?.direction == .sent ? common("you") : repliedMessage?.senderName) ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(repliedMessage?.direction == .sent ? .green : .blue)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Message preview — clamp to bubble width (WhatsApp-style)
                if (repliedMessage?.typeMessage == .IMAGE || repliedMessage?.typeMessage.isVideo == true), mediaCount > 1 {
                    Text(t(ChatTranslationKeys.REPLY_MEDIA_COUNT, args: ["\(mediaCount)"]))
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(replyPreviewText)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Media thumbnail (only for single media / non-text status replies)
            if mediaCount <= 1, showsReplyThumbnail {
                replyThumbnail
                    .frame(width: 40, height: 40)
                    .cornerRadius(4)
            }
        }
        // The colored bar is an overlay, not a sibling: a bare Shape is flexible on
        // both axes, and as an HStack child it swallowed whatever height the parent
        // proposed — which stretched the whole quote inside the context-menu copy,
        // where the bubble sits in a VStack that proposes a real height.
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(repliedMessage?.direction == .sent ? Color.blue : Color.green)
                .frame(width: 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(
            maxWidth: replyMaxWidth,
            alignment: .leading
        )
        .background(
            Color.black.opacity(repliedMessage?.direction == .sent ? 0.1 : 0.05)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            mediaCount = chatVM.cachedMediaCount(for: repliedMessage?.groupId ?? "")
            if cachedThumbnail == nil {
                cachedThumbnail = Self.decodeThumbnail(for: repliedMessage)
            }
        }
    }

    /// Media parents pass an explicit width; text bubbles rely on parent proposal.
    private var replyMaxWidth: CGFloat? {
        if isMediaParent, parentWidth > 0 {
            return parentWidth
        }
        return .infinity
    }

    /// Static thumbnail cache shared across all ReplyPreviewView instances
    private static var thumbnailCache: [String: UIImage] = [:]

    private static func decodeThumbnail(for message: MessageDataItem?) -> UIImage? {
        guard let message = message else { return nil }
        let showsThumbnail = (message.typeMessage == .IMAGE
            || message.typeMessage.isVideo
            || (message.typeMessage == .STATUS && Self.hasStatusMediaAttachment(message)))
        guard showsThumbnail else { return nil }

        let cacheKey = message.codeMessage
        if let cached = thumbnailCache[cacheKey] { return cached }

        let candidates = [
            message.message.thumbnail,
            message.message.image,
            message.message.video
        ].compactMap { $0 }.filter { !$0.isEmpty }

        for raw in candidates {
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                continue
            }
            if let image = imageFromDataURL(raw.cleanedBase64) {
                thumbnailCache[cacheKey] = image
                return image
            }
            if let image = imageFromFileOrRemotePath(raw) {
                thumbnailCache[cacheKey] = image
                return image
            }
        }
        return nil
    }

    private static func imageFromFileOrRemotePath(_ path: String) -> UIImage? {
        // Only sync-decode local paths here; remote URLs should not block the main thread.
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return nil
        }
        let url: URL?
        if path.hasPrefix("file://") {
            url = URL(string: path)
        } else if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = nil
        }
        guard let fileURL = url,
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private static func hasStatusMediaAttachment(_ message: MessageDataItem) -> Bool {
        guard message.typeMessage == .STATUS else { return false }
        return [message.message.thumbnail, message.message.image, message.message.video]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
    }
}

extension ReplyPreviewView {
    private var isTextStatusReply: Bool {
        guard let repliedMessage else { return false }
        return repliedMessage.typeMessage == .STATUS && !Self.hasStatusMediaAttachment(repliedMessage)
    }

    private var showsReplyThumbnail: Bool {
        switch repliedMessage?.typeMessage {
        case .IMAGE, .VIDEO, .VIDEO_NOTE:
            return true
        case .STATUS:
            return repliedMessage.map { Self.hasStatusMediaAttachment($0) } ?? false
        default:
            return false
        }
    }

    private var remoteThumbnailURL: URL? {
        guard showsReplyThumbnail, let repliedMessage else { return nil }
        let candidates = [
            repliedMessage.message.thumbnail,
            repliedMessage.message.image,
            repliedMessage.message.video
        ]
        guard let raw = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }),
              raw.hasPrefix("http://") || raw.hasPrefix("https://"),
              let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    private var replyPreviewText: String {
        if repliedMessage?.isDeleted == true {
            return t(ChatTranslationKeys.MESSAGE_DELETED)
        }
        if repliedMessage?.isViewOnce == true {
            return t(ChatTranslationKeys.CHAT_VIEW_ONCE_MESSAGE)
        }
        switch repliedMessage?.typeMessage {
        case .TEXT:
            return repliedMessage?.message.text ?? ""
        case .IMAGE:
            return t(ChatTranslationKeys.REPLY_PHOTO)
        case .VIDEO, .VIDEO_NOTE:
            return t(ChatTranslationKeys.REPLY_VIDEO)
        case .STATUS:
            if isTextStatusReply {
                return repliedMessage?.message.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? t(ChatTranslationKeys.REPLY_STATUS)
            }
            return t(ChatTranslationKeys.REPLY_STATUS)
        case .AUDIO, .VOICE:
            return t(ChatTranslationKeys.REPLY_AUDIO)
        case .DOCUMENT:
            return t(ChatTranslationKeys.REPLY_DOCUMENT)
        case .CONTACT:
            return t(ChatTranslationKeys.REPLY_CONTACT)
        case .LOCATION:
            return t(ChatTranslationKeys.REPLY_LOCATION)
        case .POLL:
            return t(ChatTranslationKeys.REPLY_POLL)
        default:
            return t(ChatTranslationKeys.REPLY_FALLBACK_MESSAGE)
        }
    }

    @ViewBuilder
    private var replyThumbnail: some View {
        switch repliedMessage?.typeMessage {
        case .IMAGE, .VIDEO, .VIDEO_NOTE:
            thumbnailImage
        case .STATUS where !isTextStatusReply:
            thumbnailImage
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let uiImage = cachedThumbnail {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if let remoteThumbnailURL {
            WebImage(url: remoteThumbnailURL)
                .resizable()
                .indicator(.activity)
                .scaledToFill()
                .clipped()
        } else {
            Color.gray.opacity(0.2)
        }
    }
}

extension ReplyPreviewView {
    private func t(_ key: String, args: [String] = []) -> String {
        chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
