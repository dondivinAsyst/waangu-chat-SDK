//
//  ChatCameraFlowView.swift
//  FeatureChat
//

import WaanguCoreKit
import SwiftUI

struct ChatCameraFlowView: View {
    @ObservedObject var mediaViewModel: PHMediaManagerViewModel
    let recipientName: String
    let translationService: (any TranslationServiceProtocol)?
    let onSendGalleryMedia: (String?, GalleryMedia) -> Void
    let onSendCapturedMedia: (String?, CapturedCameraMedia) -> Void
    let onDismiss: () -> Void
    /// Sends the edited media as view once. Nil hides the editor's toggle, as
    /// in channels.
    var onSendViewOnce: ((String?, EditedMediaResult) -> Void)? = nil

    @StateObject private var sessionController = ChatCameraSessionController()
    @State private var previewMedia: PreviewMediaItem?
    @Environment(\.dismiss) private var dismiss

    private var isShowingEditor: Bool { previewMedia != nil }

    var body: some View {
        ZStack {
            CameraCaptureView(
                mediaViewModel: mediaViewModel,
                sessionController: sessionController,
                onMediaSelected: { media in
                    openEditor(PreviewMediaItem(source: .gallery(media)))
                },
                onCaptured: { captured in
                    openEditor(PreviewMediaItem(source: .captured(captured)))
                },
                onDismiss: {
                    onDismiss()
                    dismiss()
                }
            )
            .opacity(isShowingEditor ? 0 : 1)
            .allowsHitTesting(!isShowingEditor)
            .zIndex(0)

            if let preview = previewMedia {
                ChatMediaEditorView(
                    previewMedia: preview,
                    recipientName: recipientName,
                    mediaCount: max(1, mediaViewModel.selectedMedia.count),
                    translationService: translationService,
                    onSend: { caption, result in
                        handleSend(result: result, caption: caption)
                    },
                    onDismiss: {
                        closeEditor()
                    },
                    onAddMoreMedia: {
                        closeEditor()
                    },
                    onSendViewOnce: onSendViewOnce.map { send in
                        { caption, result in
                            send(caption, result)
                            onDismiss()
                            dismiss()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(ChatMediaOpenAnimation.editorInsertion)
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .animation(ChatMediaOpenAnimation.spring, value: previewMedia?.id)
    }

    private func openEditor(_ item: PreviewMediaItem) {
        withAnimation(ChatMediaOpenAnimation.spring) {
            previewMedia = item
        }
    }

    private func closeEditor() {
        withAnimation(ChatMediaOpenAnimation.spring) {
            previewMedia = nil
        }
    }

    private func handleSend(result: EditedMediaResult, caption: String?) {
        switch result {
        case .uneditedGallery(let media):
            onSendGalleryMedia(caption, media)
        case .exportedImage(let image, let jpegData):
            onSendCapturedMedia(caption, .image(image, jpegData: jpegData))
        case .exportedVideo(let url):
            onSendCapturedMedia(caption, .video(url))
        }
        onDismiss()
        dismiss()
    }
}
