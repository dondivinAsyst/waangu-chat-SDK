//
//  GroupSenderRunResolver.swift
//  FeatureChat
//

import Foundation

/// Where a row sits inside a run of consecutive messages from one sender.
///
/// A group thread would repeat the same name and face on every single bubble
/// unless the run is collapsed. The name goes on the row that opens a run, the
/// avatar on the row that closes it, so a burst of messages reads as one block
/// with one name at its head and one face at its foot.
struct SenderRunPosition: Equatable {
    let isFirstOfRun: Bool
    let isLastOfRun: Bool
}

/// Decides, per timeline row, whether it opens or closes a run of consecutive
/// messages from the same sender.
enum GroupSenderRunResolver {

    /// Keyed by `MessageRow.id`.
    ///
    /// A row missing from the map shows neither name nor avatar and gets no
    /// gutter: own messages, system records, and every row of a direct chat.
    static func resolve(
        sections: [MessageSection],
        isGroup: Bool
    ) -> [String: SenderRunPosition] {
        guard isGroup else { return [:] }

        var positions: [String: SenderRunPosition] = [:]

        // Resolved per section, so a run never spans a day header — the first
        // message under "Today" opens a new block even when the same person
        // sent the last message of yesterday.
        for section in sections {
            let senderIds = section.rows.map(runSenderId(of:))

            for (index, senderId) in senderIds.enumerated() {
                guard let senderId else { continue }
                let previous = index > 0 ? senderIds[index - 1] : nil
                let next = index + 1 < senderIds.count ? senderIds[index + 1] : nil

                positions[section.rows[index].id] = SenderRunPosition(
                    isFirstOfRun: previous != senderId,
                    isLastOfRun: next != senderId
                )
            }
        }

        return positions
    }

    /// The sender a run is keyed on, or nil for a row that cannot belong to one.
    ///
    /// Returning nil is what makes checkpoints and banners *break* a run rather
    /// than be absorbed into it: two messages from one person with a "X joined"
    /// between them are two blocks, each with its own name and face.
    private static func runSenderId(of row: MessageRow) -> String? {
        guard let message = row.primaryMessage,
              message.direction == .received,
              !message.senderId.isEmpty
        else { return nil }

        // A group event carries a sender id but is drawn as a checkpoint, never
        // as a bubble — nobody's name or face belongs on it.
        guard ChatActionType(groupEvent: message.typeMessage) == nil else { return nil }

        return message.senderId
    }
}
