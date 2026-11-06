//
//  ChannelPostViews.swift
//  FeatureChat
//
//  How many people have seen a broadcast post.
//

import Foundation

/// Counts, per post, how many followers have opened it.
///
/// A broadcast has no delivery ticks worth showing — there is no single peer to
/// tick — but it does have readers, and a read receipt is exactly one reader
/// having seen one post. That is what the number on a channel card means.
///
/// It reflects what this device has been told: receipts arrive with the sync,
/// so a fresh post reads zero until they do.
public protocol ChannelPostViewCounting: Sendable {
    /// Views for every post in a conversation, keyed by `codeMessage`.
    func viewCounts(conversationId: String) async -> [String: Int]
}
