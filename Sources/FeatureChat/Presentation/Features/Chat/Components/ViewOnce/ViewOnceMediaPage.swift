//
//  ViewOnceMediaPage.swift
//  FeatureChat
//

import AVKit
import WaanguCoreKit
import SwiftUI

/// A view-once photo or video inside `ViewOnceMessageViewer`.
///
/// Not the chat's media viewer: that one offers save, share and forward, and
/// pages through the whole conversation. Here there is only this one item. A
/// received item that is not on the device yet is fetched by the same transfer
/// control the bubbles use, and shown once it lands.
struct ViewOnceMediaPage: View {
    let message: MessageDataItem
    @ObservedObject var uploadVM: FileUploadViewModel
    let translationService: (any TranslationServiceProtocol)?

    @State private var image: UIImage?
    @State private var player: AVPlayer?

    private var isVideo: Bool { message.typeMessage.isVideo }

    var body: some View {
        VStack(spacing: 12) {
            InlineMediaTransferControl(
                uploadVM: uploadVM,
                config: .forMessage(message),
                isSelectionMode: false,
                controlSize: 56,
                progressControlSize: 56,
                translator: translationService,
                readyContent: { media }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !message.message.text.isEmpty {
                Text(message.message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var media: some View {
        Group {
            if isVideo {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Color.black
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let code = message.codeMessage
        if isVideo {
            guard player == nil,
                  let url = DiskMediaManager.shared.loadVideoFromDisk(fileName: code, pathName: .CHAT) else { return }
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        } else if image == nil {
            image = DiskMediaManager.shared.loadImageFromDisk(fileName: code, pathName: .CHAT)
                ?? message.message.UIimage
        }
    }
}
