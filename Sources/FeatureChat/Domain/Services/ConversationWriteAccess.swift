//
//  ConversationWriteAccess.swift
//  FeatureChat
//
//  Who may send into a conversation that is not a plain chat.
//

import Foundation

/// Why a room is read-only for this user.
///
/// Absence of a restriction is not permission to send — Core is the authority,
/// and a group the user has left is handled elsewhere. This only covers the two
/// rooms whose rules live in Identity: a broadcast channel and a community's
/// announcements group.
public enum ConversationWriteRestriction: Equatable, Sendable {
    /// A canal Updates. Only its creator posts.
    case channelOwnerOnly
    /// A community's announcements group. Owners and admins post.
    case announcementsAdminsOnly
}

/// Answers whether the composer should be offered in a given conversation.
public protocol ConversationWriteAccessResolving: Sendable {
    /// - Returns: nil when nothing restricts this conversation, or when it
    ///   cannot be told — a lookup failure must not lock a normal chat.
    func restriction(forConversationId conversationId: String) async -> ConversationWriteRestriction?
}
