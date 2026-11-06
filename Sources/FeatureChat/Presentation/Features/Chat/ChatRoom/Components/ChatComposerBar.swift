//
//  ChatComposerBar.swift
//  FeatureChat
//

import SwiftUI
import UIKit

/// The message input toolbar, isolated from the message list.
///
/// This exists as its own view purely so that `@ObservedObject composer` — which
/// publishes on every keystroke — invalidates the toolbar and nothing above it.
/// Inlined in the list's body, as it used to be, each character re-evaluated the
/// list and re-measured every visible bubble.
///
/// `viewModel` is held as a plain `let` for the same reason: the bar calls methods
/// on it and reads two stable references off it, but must not subscribe to it.
/// Values that do change and matter here — the locale token, the appearance style —
/// are passed in by the list, which is already observing them.
@available(iOS 17.0, *)
struct ChatComposerBar: View {
    @ObservedObject var composer: ChatComposerModel
    let viewModel: ChatRoomViewModel
    let localeToken: Int
    let userInterfaceStyle: UIUserInterfaceStyle
    @Binding var contentHeight: CGFloat

    var body: some View {
        TextInputToolbarAreaViewWrapper(
            text: $composer.text,
            voiceRecordingViewModel: viewModel.voiceRecordingVM,
            translationService: viewModel.translationService,
            localeToken: localeToken,
            userInterfaceStyle: userInterfaceStyle,
            onPresentSheet: {
                viewModel.onUserOpenChatActionsSheet()
            },
            onOpenCamera: {
                viewModel.onUserOpenCamera()
            },
            onOpenVideoNote: {
                viewModel.onUserOpenVideoNote()
            },
            onOpenPayments: { viewModel.openFinanceHome() },
            onSendMessage: { text in
                viewModel.sendTextMessage(text)
                viewModel.dismissLinkPreview()
            },
            onSendAudio: {
                Task { await viewModel.stopVoiceRecording() }
            },
            onStartRecording: {
                Task { await viewModel.startVoiceRecording() }
            },
            onStopRecording: {
                Task { await viewModel.cancelVoiceRecording() }
            },
            onReadOnce: { isViewOnce in
                viewModel.setVoiceNoteViewOnce(isViewOnce)
            },
            onPauseOrResumeRecording: { isPaused in
                Task {
                    if isPaused {
                        await viewModel.resumeVoiceRecording()
                    } else {
                        await viewModel.pauseVoiceRecording()
                    }
                }
            },
            onTextChanged: { text in
                viewModel.onTextChanged(text)
            },
            contentHeight: $contentHeight
        )
        .frame(height: contentHeight)
        .background(Material.regular)
    }
}
