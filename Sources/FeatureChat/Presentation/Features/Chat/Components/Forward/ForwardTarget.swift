//
//  ForwardTarget.swift
//  FeatureChat
//

import Foundation

/// One selectable destination in the forward picker.
///
/// The picker used to hold a `Set<String>` mixing conversation ids with contact
/// ids, then re-derive "is this a group?" by comparing a display string to
/// `"Group chat"`. A target carries its own namespaced identity, its own
/// group flag and its own resolved recipient, so the send path never has to
/// guess any of the three.
struct ForwardTarget: Identifiable, Equatable {

    enum Kind: Equatable {
        /// A conversation that already exists — direct or group.
        case discussion(conversationId: String, isGroup: Bool)
        /// A contact with no conversation yet. Carries the conversation id the
        /// first message will open, minted client-side the same way starting a
        /// chat from the contact list does — a contact id is not a conversation
        /// id, and reusing one as the other is what this type exists to stop.
        case contact(contactId: String, conversationId: String)
        /// The current user's own status. Carries no recipient.
        case myStatus
    }

    let kind: Kind
    let name: String
    let avatar: String?
    /// Shown under the name when nothing better is known — a group's member list
    /// is loaded separately and takes precedence, see `ForwardMessagePickerViewModel`.
    let fallbackSubtitle: String
    let isBlocked: Bool
    /// Who the message is addressed to. Nil for `.myStatus`.
    let receiver: UserRoom?

    /// Namespaced so a conversation id and a contact id that happen to be equal
    /// stay two different rows.
    var id: String {
        switch kind {
        case .discussion(let conversationId, _): return "discussion:\(conversationId)"
        case .contact(let contactId, _):         return "contact:\(contactId)"
        case .myStatus:                          return "status"
        }
    }

    var isGroup: Bool {
        if case .discussion(_, let isGroup) = kind { return isGroup }
        return false
    }

    var isStatus: Bool { kind == .myStatus }

    /// The conversation the forwarded messages are written into. Nil for `.myStatus`.
    var conversationId: String? {
        switch kind {
        case .discussion(let conversationId, _): return conversationId
        case .contact(_, let conversationId):    return conversationId
        case .myStatus:                          return nil
        }
    }

    /// Whether this row can accept a send at all — blocked contacts cannot.
    var isSelectable: Bool {
        if isStatus { return true }
        return !isBlocked && receiver != nil
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(query) { return true }
        if let phone = receiver?.phone, phone.contains(query) { return true }
        return false
    }
}
