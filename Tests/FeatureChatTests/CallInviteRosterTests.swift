import XCTest
@testable import WaanguFeatureChat

/// Who the mid-call invite picker is allowed to offer.
///
/// The regression these cover: the exclusion set was built from
/// `invitedParticipants`, which is append-only for the life of a call because it
/// is what the call log records. Anyone who declined, was busy, or hung up
/// stayed in it forever — so they could never be invited back (the picker hid
/// them, and `invitePeers` silently dropped them even if it had not), and they
/// kept occupying a seat against the 32-peer room limit.
///
/// It now reads `remoteParticipants`, the roster that actually shrinks when
/// somebody leaves.
final class CallInviteRosterTests: XCTestCase {

    private let ada = CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33 11 11 11")
    private let bob = CallInvitee(userId: "uuid-b", name: "Bob", phone: "+33222")

    func test_excludesEveryoneCurrentlyOnTheCall() {
        XCTAssertEqual(
            VoipManager.invitablePhones(excluding: [ada, bob]),
            ["33111111", "33222"]
        )
    }

    /// The whole point: once the roster drops them, they are invitable again.
    func test_peerWhoLeftIsNoLongerExcluded() {
        let afterBobLeaves = VoipManager.invitablePhones(excluding: [ada])

        XCTAssertFalse(afterBobLeaves.contains("33222"))
        XCTAssertTrue(afterBobLeaves.contains("33111111"))
    }

    func test_emptyRosterExcludesNobody() {
        XCTAssertTrue(VoipManager.invitablePhones(excluding: []).isEmpty)
    }

    /// Phones arrive formatted in all sorts of ways; the picker compares digits.
    func test_normalisesFormattingToDigits() {
        let spaced = CallInvitee(userId: "uuid-c", name: "Cy", phone: "+33 (2) 22")

        XCTAssertEqual(
            VoipManager.invitablePhones(excluding: [spaced]),
            ["33222"]
        )
    }

    /// A peer known only by uuid has no usable phone. An empty entry would match
    /// every contact whose phone normalises to nothing and hide them all.
    func test_ignoresPeersWithNoPhone() {
        let anonymous = CallInvitee(userId: "uuid-d", name: "Dee", phone: "")

        XCTAssertTrue(VoipManager.invitablePhones(excluding: [anonymous]).isEmpty)
    }
}
