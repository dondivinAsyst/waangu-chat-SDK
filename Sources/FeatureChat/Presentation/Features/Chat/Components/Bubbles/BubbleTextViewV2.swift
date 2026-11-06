//
//  BubbleTextViewV2.swift
//
//  A from-scratch WhatsApp-style text bubble that truly hugs its content.
//
//  Layout strategy (identical to WhatsApp):
//  ┌──────────────────────────────────┐
//  │ [Forwarded indicator?]           │
//  │ [Reply preview?]                 │
//  │ [Link preview?]                  │
//  │ Message text        12:34 ✓✓    │  ← single-line if fits
//  └──────────────────────────────────┘
//  If the text + timestamp don't fit on one line:
//  ┌────────────────────┐
//  │ [Forwarded?]       │
//  │ [Reply?]           │
//  │ Message text that  │
//  │ wraps here         │
//  │              12:34 │  ← timestamp pushed to its own trailing line
//  └────────────────────┘
//
//  The bubble width = content-fit, capped at 75% of screen.
//  No Spacer(), no GeometryReader inside layout, no ViewThatFits expansion.
//

import SwiftUI

// MARK: - Public entry point (same signature as BubbleTextView)

struct BubbleTextViewV2: View {
    let message: MessageDataItem
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    let isSelectionMode: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(message: MessageDataItem, chatVM: ChatRoomViewModel, isSelectionMode: Bool = false) {
        self.message = message
        self.chatVM = chatVM
        self.isSelectionMode = isSelectionMode
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            bubbleContent
        }
        // Outer row fills full width and aligns the bubble to sent/received side
        .frame(maxWidth: .infinity, alignment: message.direction == .sent ? .trailing : .leading)
        .padding(.leading, message.direction == .received ? 5 : 55)
        .padding(.trailing, message.direction == .received ? 55 : 5)
        .id(message.id)
    }

    // MARK: - Bubble shell

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Forwarded indicator (inside the bubble, above content) ──
            if message.forwarded == true {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.forward.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(
                        chatVM.translationService?.resolve(
                            key: ChatTranslationKeys.FORWARDED,
                            module: ChatTranslationKeys.MODULE
                        ).value ?? "Forwarded"
                    )
                    .font(.system(size: 11))
                    .italic()
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 2)
            }

            // ── Reply preview ──
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
                .onTapGesture {
                    guard !isSelectionMode else { return }
                        chatVM.handleReplyPreviewTap(repliedMessage)
                }
                .allowsHitTesting(!isSelectionMode)
                .padding(.bottom, 4)
            }

            // ── Link preview (iOS 17+) ──
            if let linkURL = LinkPreviewProvider.extractFirstURL(from: message.message.text) {
                if #available(iOS 17.0, *) {
                    LinkPreviewBubble(url: linkURL)
                        .padding(.bottom, 4)
                }
            }

            // ── Core text + timestamp overlaid bottom-trailing (WhatsApp-style) ──
            VStack(alignment: .leading, spacing: 0) {
                Text(message.message.text)
                    .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                BubbleMetaOverlay(message: message, style: .bubble(colorScheme: colorScheme), translationService: chatVM.translationService)
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, message.forwarded == true ? 4 : 8)
        .padding(.bottom, 8)
        .background(message.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .applyStrokeOnBubbleView()
        .applyTailView(message.direction)
        .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
        // Cap at 75% — but only as a ceiling, not a floor
        .frame(maxWidth: UIScreen.main.bounds.width * 0.75)
    }
}
