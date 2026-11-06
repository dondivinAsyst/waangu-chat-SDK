import XCTest
@testable import WaanguFeatureChat

/// A voter holds at most one option. Every rule here exists because both the
/// optimistic local write and the inbound server echo run through this same
/// function, and the two must never disagree about who voted for what.
final class PollVoteMergerTests: XCTestCase {

    private func poll() -> PollContent {
        PollContent(
            question: "Lunch?",
            options: [
                PollOption(id: "a", text: "Pizza"),
                PollOption(id: "b", text: "Sushi")
            ]
        )
    }

    func test_firstVoteAddsVoterAndCount() {
        let merged = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: poll())

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
        XCTAssertEqual(merged.options[0].voteCount, 1)
        XCTAssertEqual(merged.options[1].voteCount, 0)
    }

    func test_switchingVoteRemovesTheOldOne() {
        var merged = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: poll())
        merged = PollVoteMerger.apply(optionId: "b", voterId: "u1", to: merged)

        XCTAssertEqual(merged.options[0].voterIds, [])
        XCTAssertEqual(merged.options[0].voteCount, 0)
        XCTAssertEqual(merged.options[1].voterIds, ["u1"])
        XCTAssertEqual(merged.options[1].voteCount, 1)
    }

    func test_repeatedVoteForTheSameOptionIsIdempotent() {
        var merged = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: poll())
        merged = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: merged)

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
        XCTAssertEqual(merged.options[0].voteCount, 1)
    }

    func test_unknownOptionIdLeavesThePollUntouched() {
        let original = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: poll())
        let merged = PollVoteMerger.apply(optionId: "zzz", voterId: "u2", to: original)

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
        XCTAssertEqual(merged.options[1].voterIds, [])
    }

    func test_emptyVoterIdIsIgnored() {
        let merged = PollVoteMerger.apply(optionId: "a", voterId: "", to: poll())

        XCTAssertEqual(merged.options[0].voterIds, [])
        XCTAssertEqual(merged.options[0].voteCount, 0)
    }

    /// A count that disagrees with the voters it summarises is a claim, not a
    /// fact — the merge re-derives it rather than carrying the contradiction.
    func test_voteCountAlwaysMatchesVoterIds() {
        var seeded = poll()
        seeded.options[0].voteCount = 99
        let merged = PollVoteMerger.apply(optionId: "b", voterId: "u1", to: seeded)

        XCTAssertEqual(merged.options[0].voteCount, merged.options[0].voterIds.count)
        XCTAssertEqual(merged.options[1].voteCount, 1)
    }

    func test_votesFromDifferentUsersAccumulate() {
        var merged = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: poll())
        merged = PollVoteMerger.apply(optionId: "a", voterId: "u2", to: merged)

        XCTAssertEqual(merged.options[0].voterIds, ["u1", "u2"])
        XCTAssertEqual(merged.options[0].voteCount, 2)
    }

    func test_totalVotesSumsEveryOption() {
        var merged = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: poll())
        merged = PollVoteMerger.apply(optionId: "b", voterId: "u2", to: merged)

        XCTAssertEqual(merged.totalVotes, 2)
    }

    // MARK: - Toggle (the local tap)

    func test_tappingAnUnheldOptionVotesForIt() {
        let merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: poll())

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
    }

    /// The only way to unvote: tap what you already hold.
    func test_tappingAHeldOptionRetractsTheVote() {
        var merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: poll())
        merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: merged)

        XCTAssertEqual(merged.options[0].voterIds, [])
        XCTAssertEqual(merged.options[0].voteCount, 0)
        XCTAssertEqual(merged.totalVotes, 0)
    }

    func test_singleChoiceTapMovesTheVote() {
        var merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: poll())
        merged = PollVoteMerger.toggle(optionId: "b", voterId: "u1", in: merged)

        XCTAssertEqual(merged.options[0].voterIds, [])
        XCTAssertEqual(merged.options[1].voterIds, ["u1"])
    }

    func test_multipleChoiceTapAccumulates() {
        var merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: multiPoll())
        merged = PollVoteMerger.toggle(optionId: "b", voterId: "u1", in: merged)

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
        XCTAssertEqual(merged.options[1].voterIds, ["u1"])
        XCTAssertEqual(merged.totalVotes, 2)
        XCTAssertEqual(merged.voterCount, 1)
    }

    func test_multipleChoiceRetractsOneWithoutTouchingTheOther() {
        var merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: multiPoll())
        merged = PollVoteMerger.toggle(optionId: "b", voterId: "u1", in: merged)
        merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: merged)

        XCTAssertEqual(merged.options[0].voterIds, [])
        XCTAssertEqual(merged.options[1].voterIds, ["u1"])
    }

    // MARK: - Selection (the authoritative echo)

    func test_selectionReplacesWhateverWasHeld() {
        var merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: multiPoll())
        merged = PollVoteMerger.applySelection(["b"], voterId: "u1", to: merged)

        XCTAssertEqual(merged.options[0].voterIds, [])
        XCTAssertEqual(merged.options[1].voterIds, ["u1"])
    }

    func test_emptySelectionIsARetraction() {
        var merged = PollVoteMerger.toggle(optionId: "a", voterId: "u1", in: poll())
        merged = PollVoteMerger.applySelection([], voterId: "u1", to: merged)

        XCTAssertEqual(merged.totalVotes, 0)
    }

    func test_selectionDropsUnknownOptionIds() {
        let merged = PollVoteMerger.applySelection(["a", "zzz"], voterId: "u1", to: poll())

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
        XCTAssertEqual(merged.totalVotes, 1)
    }

    func test_selectionLeavesOtherVotersAlone() {
        var merged = PollVoteMerger.applySelection(["a"], voterId: "u1", to: poll())
        merged = PollVoteMerger.applySelection(["b"], voterId: "u2", to: merged)

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
        XCTAssertEqual(merged.options[1].voterIds, ["u2"])
    }

    // MARK: - Inbound delta under multiple choice

    func test_deltaAddsRatherThanReplacesWhenMultipleChoice() {
        var merged = PollVoteMerger.apply(optionId: "a", voterId: "u1", to: multiPoll())
        merged = PollVoteMerger.apply(optionId: "b", voterId: "u1", to: merged)

        XCTAssertEqual(merged.options[0].voterIds, ["u1"])
        XCTAssertEqual(merged.options[1].voterIds, ["u1"])
    }

    // MARK: - Bar denominator

    /// Everyone picking everything must draw every bar full, which only works
    /// when the share is taken against voters rather than votes.
    func test_voterCountCountsPeopleNotVotes() {
        var merged = multiPoll()
        for voter in ["u1", "u2", "u3"] {
            merged = PollVoteMerger.applySelection(["a", "b"], voterId: voter, to: merged)
        }

        XCTAssertEqual(merged.totalVotes, 6)
        XCTAssertEqual(merged.voterCount, 3)
        XCTAssertEqual(merged.options[0].voterIds.count, merged.voterCount)
    }

    func test_selectionOfReportsWhatAVoterHolds() {
        var merged = PollVoteMerger.applySelection(["a", "b"], voterId: "u1", to: multiPoll())
        merged = PollVoteMerger.applySelection(["b"], voterId: "u2", to: merged)

        XCTAssertEqual(merged.selection(of: "u1"), ["a", "b"])
        XCTAssertEqual(merged.selection(of: "u2"), ["b"])
        XCTAssertEqual(merged.selection(of: "nobody"), [])
    }

    private func multiPoll() -> PollContent {
        PollContent(
            question: "Which languages?",
            options: [
                PollOption(id: "a", text: "Js"),
                PollOption(id: "b", text: "Java")
            ],
            isMultipleChoice: true
        )
    }
}
