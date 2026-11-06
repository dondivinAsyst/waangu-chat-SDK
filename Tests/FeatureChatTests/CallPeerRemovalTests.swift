import XCTest
@testable import WaanguFeatureChat

/// What happens to media when somebody leaves a group call.
///
/// The regression these cover: removal used to be driven by an alias set
/// expanded out of the roster, then applied blindly to the peer→track index by
/// key. Anything sharing a key with that widened set went with it — so a peer
/// who was still talking lost their tile, and a peer who stopped sharing their
/// screen lost their camera too.
///
/// `CALL_PEER_LEFT` and `CALL_NEW_PRODUCER` are read through the same `peerId`
/// accessor, and `consumerOwners` is keyed by that same normalised id, so the
/// media side never needs to guess: it is an exact match.
final class CallPeerRemovalTests: XCTestCase {

    private func key(_ id: String) -> String {
        VoipManager.normalizedPeerKey(id)
    }

    // MARK: - Consumer ownership is exact

    func test_leavingPeerDropsOnlyItsOwnConsumer() {
        let owners = [
            "consumer-a": key("uuid-a"),
            "consumer-b": key("uuid-b")
        ]

        XCTAssertEqual(
            VoipManager.consumersOwned(by: key("uuid-a"), in: owners),
            ["consumer-a"]
        )
    }

    /// A peer sharing their screen owns two consumers. Both are theirs, and both
    /// go when they leave — but neither may take a different peer's with them.
    func test_leavingPeerDropsBothOfItsConsumers() {
        let owners = [
            "camera": key("uuid-a"),
            "screen": key("uuid-a"),
            "consumer-b": key("uuid-b")
        ]

        XCTAssertEqual(
            VoipManager.consumersOwned(by: key("uuid-a"), in: owners),
            ["camera", "screen"]
        )
    }

    func test_unknownPeerDropsNothing() {
        let owners = ["consumer-a": key("uuid-a")]

        XCTAssertTrue(
            VoipManager.consumersOwned(by: key("uuid-ghost"), in: owners).isEmpty
        )
    }

    // MARK: - Roster rows match by alias, one person only

    /// The roster may be seeded by phone while the SFU names the peer by uuid.
    /// A row carrying both is the only thing that links them, so matching reads
    /// that row directly — it never re-expands through other rows.
    func test_rowIsMatchedByEitherOfItsAliases() {
        let roster = [
            CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111"),
            CallInvitee(userId: "uuid-b", name: "Bob", phone: "+33222")
        ]

        XCTAssertEqual(VoipManager.rosterIndices(matching: key("uuid-a"), in: roster), [0])
        XCTAssertEqual(VoipManager.rosterIndices(matching: key("+33111"), in: roster), [0])
        XCTAssertEqual(VoipManager.rosterIndices(matching: key("+33222"), in: roster), [1])
    }

    /// Seed + upsert can leave two rows for one person. Both of *that person's*
    /// rows go; nobody else's does.
    func test_clonedRowsOfOnePersonGoTogether() {
        let roster = [
            CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111"),
            CallInvitee(userId: "uuid-b", name: "Bob", phone: "+33222"),
            CallInvitee(userId: "uuid-a", name: "uuid-a", phone: "uuid-a")
        ]

        XCTAssertEqual(VoipManager.rosterIndices(matching: key("uuid-a"), in: roster), [0, 2])
    }

    func test_leavingPeerNotOnTheRosterRemovesNoRow() {
        let roster = [CallInvitee(userId: "uuid-a", name: "Ada", phone: "+33111")]

        XCTAssertTrue(
            VoipManager.rosterIndices(matching: key("uuid-ghost"), in: roster).isEmpty
        )
    }

    // MARK: - The tile index is rebuilt, never blind-deleted

    /// The reported bug, at the level it actually happens: the peer→track index
    /// is rebuilt from the consumers that are still open, so a slot disappears
    /// only when nothing is left feeding it.
    func test_rebuiltIndexKeepsRemainingPeersTrack() {
        let owners = ["consumer-b": key("uuid-b")]
        let tracks = ["consumer-b": "track-b"]

        let index = VoipManager.rebuiltTrackIndex(
            consumerOwners: owners,
            tracks: tracks,
            aliases: { [$0] }
        )

        XCTAssertEqual(index, [key("uuid-b"): "track-b"])
    }

    /// Stopping a screen share closes one consumer. The camera consumer of the
    /// same peer is still open, so that peer keeps their tile.
    func test_closingOneConsumerKeepsTheSamePeersOtherTrack() {
        let owners = ["camera": key("uuid-a")]
        let tracks = ["camera": "track-camera"]

        let index = VoipManager.rebuiltTrackIndex(
            consumerOwners: owners,
            tracks: tracks,
            aliases: { [$0] }
        )

        XCTAssertEqual(index, [key("uuid-a"): "track-camera"])
    }

    /// A track is indexed under every alias of its owner so the grid can look it
    /// up by uuid or by phone.
    func test_trackIsIndexedUnderEveryAliasOfItsOwner() {
        let owners = ["camera": key("uuid-a")]
        let tracks = ["camera": "track-camera"]

        let index = VoipManager.rebuiltTrackIndex(
            consumerOwners: owners,
            tracks: tracks,
            aliases: { _ in [self.key("uuid-a"), self.key("+33111")] }
        )

        XCTAssertEqual(
            index,
            [key("uuid-a"): "track-camera", key("+33111"): "track-camera"]
        )
    }

    /// An owner whose consumer has no track yet contributes no slot — a stale
    /// entry here is what freezes a dead frame on a tile.
    func test_consumerWithoutATrackContributesNoSlot() {
        let owners = ["camera": key("uuid-a"), "pending": key("uuid-b")]
        let tracks = ["camera": "track-camera"]

        let index = VoipManager.rebuiltTrackIndex(
            consumerOwners: owners,
            tracks: tracks,
            aliases: { [$0] }
        )

        XCTAssertEqual(index, [key("uuid-a"): "track-camera"])
    }
}
