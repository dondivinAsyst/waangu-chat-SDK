import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class SplitBillSharingTests: XCTestCase {

    private func money(_ minor: Int64) -> Money {
        Money(minorUnits: minor, currency: CurrencyCode(code: "BIF", exponent: 0))
    }

    private func participant(
        _ id: String, share: Int64 = 1_000, contributed: Int64 = 0,
        consent: SplitParticipantConsent = .pending, excluded: Bool = false
    ) -> SplitParticipant {
        SplitParticipant(userID: id, displayName: id.uppercased(), share: money(share),
                         contributed: money(contributed), consent: consent, isExcluded: excluded)
    }

    private func split(privacy: SplitPrivacyScope, participants: [SplitParticipant]) -> SplitBill {
        SplitBill(
            id: "split-1", labelKey: "Dinner", organizerID: "org",
            total: money(3_000), collected: money(1_000), participants: participants,
            strategy: .equal, state: .partiallySettled, privacyScope: privacy,
            reminderPolicy: SplitReminderPolicy(maxPerParticipant: 3, minimumInterval: 3_600),
            createdAt: Date(), updatedAt: Date()
        )
    }

    // MARK: - Progress

    func test_progressFollowsServerAmountsThenConsent() {
        XCTAssertEqual(SplitParticipantProgress(participant("a", contributed: 1_000, consent: .accepted)), .paid)
        XCTAssertEqual(SplitParticipantProgress(participant("b", contributed: 400, consent: .accepted)), .awaitingPayment)
        XCTAssertEqual(SplitParticipantProgress(participant("c", consent: .pending)), .awaitingApproval)
        XCTAssertEqual(SplitParticipantProgress(participant("d", consent: .declined)), .declined)
        XCTAssertEqual(SplitParticipantProgress(participant("e", consent: .expired)), .expired)
        XCTAssertEqual(SplitParticipantProgress(participant("f", consent: .accepted, excluded: true)), .excluded)
        XCTAssertEqual(SplitParticipantProgress(participant("g", consent: .unknown)), .unknown)
    }

    // MARK: - Privacy

    func test_openToAll_everyoneSeesEveryone() {
        let snapshot = SplitBillCardSnapshot(
            split: split(privacy: .openToAll, participants: [participant("me"), participant("other")]),
            viewerID: "me")
        XCTAssertEqual(snapshot.rows.map(\.id), ["me", "other"])
        XCTAssertFalse(snapshot.hidesOthers)
        XCTAssertNotNil(snapshot.collected)
    }

    func test_ownShareOnly_participantSeesOnlyTheirRowAndNoAggregate() {
        let snapshot = SplitBillCardSnapshot(
            split: split(privacy: .ownShareOnly, participants: [participant("me"), participant("other")]),
            viewerID: "me")
        XCTAssertEqual(snapshot.rows.map(\.id), ["me"])
        XCTAssertTrue(snapshot.rows.first?.isViewer == true)
        XCTAssertTrue(snapshot.hidesOthers)
        XCTAssertNil(snapshot.collected)
    }

    func test_aggregateOnly_participantSeesProgressButNotOthers() {
        let snapshot = SplitBillCardSnapshot(
            split: split(privacy: .aggregateOnly, participants: [participant("me"), participant("other")]),
            viewerID: "me")
        XCTAssertEqual(snapshot.rows.map(\.id), ["me"])
        XCTAssertNotNil(snapshot.collected)
    }

    func test_organizerAlwaysSeesEveryone() {
        let snapshot = SplitBillCardSnapshot(
            split: split(privacy: .ownShareOnly, participants: [participant("a"), participant("b")]),
            viewerID: "org")
        XCTAssertEqual(snapshot.rows.map(\.id), ["a", "b"])
        XCTAssertFalse(snapshot.hidesOthers)
    }

    // MARK: - Fan-out

    func test_sharePostsIntoEachParticipantsOwnConversation_andSurvivesAFailure() async {
        let discussions = FakeDiscussionUseCases()
        discussions.list.items = [MessagingFixtures.directDiscussion(conversationId: "with-a", phone: "79 00 00 01")]
        let publisher = FakePublishFinanceMessage()
        publisher.failingReceivers = ["b"]
        let sharing = ShareSplitBillUseCase(
            contacts: FakeContactsUseCases(),
            discussions: discussions,
            publisher: publisher,
            currentUserId: { "org" },
            makeConversationId: { "new-conv" }
        )

        let report = await sharing.share(
            split(privacy: .openToAll, participants: []),
            correlationID: CorrelationId(value: "corr"),
            with: [
                MessagingFixtures.contact(userId: "a", phone: "79000001"),
                MessagingFixtures.contact(userId: "b", phone: "79000002"),
                MessagingFixtures.contact(userId: "c", phone: "79000003"),
            ]
        )

        XCTAssertEqual(report.sharedWith, ["a", "c"])
        XCTAssertEqual(report.failed, ["b"])
        XCTAssertFalse(report.isComplete)
        // `a` reuses the existing conversation; `c` starts a new one. `b` failed.
        XCTAssertEqual(publisher.targets.map(\.conversationId), ["with-a", "new-conv"])
        XCTAssertEqual(publisher.targets.map(\.receiverUserId), ["a", "c"])
        XCTAssertTrue(publisher.targets.allSatisfy { $0.kind == .direct })
    }

    // MARK: - Lookup

    func test_lookupIgnoresGroupsAndSpacing() {
        var group = MessagingFixtures.directDiscussion(conversationId: "group", phone: "79000001")
        group.contact?.isGroup = true
        let direct = MessagingFixtures.directDiscussion(conversationId: "direct", phone: "+257 79 00 00 01")

        XCTAssertEqual(DirectDiscussionFinder.match(phone: "25779000001", in: [group, direct])?.conversationId, "direct")
        XCTAssertNil(DirectDiscussionFinder.match(phone: "", in: [direct]))
    }
}

// MARK: - Strategy input

final class SplitStrategyInputTests: XCTestCase {

    func test_equalNeedsNoPerPersonValue() {
        XCTAssertEqual(SplitStrategyInput().strategy(for: ["a", "b"]), .equal)
    }

    func test_customBuildsAmountsForEveryChosenParticipant_acceptingACommaDecimal() {
        let input = SplitStrategyInput(kind: .custom, values: ["a": "12,5", "b": "30"])
        XCTAssertEqual(input.strategy(for: ["a", "b"]), .custom(["a": Decimal(string: "12.5")!, "b": 30]))
    }

    func test_proportionalBuildsWeights() {
        let input = SplitStrategyInput(kind: .proportional, values: ["a": "2", "b": "1"])
        XCTAssertEqual(input.strategy(for: ["a", "b"]), .proportional(["a": 2, "b": 1]))
    }

    /// A missing, empty, zero or unreadable value is not a strategy yet — the
    /// review button stays disabled rather than submitting a partial split.
    func test_incompleteOrInvalidValuesFormNoStrategy() {
        XCTAssertNil(SplitStrategyInput(kind: .custom, values: ["a": "10"]).strategy(for: ["a", "b"]))
        XCTAssertNil(SplitStrategyInput(kind: .custom, values: ["a": "10", "b": ""]).strategy(for: ["a", "b"]))
        XCTAssertNil(SplitStrategyInput(kind: .proportional, values: ["a": "0", "b": "1"]).strategy(for: ["a", "b"]))
        XCTAssertNil(SplitStrategyInput(kind: .custom, values: [:]).strategy(for: []))
    }

    /// A value typed for someone later removed must not travel in the request.
    func test_valuesOfRemovedParticipantsAreIgnored() {
        let input = SplitStrategyInput(kind: .custom, values: ["a": "10", "gone": "99"])
        XCTAssertEqual(input.strategy(for: ["a"]), .custom(["a": 10]))
        XCTAssertEqual(input.customSum(for: ["a"]), 10)
    }

    func test_customSumOnlyForCustomAmounts() {
        XCTAssertEqual(SplitStrategyInput(kind: .custom, values: ["a": "10", "b": "5,5"]).customSum(for: ["a", "b"]),
                       Decimal(string: "15.5"))
        XCTAssertNil(SplitStrategyInput(kind: .proportional, values: ["a": "2"]).customSum(for: ["a"]))
    }

    /// The draft the form produces must pass the contract's own validation.
    func test_customStrategyFromInputIsSubmittable() throws {
        let strategy = try XCTUnwrap(
            SplitStrategyInput(kind: .custom, values: ["a": "20000", "b": "30000"]).strategy(for: ["a", "b"]))
        let draft = SplitBillDraft(
            labelKey: "Dinner",
            total: Money(minorUnits: 50_000, currency: CurrencyCode(code: "BIF", exponent: 0)),
            participantIDs: ["a", "b"], strategy: strategy, privacyScope: .ownShareOnly)
        XCTAssertTrue(draft.isSubmittable)
    }
}

// MARK: - Contacts fake

private struct FakeContactsUseCases: ContactsUseCasesProtocol, GetContactsUseCaseProtocol,
    GetContactsIncrementalUseCaseProtocol, GetPersistedContactsUseCaseProtocol,
    GetDeviceContactsUseCaseProtocol, IsContactPersistedUseCaseProtocol, ToggleBlockContactUseCaseProtocol {
    var getUpdatedContacts: GetContactsUseCaseProtocol { self }
    var getUpdatedContactsIncremental: GetContactsIncrementalUseCaseProtocol { self }
    var getDeviceContacts: GetDeviceContactsUseCaseProtocol { self }
    var getPersistedContacts: GetPersistedContactsUseCaseProtocol { self }
    var isContactPersisted: IsContactPersistedUseCaseProtocol { self }
    var toggleBlockContact: ToggleBlockContactUseCaseProtocol { self }

    func execute() async throws -> (waanguContacts: [WaanguContact], UserContactProps: [UserContactProps])? { nil }
    func execute() async throws -> [UserContactProps]? { nil }
    func execute(phone: String) async throws -> Bool { false }
    func execute(contactId: String, blocked: Bool) async throws -> Bool { false }
}
