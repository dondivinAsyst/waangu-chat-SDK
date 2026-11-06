//
//  CallEntities.swift
//  FeatureChat
//
//  Domain shape of a call log entry.
//
//  Deliberately separate from `CallLogModel`: that is the GRDB row and belongs
//  to Data. `CallMapper` converts between the two so storage concerns never
//  reach the view models.
//

import Foundation

// MARK: - Call log

public struct CallLogEntity: Identifiable, Equatable, Sendable {

    public let id: String
    /// Remote party for a one-to-one call; nil for group calls.
    public let userId: String?
    public let contactId: String?
    /// Required by the signaling contract for a call to appear in server history.
    public let conversationId: String?

    // Denormalised so the calls list renders without a join.
    public let contactName: String
    public let contactPhone: String
    public let contactAvatarURL: String?

    public let media: CallMedia
    public let direction: CallDirection
    public let outcome: CallOutcome
    public let durationSeconds: Int
    public let startedAt: Date
    public let endedAt: Date?

    public let isGroupCall: Bool
    public let groupName: String?
    public let participantCount: Int
    public let initiatedByUserId: String?
    public let participants: [CallLogParticipant]

    public init(
        id: String = UUID().uuidString.lowercased(),
        userId: String? = nil,
        contactId: String? = nil,
        conversationId: String? = nil,
        contactName: String,
        contactPhone: String,
        contactAvatarURL: String? = nil,
        media: CallMedia,
        direction: CallDirection,
        outcome: CallOutcome,
        durationSeconds: Int = 0,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        isGroupCall: Bool = false,
        groupName: String? = nil,
        participantCount: Int = 1,
        initiatedByUserId: String? = nil,
        participants: [CallLogParticipant] = []
    ) {
        self.id = id
        self.userId = userId
        self.contactId = contactId
        self.conversationId = conversationId
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.contactAvatarURL = contactAvatarURL
        self.media = media
        self.direction = direction
        self.outcome = outcome
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isGroupCall = isGroupCall
        self.groupName = groupName
        self.participantCount = participantCount
        self.initiatedByUserId = initiatedByUserId
        self.participants = participants
    }
}

public struct CallLogParticipant: Equatable, Sendable, Identifiable {
    public let userId: String
    public let name: String
    /// What a redial needs. Optional because logs written before this existed
    /// have none, and because a participant may only ever be known by user id.
    public let phone: String?
    public let outcome: CallOutcome

    public var id: String { userId }

    public init(
        userId: String,
        name: String,
        phone: String? = nil,
        outcome: CallOutcome = .answered
    ) {
        self.userId = userId
        self.name = name
        self.phone = phone
        self.outcome = outcome
    }
}

// MARK: - Enums

public enum CallMedia: String, Sendable {
    case voice
    case video
}

public enum CallDirection: String, Sendable {
    case incoming
    case outgoing
}

/// How a call finished. Every call reaches exactly one of these, including the
/// ones that never connected — that is what makes the log complete.
public enum CallOutcome: String, Sendable {
    /// Picked up by the other side.
    case answered
    /// Rang here and nobody picked up.
    case missed
    /// Explicitly rejected by the receiver.
    case declined
    /// Hung up by the caller before it was answered.
    case cancelled
    /// Rang out at the other end without an answer.
    case noAnswer
    /// The other party was already on a call.
    case busy
    /// The call could not be placed at all — the server refused it or a backing
    /// service was down. Distinct from `cancelled`, which is the user changing
    /// their mind, and from `noAnswer`, which means it really did ring.
    case failed

    /// Missed and no-answer both surface in the "Missed" filter and in red.
    ///
    /// A failed call is deliberately not among them: nobody missed anything,
    /// the call never reached the other side.
    public var isMissed: Bool {
        switch self {
        case .missed, .noAnswer: return true
        case .answered, .declined, .cancelled, .busy, .failed: return false
        }
    }

    /// Only an answered call has a meaningful duration.
    public var didConnect: Bool { self == .answered }
}

// MARK: - Query

/// Filter for reading the calls list.
public enum CallLogFilter: Sendable {
    case all
    case missed
}
