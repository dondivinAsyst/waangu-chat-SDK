import SwiftUI
import WaanguSharedUI

/// What the thread shows for a view-once message, whatever its type: never the
/// content, only what it is. A tap opens the real bubble full screen, once; after
/// that it reads "Opened" for good on this device.
///
/// Each side has its own copy, so the sender gets one look too — but only once
/// the upload is done, because opening wipes the file the upload reads from.
struct BubbleViewOnceView: View {
    let message: MessageDataItem
    @ObservedObject var uploadVM: FileUploadViewModel
    /// Held, not observed: see `BubbleImageView`.
    let chatVM: ChatRoomViewModel
    let isSelectionMode: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var isOpened: Bool { message.isViewOnceOpened }
    private var isSent: Bool { message.direction == .sent }

    /// The sender's copy cannot be opened while it is still on its way.
    private var isUploading: Bool { isSent && message.mediaNeedsTransfer }

    private var canOpen: Bool { !isOpened && !isUploading && !isSelectionMode }

    private var transferConfig: InlineMediaTransferConfig {
        .forMessage(
            message,
            onUploadSuccess: { [codeMessage = message.codeMessage] remoteUrl in
                chatVM.clearPendingUpload(codeMessage: codeMessage, remoteUrl: remoteUrl)
            },
            onAutoTransferAttempt: { [codeMessage = message.codeMessage] attempts in
                chatVM.persistAutoTransferAttempts(codeMessage: codeMessage, attempts: attempts)
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon

            Text(isOpened ? t(ChatTranslationKeys.CHAT_VIEW_ONCE_OPENED, fallback: "Opened") : kindLabel)
                .font(.subheadline.weight(isOpened ? .regular : .semibold))
                .italic(isOpened)
                .foregroundStyle(
                    isOpened
                        ? ChatBubbleStyle.secondaryForeground(for: colorScheme)
                        : ChatBubbleStyle.foreground(for: colorScheme)
                )
                .lineLimit(1)
        }
        // Sized by its content. The time sits on its own line below, so the row
        // needs no spacer to make room for it.
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .fixedSize()
        .background(message.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .applyStrokeOnBubbleView()
        .applyTailView(message.direction)
        .overlay(alignment: .bottomTrailing) {
            BubbleMetaOverlay(message: message, style: .bubble(colorScheme: colorScheme), translationService: chatVM.translationService)
                .padding(.trailing, 4)
                .padding(.bottom, 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard canOpen else { return }
            chatVM.openViewOnce(message)
        }
        .frame(maxWidth: .infinity, alignment: message.alignment)
        .padding(.leading, isSent ? 60 : 5)
        .padding(.trailing, isSent ? 5 : 60)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .onAppear(perform: handleAppear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(canOpen ? .isButton : [])
        .accessibilityHint(canOpen ? t(ChatTranslationKeys.CHAT_VIEW_ONCE_CLOSE_HINT, fallback: "Once you close it, it can't be opened again.") : "")
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if isUploading {
            InlineMediaTransferControl(
                uploadVM: uploadVM,
                config: transferConfig,
                isSelectionMode: isSelectionMode,
                controlSize: 32,
                progressControlSize: 32,
                translator: chatVM.translationService,
                readyContent: { timerIcon }
            )
            .frame(width: 32, height: 32)
        } else {
            timerIcon
        }
    }

    private var timerIcon: some View {
        // Unopened: the same filled primary circle as the recorder's "on" state.
        // Opened: a plain grey timer — nothing left to open.
        Image(systemName: "timer")
            .font(.system(size: isOpened ? 20 : 16, weight: .semibold))
            .foregroundStyle(isOpened ? ChatBubbleStyle.secondaryForeground(for: colorScheme) : Color.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(isOpened ? Color.clear : AppColors.primary))
    }

    /// What kind of message is waiting, without anything of what it says.
    private var kindLabel: String {
        switch message.typeMessage {
        case .AUDIO, .VOICE:
            return t(ChatTranslationKeys.REPLY_VOICE_MESSAGE, fallback: "Voice message")
        case .IMAGE:
            return t(ChatTranslationKeys.REPLY_PHOTO, fallback: "Photo")
        case .VIDEO, .VIDEO_NOTE:
            return t(ChatTranslationKeys.REPLY_VIDEO, fallback: "Video")
        default:
            return t(ChatTranslationKeys.CHAT_VIEW_ONCE_MESSAGE, fallback: "View once message")
        }
    }

    private func handleAppear() {
        // Opened while the app was closed under it: finish the job now.
        if message.viewOnceNeedsWipe {
            chatVM.wipeViewOnceContent(codeMessage: message.codeMessage)
            return
        }
        // The real bubble is not in the thread to start the upload, so this does.
        if isSent, !isOpened {
            InlineMediaTransferExecutor.triggerAutoUploadIfNeeded(
                config: transferConfig,
                uploadVM: uploadVM
            )
        }
    }

    private func t(_ key: String, fallback: String) -> String {
        chatVM.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE)
            .value ?? fallback
    }
}
