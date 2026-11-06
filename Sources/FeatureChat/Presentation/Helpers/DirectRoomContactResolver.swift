//
//  DirectRoomContactResolver.swift
//  FeatureChat
//
//  Who a direct chat room opens with.
//

import Foundation

/// Builds the `ContactChannel` a direct chat room opens with, out of every
/// source that might know who the peer is.
///
/// The sources disagree, so precedence is per field and by how close each one
/// sits to the conversation:
/// 1. the stored discussion — written from the conversation itself;
/// 2. the Waangu directory — the current user's own view of this person;
/// 3. the route's `DirectChatPeer` — a contact card someone shared, which may
///    carry *their* name for the person, but is the only source that knows them
///    at all when the number arrived shared rather than saved.
///
/// A field missing from one source falls through to the next, so a discussion
/// row that never learned the peer's `userId` still gets one from the card.
enum DirectRoomContactResolver {

    static func resolve(
        phoneNumber: String,
        listContact: ContactChannel?,
        directoryContact: UserContactProps?,
        peer: DirectChatPeer?
    ) -> ContactChannel {
        let identifiers = [
            listContact?.userId ?? "",
            listContact?.id ?? "",
            directoryContact?.userId ?? "",
            peer?.userId ?? ""
        ]

        return ContactChannel(
            userName: firstNonEmpty(
                PeerDisplayName.sanitized(listContact?.userName, identifiers: identifiers),
                PeerDisplayName.sanitized(directoryContact?.name, identifiers: identifiers),
                PeerDisplayName.sanitized(peer?.name, identifiers: identifiers)
            ) ?? "",
            phone: firstNonEmpty(listContact?.phone, directoryContact?.phone, phoneNumber) ?? "",
            image: firstNonEmpty(listContact?.image, directoryContact?.avatar, peer?.avatar),
            isBlocked: listContact?.isBlocked ?? directoryContact?.isBlocked ?? false,
            isGroup: false,
            id: firstNonEmpty(listContact?.id, directoryContact?.idContact, peer?.idContact) ?? "",
            userId: firstNonEmpty(listContact?.userId, directoryContact?.userId, peer?.userId) ?? ""
        )
    }

    /// The same number written two ways is the same number: a shared card
    /// carries whatever spacing the sender's address book used, the directory
    /// carries the server's form. Comparing the raw strings misses on spacing
    /// alone, which is how a known contact ends up nameless in their own room.
    static func directoryContact(
        for phoneNumber: String,
        in users: [UserContactProps]
    ) -> UserContactProps? {
        let digits = phoneNumber.onlyDigits
        guard !digits.isEmpty else { return nil }
        return users.first { $0.phone.onlyDigits == digits }
    }

    /// A stored one-to-one discussion with this peer, if we already have one.
    static func discussion(
        for phoneNumber: String,
        in discussions: [DiscussionChatItem]
    ) -> DiscussionChatItem? {
        DirectDiscussionFinder.match(phone: phoneNumber, in: discussions)
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        candidates.compactMap { $0 }.first { !$0.isEmpty }
    }
}
