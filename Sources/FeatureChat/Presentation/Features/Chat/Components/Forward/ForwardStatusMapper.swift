//
//  ForwardStatusMapper.swift
//  FeatureChat
//

import Foundation
import SwiftUI
import UIKit
import WaanguSharedUI

/// Posts a story to the current user's status.
///
/// Declared here so the chat room can forward a message into the status feature
/// without owning `StatusUseCases`: the room is handed whatever already holds
/// them — today `StoriesViewModel`, which the chat screen already observes.
@MainActor
protocol ForwardStatusPosting: AnyObject {
    func addOwnStatus(story: StoryToSend) async
}

extension StoriesViewModel: ForwardStatusPosting {}

/// Turns a chat message into a story that can be posted to the user's status.
///
/// A status carries text, an image or a video and nothing else — a location, a
/// contact card, a poll or a call record has no status form. Those are reported
/// as unsupported so the picker can hide the row instead of accepting the tap
/// and dropping the message.
enum ForwardStatusMapper {

    /// Whether every message in the selection can become a status item.
    ///
    /// All-or-nothing on purpose: posting three of five selected photos and
    /// silently skipping the rest is worse than not offering the row.
    static func canPost(_ messages: [MessageDataItem]) -> Bool {
        !messages.isEmpty && messages.allSatisfy(isSupported)
    }

    static func isSupported(_ message: MessageDataItem) -> Bool {
        guard !message.isDeleted else { return false }
        switch message.typeMessage {
        case .TEXT:
            return !message.message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .IMAGE:
            // The bytes have to be on this device: a status uploads its own copy
            // rather than pointing at the chat message's remote URL.
            return DiskMediaManager.shared.hasDiskImage(for: message.codeMessage, pathName: .CHAT)
        case .VIDEO, .VIDEO_NOTE:
            return DiskMediaManager.shared.hasDiskVideo(for: message.codeMessage, pathName: .CHAT)
        default:
            return false
        }
    }

    /// Builds the story for one message. `caption` is the text typed in the
    /// forward sheet; the message's own caption is used when nothing was typed.
    static func story(from message: MessageDataItem, caption: String?) -> StoryToSend? {
        let session = CurrentSessionInfo.shared
        let id = StatusIDGenerator.newCode()
        let resolvedCaption = caption ?? existingCaption(of: message)

        switch message.typeMessage {
        case .TEXT:
            let text = message.message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return StoryToSend(
                id: id,
                userId: session.currentUid,
                type: .text,
                content: text,
                background: textBackgroundHex,
                fontText: "system",
                fontWeight: "regular",
                userName: session.userName,
                userImage: nil
            )

        case .IMAGE:
            guard let url = DiskMediaManager.shared.imageURL(
                for: message.codeMessage,
                pathName: .CHAT
            ) else { return nil }
            let thumbnail = DiskMediaManager.shared
                .loadImageFromDisk(fileName: message.codeMessage, pathName: .CHAT)
                .flatMap { imageToDataURL($0) }
            return StoryToSend(
                id: id,
                userId: session.currentUid,
                type: .image,
                content: url.absoluteString,
                caption: resolvedCaption,
                thumbnail: thumbnail,
                userName: session.userName,
                userImage: nil,
                fileSize: fileSize(at: url) ?? message.message.size ?? 0
            )

        case .VIDEO, .VIDEO_NOTE:
            guard let url = DiskMediaManager.shared.loadVideoFromDisk(
                fileName: message.codeMessage,
                pathName: .CHAT
            ) else { return nil }
            // Chat stores the video poster under the same code as the video.
            let thumbnail = DiskMediaManager.shared
                .loadImageFromDisk(fileName: message.codeMessage, pathName: .CHAT)
                .flatMap { imageToDataURL($0) }
            return StoryToSend(
                id: id,
                userId: session.currentUid,
                type: .video,
                content: url.absoluteString,
                caption: resolvedCaption,
                thumbnail: thumbnail,
                userName: session.userName,
                userImage: nil,
                fileSize: fileSize(at: url) ?? message.message.size ?? 0
            )

        default:
            return nil
        }
    }

    // MARK: - Helpers

    /// First swatch of the status editor palette, so a forwarded text status
    /// looks like one composed in the editor.
    private static var textBackgroundHex: String {
        ConstantColors.customColors.first?.toHex() ?? "#663399"
    }

    private static func existingCaption(of message: MessageDataItem) -> String? {
        let caption = (message.message.caption ?? message.message.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return caption.isEmpty ? nil : caption
    }

    private static func fileSize(at url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }
}
