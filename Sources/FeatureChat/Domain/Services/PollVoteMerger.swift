import Foundation

/// The single place a vote is applied to a poll.
///
/// Three callers reach it: the local user tapping an option, the inbound event
/// carrying somebody's full selection, and the inbound event that names only one
/// option. All three funnel into `applySelection`, so a vote is idempotent — the
/// echo of your own vote re-applies it and changes nothing.
enum PollVoteMerger {

    /// The local user tapped `optionId`.
    ///
    /// Tapping an option you already hold retracts it, which is the only way to
    /// unvote. In a single-choice poll picking a different option moves your
    /// vote; in a multiple-choice poll it adds to it.
    static func toggle(optionId: String, voterId: String, in poll: PollContent) -> PollContent {
        guard !voterId.isEmpty,
              poll.options.contains(where: { $0.id == optionId })
        else { return poll }

        var selection = poll.selection(of: voterId)

        if selection.contains(optionId) {
            selection.removeAll { $0 == optionId }
        } else if poll.isMultipleChoice {
            selection.append(optionId)
        } else {
            selection = [optionId]
        }

        return applySelection(selection, voterId: voterId, to: poll)
    }

    /// This voter now holds exactly these options, and nothing else.
    ///
    /// An empty array is meaningful: it is a retraction. Unknown option ids are
    /// dropped rather than honoured, so a peer running a newer poll shape can
    /// never corrupt an older one.
    static func applySelection(
        _ optionIds: [String],
        voterId: String,
        to poll: PollContent
    ) -> PollContent {
        guard !voterId.isEmpty else { return poll }

        let chosen = Set(optionIds.filter { id in poll.options.contains { $0.id == id } })

        var updated = poll
        updated.options = poll.options.map { option in
            var next = option
            if chosen.contains(option.id) {
                if !next.voterIds.contains(voterId) {
                    next.voterIds.append(voterId)
                }
            } else {
                next.voterIds.removeAll { $0 == voterId }
            }
            // Always re-derived: a count off the wire is a claim, not a fact.
            next.voteCount = next.voterIds.count
            return next
        }
        return updated
    }

    /// An inbound event naming a single option.
    ///
    /// What that means depends on the poll: in a multiple-choice poll it adds to
    /// whatever the voter already holds, and in a single-choice one it replaces
    /// it. A delta can never express a retraction — only `applySelection` can —
    /// which is why the client publishes its whole selection.
    static func apply(optionId: String, voterId: String, to poll: PollContent) -> PollContent {
        guard !voterId.isEmpty,
              poll.options.contains(where: { $0.id == optionId })
        else { return poll }

        guard poll.isMultipleChoice else {
            return applySelection([optionId], voterId: voterId, to: poll)
        }

        var selection = poll.selection(of: voterId)
        if !selection.contains(optionId) {
            selection.append(optionId)
        }
        return applySelection(selection, voterId: voterId, to: poll)
    }
}
