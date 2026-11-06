import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: Outbound — vote
// ─────────────────────────────────────────────────────────────

/// Published to `waangu-chat/vote-poll`.
///
/// Carries the voter's **whole selection** rather than the option they just
/// tapped. One operation then covers all three cases: a single-choice vote, a
/// multiple-choice set, and a retraction — which is an empty array. Naming a
/// lone option could express none of the last two, and would have needed a
/// separate unvote topic the contract does not define.
///
/// `selectedOptions` holds option ids, the same ids sent in `pollOptions` when
/// the poll was created.
public struct OutboundVotePollDTO: Codable, Sendable, Equatable {
    public let codeMessage: String
    public let conversationId: String
    public let userId: String
    public let selectedOptions: [String]
    public let tenantId: String?
    public let country: String?

    public init(
        codeMessage: String,
        conversationId: String,
        userId: String,
        selectedOptions: [String],
        tenantId: String?,
        country: String?
    ) {
        self.codeMessage = codeMessage
        self.conversationId = conversationId
        self.userId = userId
        self.selectedOptions = selectedOptions
        self.tenantId = tenantId
        self.country = country
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Inbound — vote echo
// ─────────────────────────────────────────────────────────────

/// A vote fanned back out to the room.
///
/// Two shapes are accepted because the contract does not say which is sent: an
/// authoritative one carrying the whole `pollOptions` array, and a delta naming
/// only the voter and their option. Every id is optional and read through an
/// accessor, since the message id alone arrives under three different names
/// across the payloads already in use.
public struct InboundPollVoteDTO: Codable, Sendable {
    public let codeMessage: String?
    public let messageId: String?
    public let id: String?
    public let userId: String?
    public let senderId: String?
    public let optionId: String?
    /// The voter's whole selection, when the server echoes it back that way.
    /// Distinguishable from an absent field, which is what makes a retraction
    /// (`[]`) readable at all.
    public let optionIds: [String]?
    /// The same selection under the name the client itself sends it out with
    /// (`OutboundVotePollDTO.selectedOptions`) — the server echoes that name
    /// back, so an inbound vote carrying only this field must still be read.
    public let selectedOptions: [String]?
    public let pollOptions: [PollOptionDTO]?

    public var resolvedCodeMessage: String {
        (codeMessage ?? messageId ?? id ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resolvedVoterId: String {
        (userId ?? senderId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resolvedOptionId: String {
        (optionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The selection the server reports, or nil when it sent only a single
    /// option — nil and `[]` mean different things here, so they must not be
    /// collapsed: one is "no selection field", the other is "voted for nothing".
    public var resolvedSelection: [String]? {
        (optionIds ?? selectedOptions)?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
