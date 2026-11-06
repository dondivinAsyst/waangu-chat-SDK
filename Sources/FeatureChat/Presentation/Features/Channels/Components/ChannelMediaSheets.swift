//
//  ChannelMediaSheets.swift
//  FeatureChat
//

import SwiftUI

/// The channel composer's sheets: attachments, camera, the media editor and
/// document preview.
///
/// Bound to `ChannelRoomViewModel`, not to the chat room's. The sheets
/// themselves — `SheetActionView`, `ChatCameraFlowView`, `ChatMediaEditorView` —
/// take plain closures, so they are shared between the two rooms without either
/// room sharing a view model with the other.
@available(iOS 16.0, *)
struct ChannelMediaSheets: ViewModifier {

    @ObservedObject var viewModel: ChannelRoomViewModel
    @ObservedObject var mediaViewModel: PHMediaManagerViewModel
    let galleryViewModel: GalleryViewModel
    let financeSurface: ChatFinanceSurface

    func body(content: Content) -> some View {
        content
            .chatAppearanceSheet(isPresented: $viewModel.showAttachments) {
                attachmentsSheet
            }
            .chatAppearanceFullScreenCover(isPresented: $viewModel.showCamera) {
                cameraCover
            }
            .chatAppearanceFullScreenCover(isPresented: galleryEditorBinding) {
                galleryEditorCover
            }
            .chatAppearanceSheet(isPresented: documentPreviewBinding) {
                documentPreview
            }
    }

    // MARK: - Attachments

    private var attachmentsSheet: some View {
        SheetActionView(
            onDismiss: {
                viewModel.closeAttachments()
            },
            onSendMedia: { caption in
                viewModel.closeAttachments()
                viewModel.postMedia(caption: caption, selectedMedia: mediaViewModel.selectedMedia)
                mediaViewModel.resetSelectedMedia()
            },
            onOpenMediaEditor: { media in
                viewModel.openGalleryMediaEditor(with: media)
            },
            onSendFiles: { urls in
                viewModel.closeAttachments()
                for url in urls {
                    viewModel.postDocument(fileURL: url)
                }
            },
            onSendContacts: { contacts in
                viewModel.closeAttachments()
                viewModel.postContacts(contacts)
            },
            onSendLocation: { location in
                viewModel.closeAttachments()
                viewModel.postLocation(location)
            },
            onSendPoll: { question, options, allowsMultipleAnswers in
                viewModel.closeAttachments()
                viewModel.postPoll(
                    question: question,
                    options: options,
                    allowsMultipleAnswers: allowsMultipleAnswers
                )
            },
            financeSurface: financeSurface,
            // A channel is a broadcast, not a conversation between two parties:
            // there is nobody to pay and nobody to be paid, so the finance hub
            // opens with no context rather than a wrong one.
            financeContext: nil,
            onSelectFinanceEntry: { _ in },
            conversationId: viewModel.conversationIdForSheets ?? "",
            loadRecentDocuments: {
                await viewModel.recentDocuments()
            },
            translationService: viewModel.translationService,
            galleryViewModel: galleryViewModel,
            mediaViewModel: mediaViewModel
        )
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(500), .large])
    }

    // MARK: - Camera

    private var cameraCover: some View {
        ChatCameraFlowView(
            mediaViewModel: mediaViewModel,
            recipientName: viewModel.channel?.name ?? "",
            translationService: viewModel.translationService,
            onSendGalleryMedia: { caption, media in
                viewModel.closeCamera()
                viewModel.postMedia(caption: caption, selectedMedia: [media])
                mediaViewModel.resetSelectedMedia()
            },
            onSendCapturedMedia: { caption, captured in
                viewModel.closeCamera()
                viewModel.postCapturedMedia(captured, caption: caption)
                mediaViewModel.resetSelectedMedia()
            },
            onDismiss: {
                viewModel.closeCamera()
                mediaViewModel.resetSelectedMedia()
            }
        )
    }

    // MARK: - Editor

    private var galleryEditorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.galleryEditorPreview != nil },
            set: { isPresented in
                if !isPresented { viewModel.closeGalleryMediaEditor() }
            }
        )
    }

    @ViewBuilder
    private var galleryEditorCover: some View {
        if let preview = viewModel.galleryEditorPreview {
            ChatMediaEditorView(
                previewMedia: preview,
                recipientName: viewModel.channel?.name ?? "",
                mediaCount: max(1, mediaViewModel.selectedMedia.count),
                translationService: viewModel.translationService,
                onSend: { caption, result in
                    viewModel.postEditedMedia(result, caption: caption)
                    viewModel.closeGalleryMediaEditor()
                    mediaViewModel.resetSelectedMedia()
                },
                onDismiss: {
                    viewModel.closeGalleryMediaEditor()
                },
                onAddMoreMedia: {
                    viewModel.closeGalleryMediaEditor()
                    viewModel.showAttachments = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
    }

    // MARK: - Documents

    private var documentPreviewBinding: Binding<Bool> {
        Binding(
            get: { viewModel.documentPreviewURL != nil },
            set: { isPresented in
                if !isPresented { viewModel.documentPreviewURL = nil }
            }
        )
    }

    @ViewBuilder
    private var documentPreview: some View {
        if let url = viewModel.documentPreviewURL {
            DocumentPreviewSheet(url: url)
        }
    }
}
