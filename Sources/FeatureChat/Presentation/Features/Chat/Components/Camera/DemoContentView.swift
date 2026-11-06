//
//  DemoContentView.swift
//  FeatureChat
//

import SwiftUI

struct DemoContentView: View {
    @StateObject private var mediaViewModel = PHMediaManagerViewModel(mediaManager: PHMediaManager())
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Button("Open Camera Screen") {
                    withAnimation(ChatMediaOpenAnimation.spring) { showCamera = true }
                }
                NavigationLink("Open Photo Preview Screen") {
                    PhotoPreviewView(
                        previewMedia: PreviewMediaItem(
                            source: .captured(.image(UIImage(systemName: "photo")!, jpegData: nil))
                        ),
                        recipientName: "Armand",
                        onSend: { _ in },
                        onDismiss: {}
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            ChatCameraFlowView(
                mediaViewModel: mediaViewModel,
                recipientName: "Armand",
                translationService: nil,
                onSendGalleryMedia: { _, _ in
                    withAnimation(ChatMediaOpenAnimation.spring) { showCamera = false }
                },
                onSendCapturedMedia: { _, _ in
                    withAnimation(ChatMediaOpenAnimation.spring) { showCamera = false }
                },
                onDismiss: {
                    withAnimation(ChatMediaOpenAnimation.spring) { showCamera = false }
                }
            )
        }
    }
}

#Preview {
    DemoContentView()
}
