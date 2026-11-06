//
//  ChatRoomMediaViewerCoordinator.swift
//  FeatureChat
//

import Foundation
import UIKit

/// Turns a media tap into a `MediaViewerRequest`, and resolves document URLs.
///
/// Pure and static: no frames, no UIKit views, no presentation state. Everything
/// the transition needs about geometry comes from `MediaHeroAnchorRegistry`.
enum ChatRoomMediaViewerCoordinator {

    /// Builds the viewer request for a tapped media message.
    ///
    /// - Parameters:
    ///   - tapped: the message the user tapped.
    ///   - messages: the conversation's media messages, in timeline order.
    ///   - thumbnailProvider: resolves an in-memory thumbnail by `codeMessage`.
    /// - Returns: `nil` when the tapped message is neither image nor video.
    static func makeRequest(
        tapped: MessageDataItem,
        in messages: [MessageDataItem],
        thumbnailProvider: (String) -> UIImage?
    ) -> MediaViewerRequest? {
        guard isMedia(tapped) else { return nil }

        // A just-sent image may not have reached `allMediaMessages` yet; it still
        // has to open.
        var ordered = messages.filter(isMedia)
        if !ordered.contains(where: { $0.codeMessage == tapped.codeMessage }) {
            ordered.append(tapped)
        }

        var seen = Set<String>()
        let unique = ordered.filter { seen.insert($0.codeMessage).inserted }

        let items = unique.map { makeItem($0, thumbnail: thumbnailProvider($0.codeMessage)) }
        let startIndex = unique.firstIndex { $0.codeMessage == tapped.codeMessage } ?? 0

        return MediaViewerRequest(items: items, startIndex: startIndex)
    }

    static func resolveDocumentURL(for message: MessageDataItem) -> URL? {
        guard let fileString = message.message.file?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fileString.isEmpty else { return nil }

        if let url = URL(string: fileString), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: fileString)
    }

    // MARK: - Private

    private static func isMedia(_ message: MessageDataItem) -> Bool {
        (message.typeMessage == .IMAGE || message.typeMessage.isVideo) && !message.isViewOnce
    }

    /// Internal rather than private so a page can be rebuilt after its file
    /// arrives — `fullResURL` and `videoURL` are resolved here, and are the whole
    /// difference between a page that can show its media and one that cannot.
    static func makeItem(_ message: MessageDataItem, thumbnail: UIImage?) -> MediaViewerItem {
        let isVideo = message.typeMessage.isVideo
        return MediaViewerItem(
            id: message.codeMessage,
            kind: isVideo ? .video : .image,
            thumbnail: thumbnail,
            fullResURL: DiskMediaManager.shared.imageURL(for: message.codeMessage, pathName: .CHAT),
            videoURL: isVideo
                ? DiskMediaManager.shared.loadVideoFromDisk(fileName: message.codeMessage, pathName: .CHAT)
                : nil,
            videoDuration: message.message.videoDuration,
            senderName: message.senderName,
            displayTime: message.displayTime,
            caption: message.message.text,
            isSentByMe: message.isSentByMe
        )
    }

}
