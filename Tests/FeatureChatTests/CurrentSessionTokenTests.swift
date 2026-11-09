//
//  CurrentSessionTokenTests.swift
//  FeatureChatTests
//
//  The legacy upload paths read the host's token when they send, so a token the host renewed
//  is used at once. The stored copy is only the fallback.
//

import XCTest
@testable import WaanguFeatureChat

final class CurrentSessionTokenTests: XCTestCase {

    private var savedToken = ""
    private var savedProvider: (@Sendable () async -> String?)?

    override func setUp() {
        super.setUp()
        savedToken = CurrentSessionInfo.shared.token
        savedProvider = CurrentSessionInfo.shared.tokenProvider
    }

    override func tearDown() {
        CurrentSessionInfo.shared.token = savedToken
        CurrentSessionInfo.shared.tokenProvider = savedProvider
        super.tearDown()
    }

    func test_theProvidersToken_winsOverTheStoredCopy() async {
        CurrentSessionInfo.shared.token = "old"
        CurrentSessionInfo.shared.tokenProvider = { "renewed" }

        let token = await CurrentSessionInfo.shared.currentToken()

        XCTAssertEqual(token, "renewed")
    }

    func test_withoutAProvider_theStoredCopyIsUsed() async {
        CurrentSessionInfo.shared.token = "stored"
        CurrentSessionInfo.shared.tokenProvider = nil

        let token = await CurrentSessionInfo.shared.currentToken()

        XCTAssertEqual(token, "stored")
    }

    func test_aProviderWithNoToken_fallsBackToTheStoredCopy() async {
        CurrentSessionInfo.shared.token = "stored"
        CurrentSessionInfo.shared.tokenProvider = { nil }

        let nothing = await CurrentSessionInfo.shared.currentToken()
        CurrentSessionInfo.shared.tokenProvider = { "" }
        let empty = await CurrentSessionInfo.shared.currentToken()

        XCTAssertEqual(nothing, "stored")
        XCTAssertEqual(empty, "stored")
    }
}
