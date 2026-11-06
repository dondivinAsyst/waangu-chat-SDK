import XCTest
@testable import WaanguFeatureChat

/// Which roster row an inbound peer belongs to.
///
/// The regression these cover: the match used to be computed from an alias set
/// expanded back through the roster, then applied to any row that intersected
/// it. A peer arriving with a phone number could land on a row belonging to
/// somebody else entirely, and from then on two people shared one row — which
/// is what let a single `CALL_PEER_LEFT` take both of them off the call.
///
/// Matching now reads only the identifiers the event itself carries, and `userId`
/// outranks `phone`: the id is the authoritative identity, the phone is
/// supporting data that the server may attach loosely.
final class CallRosterMergeTests: XCTestCase {

    private func key(_ id: String) -> String {
        VoipManager.normalizedPeerKey(id)
    }

    func test_matchesTheRowCarryingThatUserId() {
        let roster = [
            CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111"),
            CallInvitee(userId: "uuid-b", name: "Bob", phone: "+33222")
        ]

        XCTAssertEqual(
            VoipManager.rosterMatch(userIdKey: key("uuid-b"), phoneKey: "", in: roster),
            1
        )
    }

    /// A row seeded from an invite may only know a phone number. The uuid shows
    /// up later, and must find that row rather than starting a second one.
    func test_matchesByPhoneWhenNoRowCarriesTheUserId() {
        let roster = [CallInvitee(userId: "+33111", name: "Ada", phone: "+33111")]

        XCTAssertEqual(
            VoipManager.rosterMatch(userIdKey: key("uuid-a"), phoneKey: key("+33111"), in: roster),
            0
        )
    }

    /// The regression, stated directly: a phone that happens to sit on another
    /// person's row must never outrank the peer's own id. Bob is first in the
    /// roster and carries the incoming phone — Ada must still resolve to Ada.
    func test_userIdOutranksAPhoneSittingOnSomebodyElsesRow() {
        let roster = [
            CallInvitee(userId: "uuid-b", name: "Bob", phone: "+33222"),
            CallInvitee(userId: "uuid-a", name: "Ada", phone: "uuid-a")
        ]

        XCTAssertEqual(
            VoipManager.rosterMatch(userIdKey: key("uuid-a"), phoneKey: key("+33222"), in: roster),
            1
        )
    }

    /// Two rows, two people, and an event naming neither of their ids. Guessing
    /// here is what corrupted the roster, so the answer is "no row".
    func test_unknownPeerMatchesNoRow() {
        let roster = [
            CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111"),
            CallInvitee(userId: "uuid-b", name: "Bob", phone: "+33222")
        ]

        XCTAssertNil(
            VoipManager.rosterMatch(userIdKey: key("uuid-ghost"), phoneKey: "", in: roster)
        )
    }

    func test_emptyIdentifiersMatchNoRow() {
        let roster = [CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111")]

        XCTAssertNil(VoipManager.rosterMatch(userIdKey: "", phoneKey: "", in: roster))
    }

    // MARK: - No duplicate tiles

    /// Two rows for one person can exist before anything links them: a row
    /// seeded from an invite that only knew a phone, and a row created when the
    /// producer arrived naming a uuid. Nothing has yet said they are the same
    /// person, so they legitimately do not collapse.
    func test_unlinkedRowsAreNotAssumedToBeTheSamePerson() {
        let seeded = CallInvitee(userId: "+33111", name: "+33111", phone: "+33111")
        let byUuid = CallInvitee(userId: "uuid-a", name: "uuid-a", phone: "uuid-a")

        XCTAssertFalse(VoipManager.rowsShareIdentity(seeded, byUuid))
    }

    /// The event that carries both identifiers is what links them — and it must
    /// land on the uuid row, so the phone is absorbed there rather than starting
    /// a third row.
    func test_linkingEventResolvesToTheUuidRow() {
        let roster = [
            CallInvitee(userId: "+33111", name: "+33111", phone: "+33111"),
            CallInvitee(userId: "uuid-a", name: "uuid-a", phone: "uuid-a")
        ]

        XCTAssertEqual(
            VoipManager.rosterMatch(userIdKey: key("uuid-a"), phoneKey: key("+33111"), in: roster),
            1
        )
    }

    /// Once the phone has been absorbed the two rows overlap, and the grid
    /// collapses them into a single tile.
    func test_rowsCollapseOnceTheyShareAnIdentifier() {
        let seeded = CallInvitee(userId: "+33111", name: "+33111", phone: "+33111")
        let linked = CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111")

        XCTAssertTrue(VoipManager.rowsShareIdentity(seeded, linked))
    }

    /// Two different people never collapse, however their rows are filled in.
    func test_differentPeopleNeverShareIdentity() {
        let ada = CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111")
        let bob = CallInvitee(userId: "uuid-b", name: "Bob", phone: "+33222")

        XCTAssertFalse(VoipManager.rowsShareIdentity(ada, bob))
    }

    /// A blank phone is an absent value, not a shared one — two rows that both
    /// lack a phone must not collapse on that basis.
    func test_blankFieldsDoNotMakeRowsMatch() {
        let ada = CallInvitee(userId: "uuid-a", name: "Ada", phone: "")
        let bob = CallInvitee(userId: "uuid-b", name: "Bob", phone: "")

        XCTAssertFalse(VoipManager.rowsShareIdentity(ada, bob))
    }

    /// An empty phone field on a row is not an identity — two rows that both
    /// lack a phone are not therefore the same person.
    func test_blankPhoneOnARowIsNotAnIdentity() {
        let roster = [CallInvitee(userId: "uuid-a", name: "Ada", phone: "")]

        XCTAssertNil(
            VoipManager.rosterMatch(userIdKey: key("uuid-b"), phoneKey: "", in: roster)
        )
    }
}
