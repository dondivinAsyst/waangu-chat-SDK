//
//  BubleTextView.swift
//  chatpreview
//
//  Created by Asyst on 6/30/25.
//

import SwiftUI
import WaanguCoreKit

struct BubbleTextView: View {
    let message: MessageDataItem
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    let isSelectionMode: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let bubbleHorizontalPadding: CGFloat = 24
    private let bubbleMinWidth: CGFloat = 120
    private let singleLineMetaReserve: CGFloat = 48

    private var bubbleMaxWidth: CGFloat {
        UIScreen.main.bounds.width * 0.75
    }

    private var contentMaxWidth: CGFloat {
        bubbleMaxWidth - bubbleHorizontalPadding
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            bubbleContent
            bubbleForwardButton(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
        }
        .frame(maxWidth: .infinity, alignment: message.direction == .sent ? .trailing : .leading)
        .padding(.leading, message.direction == .received ? 10 : 60)
        .padding(.trailing, message.direction == .received ? 60 : 10)
        .id(message.id)
    }

    // MARK: - Bubble shell

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            forwardedIndicator(
                for: message,
                forwardedLabel: chatVM.translationService?.resolve(
                    key: ChatTranslationKeys.FORWARDED,
                    module: ChatTranslationKeys.MODULE
                ).value ?? "Forwarded"
            )

            if let reply = message.reply,
               case .message(let repliedMessage?) = reply {
                ReplyPreviewView(
                    repliedMessage: repliedMessage,
                    chatVM: chatVM,
                    parentWidth: .constant(0),
                    isMediaParent: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .padding(.bottom, 4)
                    .onTapGesture {
                        guard !isSelectionMode else { return }
                        chatVM.handleReplyPreviewTap(repliedMessage)
                    }
                .allowsHitTesting(!isSelectionMode)
            }

            if let linkURL = LinkPreviewProvider.extractFirstURL(from: message.message.text) {
                if #available(iOS 17.0, *) {
                    LinkPreviewBubble(url: linkURL)
                        .padding(.bottom, 4)
                }
            }

            messageTextRow
        }
        .padding(.horizontal, 12)
        .padding(.top, message.forwarded == true ? 4 : 8)
        .padding(.bottom, 8)
        .frame(width: measuredBubbleWidth, alignment: .leading)
        .background(message.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .applyStrokeOnBubbleView()
        .applyTailView(message.direction)
        .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
    }

    // MARK: - Sizing

    private var hasReplyPreview: Bool {
        if case .message(let replied?) = message.reply { return replied != nil }
        return false
    }

    private var isMultilineText: Bool {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let metrics = textMetrics(
            for: message.message.text,
            font: font,
            maxWidth: contentMaxWidth - singleLineMetaReserve
        )
        return metrics.lines > 1
    }

    /// Explicit width avoids SwiftUI expanding the bubble background to the full row.
    private var measuredBubbleWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let textMetricsResult = textMetrics(
            for: message.message.text,
            font: font,
            maxWidth: contentMaxWidth - (isMultilineText ? 0 : singleLineMetaReserve)
        )

        let textBlockWidth: CGFloat
        if isMultilineText {
            textBlockWidth = textMetricsResult.occupiedWidth
        } else {
            textBlockWidth = textMetricsResult.occupiedWidth + singleLineMetaReserve
        }

        let stackedWidth = max(
            textBlockWidth,
            estimatedReplyPreviewWidth(),
            estimatedForwardedWidth()
        )

        return max(
            bubbleMinWidth,
            min(stackedWidth + bubbleHorizontalPadding, bubbleMaxWidth)
        )
    }

    private func estimatedReplyPreviewWidth() -> CGFloat {
        guard hasReplyPreview,
              case .message(let replied?) = message.reply else { return 0 }

        let name = (replied.direction == .sent
            ? (chatVM.translationService?.resolve(key: "you", module: ChatTranslationKeys.COMMON_MODULE).value ?? "You")
            : replied.senderName) ?? ""

        let preview: String = replyPreviewLabel(for: replied)

        let nameWidth = measureText(name, font: .systemFont(ofSize: 13, weight: .semibold))
        // Cap preview measure to ~2 lines worth of content width inside the bubble.
        let previewWidth = min(
            measureText(preview, font: .systemFont(ofSize: 13)),
            contentMaxWidth * 0.95
        )
        let textColumn = max(nameWidth, previewWidth)

        var width: CGFloat = 4 + 8 + textColumn + 8 + 16
        if showsReplyThumbnail(for: replied) {
            width += 40
        }
        return min(ceil(width), contentMaxWidth)
    }

    private func estimatedForwardedWidth() -> CGFloat {
        guard message.forwarded == true else { return 0 }
        let label = chatVM.translationService?.resolve(
            key: ChatTranslationKeys.FORWARDED,
            module: ChatTranslationKeys.MODULE
        ).value ?? "Forwarded"
        return measureText(label, font: .italicSystemFont(ofSize: 11)) + 18
    }

    private func replyPreviewLabel(for replied: MessageDataItem) -> String {
        func t(_ key: String) -> String {
            chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
        }

        if replied.isViewOnce { return t(ChatTranslationKeys.CHAT_VIEW_ONCE_MESSAGE) }
        switch replied.typeMessage {
        case .TEXT: return replied.message.text
        case .IMAGE: return t(ChatTranslationKeys.REPLY_PHOTO)
        case .VIDEO, .VIDEO_NOTE: return t(ChatTranslationKeys.REPLY_VIDEO)
        case .STATUS: return t(ChatTranslationKeys.REPLY_STATUS)
        case .AUDIO, .VOICE: return t(ChatTranslationKeys.REPLY_AUDIO)
        case .DOCUMENT: return t(ChatTranslationKeys.REPLY_DOCUMENT)
        case .CONTACT: return t(ChatTranslationKeys.REPLY_CONTACT)
        case .LOCATION: return t(ChatTranslationKeys.REPLY_LOCATION)
        default: return t(ChatTranslationKeys.REPLY_FALLBACK_MESSAGE)
        }
    }

    private func showsReplyThumbnail(for replied: MessageDataItem) -> Bool {
        switch replied.typeMessage {
        case .IMAGE, .VIDEO, .VIDEO_NOTE, .STATUS:
            return true
        default:
            return false
        }
    }

    private func measureText(_ text: String, font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    // MARK: - Text + meta

    @ViewBuilder
    private var messageTextRow: some View {
        if isMultilineText {
            Text(message.message.text)
                .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.bottom, 16)
                .overlay(alignment: .bottomTrailing) {
                    bubbleMetaOverlay
                }
        } else if hasReplyPreview {
            Text(message.message.text)
                .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)
                .overlay(alignment: .bottomTrailing) {
                    bubbleMetaOverlay
                }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(message.message.text)
                    .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))

                bubbleMetaOverlay
                    .alignmentGuide(.lastTextBaseline) { dimensions in
                        dimensions[.bottom] - 2
                    }
            }
        }
    }

    private var bubbleMetaOverlay: some View {
        BubbleMetaOverlay(
            message: message,
            style: .bubble(colorScheme: colorScheme),
            translationService: chatVM.translationService
        )
        .padding(.trailing, 0)
        .padding(.bottom, 0)
    }
}

// Extension pour factoriser les modificateurs communs
extension View {
    @ViewBuilder func applyDeletedMessageModifiers(message: MessageDataItem) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .applyStrokeOnBubbleView()
            .applyTailView(message.direction)
            .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity, alignment: message.alignment)
            .padding(.leading, message.direction == .received ? 10 : 60)
            .padding(.trailing, message.direction == .received ? 60 : 10)
    }

    @ViewBuilder func applyCommonModifiers(message: MessageDataItem) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.top, message.forwarded == true ? 4 : 8)
            .padding(.bottom, 8)
            .background(message.backgroundColor)
            .clipShape(RoundedRectangle(
                cornerRadius: 16, style: .continuous)
            )
            .applyStrokeOnBubbleView()
            .applyTailView(message.direction)
            .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75)
            .padding(.leading, message.direction == .received ? 10 : 60)
            .padding(.trailing, message.direction == .received ? 60 : 10)
    }
}
