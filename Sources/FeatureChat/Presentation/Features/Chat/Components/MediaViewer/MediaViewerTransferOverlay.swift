import SwiftUI

/// The media viewer's transfer control.
///
/// This is `MediaTransferButton` — the same control the bubble shows over its
/// media — hosted over the page. Not a variant of it and not a second
/// implementation: a viewer with its own retry would have to re-derive progress,
/// cancel, the retry allowance and the "is this file here" question, and would
/// drift from the bubble the first time either changed.
///
/// It also observes `FileUploadViewModel`, which a page cannot. The viewer's item
/// is a snapshot taken when the user tapped, so a page that opened mid-transfer
/// had no way to learn how that transfer ended.
struct MediaViewerTransferOverlay: View {
    @ObservedObject var uploadVM: FileUploadViewModel
    let message: MessageDataItem
    /// Held, not observed: the room is a service locator here.
    let chatVM: ChatRoomViewModel
    /// The file is now on this device. The page re-resolves its URLs and loads it.
    let onReady: () -> Void

    var body: some View {
        MediaTransferButton(
            uploadVM: uploadVM,
            messages: [message],
            isDownload: message.mediaTransferIsDownload,
            translationService: chatVM.translationService,
            onRetryRequested: { code in
                chatVM.clearAutoTransferAttempts(codeMessage: code)
            },
            onTransferComplete: onReady,
            onUploadSuccess: { code, remoteUrl in
                chatVM.clearPendingUpload(codeMessage: code, remoteUrl: remoteUrl)
            },
            onAutoTransferAttempt: { code, attempts in
                chatVM.persistAutoTransferAttempts(codeMessage: code, attempts: attempts)
            }
        )
    }
}
