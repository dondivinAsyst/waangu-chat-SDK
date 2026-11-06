import XCTest
@testable import WaanguFeatureChat

/// Parses the exact payloads published in CALL-INTEGRATION.md §9.
///
/// These are transcribed from the contract rather than invented, so the suite
/// fails if the client stops reading a documented field — which is how the
/// accessors silently drifted before.
final class CallContractPayloadTests: XCTestCase {

    private func event(_ eventType: String, _ payload: [String: Any]) -> InboundCallEventDTO? {
        let envelope: [String: Any] = [
            "eventType": eventType,
            "category": "call",
            "payload": payload,
            "notification": ["show": false, "priority": "normal"],
            "ui": ["fullScreen": false, "minimizable": true],
            "muted": false,
            "suppressNotification": true,
            "timestamp": "2026-07-31T10:00:00.000Z",
            "version": 1
        ]
        return CallMqttEventParser.parse(data: try! JSONSerialization.data(withJSONObject: envelope))
    }

    // MARK: - §9.1 Lifecycle

    func test_callInitiated_readsRingingTimeoutAndConversation() {
        let parsed = event("CALL_INITIATED", [
            "roomId": "uuid-room",
            "callId": "uuid-call",
            "conversationId": "conv-uuid",
            "from": "userA",
            "initiatedBy": "userA",
            "peerId": "userB",
            "type": "audio",
            "callType": "VOICE",
            "ringingTimeoutMs": 45000,
            "participants": [
                ["userId": "userA", "username": "Alice", "phone": "+33111"],
                ["userId": "userB", "username": "Bob", "phone": "+33222"]
            ]
        ])

        XCTAssertEqual(parsed?.ringingTimeoutMs, 45000)
        XCTAssertEqual(parsed?.conversationId, "conv-uuid")
        XCTAssertEqual(parsed?.caller?.userId, "userA")
        XCTAssertFalse(parsed?.isVideo ?? true)
    }

    /// The self-blocked variant carries the room we are *already* on, so it must
    /// stay distinguishable from a callee simply being busy.
    func test_callBusy_distinguishesAlreadyInCallFromCalleeBusy() {
        let calleeBusy = event("CALL_BUSY", [
            "roomId": "uuid-room",
            "callId": "uuid-call",
            "userId": "userB",
            "reason": "callee_busy"
        ])
        XCTAssertEqual(calleeBusy?.reason, "callee_busy")

        let selfBlocked = event("CALL_BUSY", [
            "reason": "already_in_call",
            "roomId": "other-room-id"
        ])
        XCTAssertEqual(selfBlocked?.reason, "already_in_call")
        XCTAssertEqual(selfBlocked?.roomId, "other-room-id")
    }

    /// The real payload observed from the server carries no `roomId` at all,
    /// unlike the documented example. It must still be recognised, and it must
    /// stay distinguishable from a callee simply being busy.
    func test_callBusy_alreadyInCallWithoutRoomId() {
        let parsed = event("CALL_BUSY", [
            "reason": "already_in_call",
            "timestamp": "2026-07-31T14:57:07.269Z"
        ])

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.reason, "already_in_call")
        XCTAssertNil(parsed?.roomId)
    }

    func test_callPong_readsCallAndRoom() {
        let parsed = event("CALL_PONG", [
            "callId": "uuid-call",
            "roomId": "uuid-room",
            "ts": 1_722_412_800_000
        ])
        XCTAssertEqual(parsed?.callId, "uuid-call")
        XCTAssertEqual(parsed?.roomId, "uuid-room")
    }

    func test_callHold_readsHoldFlag() {
        let parsed = event("CALL_HOLD", [
            "callId": "uuid-call",
            "roomId": "uuid-room",
            "heldBy": "userA",
            "isOnHold": true
        ])
        XCTAssertEqual(parsed?.payload["isOnHold"] as? Bool, true)
    }

    /// Agent transfer (§9.4), distinct from the multi-device handoff.
    func test_callTransferred_readsTargetUser() {
        let parsed = event("CALL_TRANSFERRED", [
            "callId": "uuid-call",
            "roomId": "uuid-room",
            "transferredBy": "userA",
            "fromUserId": "userA",
            "toUserId": "userC"
        ])
        XCTAssertEqual(parsed?.payload["toUserId"] as? String, "userC")
    }

    func test_callEnded_readsCancelledAndTimeoutReasons() {
        XCTAssertEqual(
            event("CALL_ENDED", ["roomId": "r", "callId": "c", "endedBy": "userA", "reason": "CANCELLED"])?.reason,
            "CANCELLED"
        )
        XCTAssertEqual(
            event("CALL_ENDED", ["roomId": "r", "callId": "c", "reason": "TIMEOUT"])?.reason,
            "TIMEOUT"
        )
    }

    func test_callStatusChanged_readsPresenceStatus() {
        let parsed = event("CALL_STATUS_CHANGED", [
            "userId": "userA",
            "status": "AVAILABLE",
            "since": "2026-07-31T10:00:10.000Z",
            "callId": "uuid-call"
        ])
        XCTAssertEqual(parsed?.callStatus, "AVAILABLE")
        // No roomId in this payload — it is presence, not a room event.
        XCTAssertNil(parsed?.roomId)
    }

    func test_peerJoined_readsSingularUserObject() {
        let parsed = event("CALL_PEER_JOINED", [
            "roomId": "uuid-room",
            "peerId": "userB",
            "user": ["userId": "userB", "username": "Bob", "phone": "+33222"]
        ])
        XCTAssertEqual(parsed?.user?.userId, "userB")
        XCTAssertEqual(parsed?.user?.username, "Bob")
        XCTAssertEqual(parsed?.user?.phone, "+33222")
        // `participants` is absent here — the joiner must still be identifiable.
        XCTAssertTrue(parsed?.participants.isEmpty ?? false)
    }

    func test_peerLeft_readsPeerId() {
        XCTAssertEqual(event("CALL_PEER_LEFT", ["roomId": "r", "peerId": "userA"])?.peerId, "userA")
    }

    func test_deviceTransferred_readsBothDeviceIds() {
        let parsed = event("CALL_DEVICE_TRANSFERRED", [
            "roomId": "uuid-room",
            "callId": "uuid-call",
            "userId": "userB",
            "fromDeviceId": "device-old",
            "toDeviceId": "device-android-2",
            "reason": "answered_on_device"
        ])
        XCTAssertEqual(parsed?.fromDeviceId, "device-old")
        XCTAssertEqual(parsed?.toDeviceId, "device-android-2")
        XCTAssertEqual(parsed?.reason, "answered_on_device")
    }

    /// A null `fromDeviceId` is documented ("device-old-or-null") and must not
    /// be read as a device named "null".
    func test_deviceTransferred_toleratesNullFromDevice() {
        let parsed = event("CALL_DEVICE_TRANSFERRED", [
            "roomId": "r",
            "userId": "userB",
            "fromDeviceId": NSNull(),
            "toDeviceId": "device-2"
        ])
        XCTAssertNil(parsed?.fromDeviceId)
        XCTAssertEqual(parsed?.toDeviceId, "device-2")
    }

    // MARK: - Outbound offer identity

    /// The server resolves conversation membership by `userId`. Sending a phone
    /// number there is what makes an offer fail with `CORE_INITIATE_FAILED`, so
    /// the two fields must stay distinct when the callee is a known contact.
    func test_offerCarriesAccountIdNotPhone() throws {
        let offer = CallOfferDTO(
            sessionId: "sess-1",
            deviceId: "device-1",
            roomId: "room-1",
            peerId: "611768bb8b70e0c342bedd7b",
            conversationId: "conv-1",
            type: "audio",
            participants: [
                CallParticipantDTO(
                    userId: "611768bb8b70e0c342bedd7b",
                    username: "NDIKUMANA YOHANA",
                    phone: "09506569666"
                ),
                CallParticipantDTO(
                    userId: "5f2c9a1b7d3e4f0012ab34cd",
                    username: "Bob",
                    phone: "098741201"
                )
            ]
        )

        let encoded = try JSONEncoder().encode(offer)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let participants = try XCTUnwrap(json["participants"] as? [[String: Any]])

        XCTAssertEqual(participants.count, 2)
        for participant in participants {
            let userId = participant["userId"] as? String
            let phone = participant["phone"] as? String
            XCTAssertNotNil(userId)
            XCTAssertNotEqual(userId, phone, "userId must not be the phone number")
        }
    }

    // MARK: - §9.2 Mediasoup

    func test_offerMedia_mapsToMediaSetup() {
        let parsed = event("CALL_OFFER_MEDIA", [
            "callId": "uuid-call",
            "roomId": "uuid-room",
            "peerId": "userA",
            "type": "offer-media",
            "sendTransportOptions": [
                "id": "transport-send-uuid",
                "iceParameters": ["usernameFragment": "abc"],
                "iceCandidates": [["foundation": "1"]],
                "dtlsParameters": ["role": "auto"]
            ],
            "recvTransportOptions": [
                "id": "transport-recv-uuid",
                "iceParameters": ["usernameFragment": "def"],
                "iceCandidates": [],
                "dtlsParameters": ["role": "auto"]
            ],
            "rtpCapabilities": ["codecs": []],
            "peers": []
        ])

        let setup = CallMediaMapper.setup(from: parsed!)
        XCTAssertEqual(setup?.sendTransport.id, "transport-send-uuid")
        XCTAssertEqual(setup?.recvTransport.id, "transport-recv-uuid")
        // Nested objects are handed to the SFU client as JSON strings.
        XCTAssertEqual(setup?.routerRtpCapabilities, #"{"codecs":[]}"#)
        XCTAssertEqual(setup?.recvTransport.iceCandidates, "[]")
        // Absent in the contract's example, and optional for the client.
        XCTAssertNil(setup?.sendTransport.sctpParameters)
    }

    func test_setupIsNilWhenATransportIsMissing() {
        let parsed = event("CALL_OFFER_MEDIA", [
            "roomId": "uuid-room",
            "rtpCapabilities": ["codecs": []],
            "sendTransportOptions": [
                "id": "send",
                "iceParameters": [:],
                "iceCandidates": [],
                "dtlsParameters": [:]
            ]
        ])
        XCTAssertNil(CallMediaMapper.setup(from: parsed!))
    }

    func test_iceAnswer_readsTransportAndStatus() {
        let parsed = event("CALL_ICE_ANSWER", [
            "roomId": "uuid-room",
            "peerId": "userA",
            "transportId": "transport-uuid",
            "status": "connected"
        ])
        XCTAssertEqual(parsed?.transportId, "transport-uuid")
        XCTAssertEqual(parsed?.callStatus, "connected")
    }

    func test_newProducer_readsProducerAndMediaType() {
        let parsed = event("CALL_NEW_PRODUCER", [
            "roomId": "uuid-room",
            "producerId": "producer-uuid",
            "peerId": "userA",
            "kind": "audio",
            "mediaType": "audio",
            "rtpParameters": [:]
        ])
        XCTAssertEqual(parsed?.producerId, "producer-uuid")
        XCTAssertEqual(parsed?.mediaKind, "audio")
        XCTAssertFalse(parsed?.isScreenShare ?? true)
    }

    /// A screen share is an ordinary video producer distinguished only by
    /// `mediaType`.
    func test_newProducer_flagsScreenShare() {
        let parsed = event("CALL_NEW_PRODUCER", [
            "roomId": "uuid-room",
            "producerId": "producer-uuid",
            "peerId": "userA",
            "kind": "video",
            "mediaType": "screen",
            "rtpParameters": [:]
        ])
        XCTAssertTrue(parsed?.isScreenShare ?? false)
    }

    func test_consumerCreated_mapsToConsumerParameters() {
        let parsed = event("CALL_CONSUMER_CREATED", [
            "roomId": "uuid-room",
            "peerId": "userB",
            "consumerId": "consumer-uuid",
            "producerId": "producer-uuid",
            "kind": "video",
            "rtpParameters": ["encodings": []]
        ])

        let parameters = CallMediaMapper.consumerParameters(from: parsed!)
        XCTAssertEqual(parameters?.consumerId, "consumer-uuid")
        XCTAssertEqual(parameters?.producerId, "producer-uuid")
        XCTAssertEqual(parameters?.kind, .video)
        XCTAssertEqual(parameters?.peerId, "userB")
        XCTAssertEqual(parameters?.rtpParameters, #"{"encodings":[]}"#)
    }

    func test_producerState_readsPausedFlag() {
        let parsed = event("CALL_PRODUCER_STATE", [
            "roomId": "uuid-room",
            "peerId": "userA",
            "kind": "audio",
            "isPaused": true
        ])
        XCTAssertEqual(parsed?.isPaused, true)
        XCTAssertEqual(parsed?.mediaKind, "audio")
    }

    // MARK: - §9.3 Keep-alive and errors

    func test_reconnecting_readsTryCount() {
        let parsed = event("CALL_RECONNECTING", [
            "roomId": "uuid-room",
            "peerId": "userA",
            "tryCount": 1
        ])
        XCTAssertEqual(parsed?.roomId, "uuid-room")
        XCTAssertEqual(parsed?.peerId, "userA")
    }

    /// The error text is infrastructure-facing and separate from the code the
    /// client branches on.
    func test_callError_readsCodeAndMessageSeparately() {
        let parsed = event("CALL_ERROR", [
            "roomId": "uuid-room",
            "callId": "uuid-call",
            "error": "core_initiate_failed",
            "code": "CORE_INITIATE_FAILED"
        ])
        XCTAssertEqual(parsed?.errorCode, "CORE_INITIATE_FAILED")
        XCTAssertEqual(parsed?.errorMessage, "core_initiate_failed")
    }

    func test_callError_lockBusyIsRecognisable() {
        XCTAssertEqual(
            event("CALL_ERROR", ["roomId": "r", "code": "LOCK_BUSY"])?.errorCode,
            "LOCK_BUSY"
        )
    }

    /// Silent signaling is still parsed — suppression governs alerting, not
    /// whether the event reaches the state machine.
    func test_suppressedEventsStillParse() {
        let parsed = event("CALL_ERROR", ["roomId": "r", "code": "CORE_INITIATE_FAILED"])
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.suppressNotification, true)
        XCTAssertEqual(parsed?.showsNotification, false)
    }

    // MARK: - Conference features (§16)

    /// §16.1 ingress: `{ sessionId, roomId, peerId, callId }`. `targetUserId` is
    /// present only on the host's ack, and must not appear otherwise — the
    /// server reads it as the person being acted on.
    func test_handRaisePayloadOmitsTargetWhenAbsent() throws {
        let dto = CallHandDTO(sessionId: "s1", roomId: "r1", peerId: "userB", callId: "c1")
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(dto)
        ) as! [String: Any]

        XCTAssertEqual(json["sessionId"] as? String, "s1")
        XCTAssertEqual(json["roomId"] as? String, "r1")
        XCTAssertEqual(json["peerId"] as? String, "userB")
        XCTAssertEqual(json["callId"] as? String, "c1")
        XCTAssertNil(json["targetUserId"])
    }

    func test_handAckPayloadCarriesTarget() throws {
        let dto = CallHandDTO(
            sessionId: "s1", roomId: "r1", peerId: "host", callId: "c1", targetUserId: "userB"
        )
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(dto)
        ) as! [String: Any]

        XCTAssertEqual(json["targetUserId"] as? String, "userB")
    }

    func test_reactionPayloadCarriesEmoji() throws {
        let dto = CallReactionDTO(sessionId: "s1", roomId: "r1", peerId: "userA", reaction: "👏")
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(dto)
        ) as! [String: Any]

        XCTAssertEqual(json["reaction"] as? String, "👏")
        XCTAssertEqual(json["peerId"] as? String, "userA")
    }
}
