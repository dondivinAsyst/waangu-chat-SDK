//
//  ConversationKind.swift
//  FeatureChat
//

import Foundation

/// What a conversation *is*, on the way out.
///
/// Replaces the `isGroup` boolean the send path used to carry. A boolean has two
/// values and there are three kinds, so a broadcast had to travel as
/// `isGroup: true` — and the store, believing it, wrote the row as a group. That
/// is not a bug to patch after the fact in every writer; it is a missing case,
/// and this is the case.
public enum ConversationKind: String, Codable, Sendable, CaseIterable {

    case direct
    case group
    case channel

    /// Addressed to a room rather than to one person: no peer, and the group id
    /// travels with the message.
    public var isMultiParty: Bool {
        self != .direct
    }

    /// What the wire and the group endpoints still call a group.
    ///
    /// A broadcast is one of these on the way out — it is fanned out to
    /// participants, not delivered to a recipient — which is exactly why the
    /// kind has to be kept alongside it rather than collapsed into it.
    public var travelsAsGroup: Bool {
        isMultiParty
    }
}
