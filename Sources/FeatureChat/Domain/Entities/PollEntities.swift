import Foundation
import WaanguCoreKit

// MARK: - Poll Content

/// A poll carried by a message.
///
/// Modelled as a nested struct for the same reason `ChatLocationItem` and
/// `CallContent` are: storage keeps these facts as flat `poll*` columns inside
/// the content blob, and the mappers translate. Nothing above the mapper should
/// have to know that shape.
public struct PollContent: Codable, Equatable, Sendable {
    public var question: String
    public var options: [PollOption]
    /// Always false today. Carried end to end anyway, so enabling multi-choice
    /// later is UI work rather than another pass through every layer.
    public var isMultipleChoice: Bool
    public var isClosed: Bool

    public init(
        question: String,
        options: [PollOption],
        isMultipleChoice: Bool = false,
        isClosed: Bool = false
    ) {
        self.question = question
        self.options = options
        self.isMultipleChoice = isMultipleChoice
        self.isClosed = isClosed
    }

    /// Every vote cast, across all options. Derived rather than stored so it can
    /// never disagree with the options it summarises.
    ///
    /// In a multiple-choice poll this exceeds the number of people who voted —
    /// use `voterCount` for anything phrased as "who".
    public var totalVotes: Int {
        options.reduce(0) { $0 + $1.voterIds.count }
    }

    /// How many distinct people voted.
    ///
    /// This, not `totalVotes`, is what a result bar is a share of: when everyone
    /// picks every option in a multiple-choice poll, every bar should be full,
    /// and dividing by the vote total would draw them all at half.
    public var voterCount: Int {
        Set(options.flatMap(\.voterIds)).count
    }

    /// The options this person currently holds.
    public func selection(of voterId: String) -> [String] {
        options.filter { $0.voterIds.contains(voterId) }.map(\.id)
    }
}

// MARK: - Poll Option

public struct PollOption: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var text: String
    public var voterIds: [String]
    /// Kept in step with `voterIds` by `PollVoteMerger`. Present because the wire
    /// carries it, and because a server may report a count for voters it chose
    /// not to name.
    public var voteCount: Int

    public init(
        id: String = UUID().lowercasedString,
        text: String,
        voterIds: [String] = [],
        voteCount: Int = 0
    ) {
        self.id = id
        self.text = text
        self.voterIds = voterIds
        self.voteCount = voteCount
    }

    public func hasVoted(_ userId: String) -> Bool {
        voterIds.contains(userId)
    }
}
