//
//  RealtimeAuthBridgeTests.swift
//  WaanguChatSDKTests
//
//  SDK plan, step 1.9 — the bridge that gives the realtime connection the chat token. It lived in
//  the Waangu app target without tests.
//

import XCTest
import WaanguCoreKit
@testable import WaanguChatSDK

final class RealtimeAuthBridgeTests: XCTestCase {

    private func bridge(accessValid: Bool, refreshValid: Bool, token: String?) -> RealtimeAuthBridge {
        RealtimeAuthBridge(
            tokenManager: ScriptedChatTokens(accessValid: accessValid, refreshValid: refreshValid, token: token),
            eventBus: EventBus.shared)
    }

    /// A JWT with only an `exp` claim, base64url without padding like real ones.
    private func jwt(exp: Double) -> String {
        func encode(_ object: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(["alg": "HS256"])).\(encode(["exp": exp])).sig"
    }

    func test_aValidAccessToken_isUsedAsIs_withItsExpiry() async throws {
        let token = jwt(exp: 1_900_000_000)
        let credentials = try await bridge(accessValid: true, refreshValid: true, token: token)
            .realtimeClientNeedsToken()

        XCTAssertEqual(credentials.token, token)
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertNil(credentials.userId)
    }

    /// An access token that is not a JWT still connects; the expiry is simply unknown, so the
    /// transport cannot refresh ahead of time.
    func test_aTokenThatIsNotAJWT_connects_withoutAnExpiry() async throws {
        let credentials = try await bridge(accessValid: true, refreshValid: true, token: "opaque-session-id")
            .realtimeClientNeedsToken()

        XCTAssertEqual(credentials.token, "opaque-session-id")
        XCTAssertNil(credentials.expiresAt)
    }

    func test_anExpiredAccessToken_withAValidRefreshToken_asksTheTokenManager() async throws {
        let credentials = try await bridge(accessValid: false, refreshValid: true, token: "refreshed")
            .realtimeClientNeedsToken()

        XCTAssertEqual(credentials.token, "refreshed")
    }

    func test_noValidToken_failsAsAnExpiredSession() async {
        do {
            _ = try await bridge(accessValid: false, refreshValid: false, token: nil).realtimeClientNeedsToken()
            XCTFail("no token must not connect")
        } catch let error as RealtimeError {
            guard case .authenticationFailed(let reason) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(reason.contains("session expired"), reason)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_aValidAccessToken_thatTheManagerCannotReturn_failsAuthentication() async {
        do {
            _ = try await bridge(accessValid: true, refreshValid: true, token: nil).realtimeClientNeedsToken()
            XCTFail("a missing token must not connect")
        } catch let error as RealtimeError {
            guard case .authenticationFailed = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_aRefreshThatReturnsNothing_failsAsARefreshFailure() async {
        do {
            _ = try await bridge(accessValid: false, refreshValid: true, token: nil).realtimeClientNeedsToken()
            XCTFail("a failed refresh must not connect")
        } catch let error as RealtimeError {
            guard case .tokenRefreshFailed = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_refreshesNinetySecondsBeforeExpiry() {
        XCTAssertEqual(bridge(accessValid: true, refreshValid: true, token: "t").tokenRefreshThreshold, 90)
    }

    // MARK: Expired chat session, renewed by logging in again

    func test_anExpiredSession_isRenewed_whenTheHostCanLogInAgain() async throws {
        let tokens = RenewableChatTokens()
        let bridge = RealtimeAuthBridge(tokenManager: tokens, eventBus: EventBus.shared,
                                        reauthenticate: { await tokens.renew(to: "new-session") })

        let credentials = try await bridge.realtimeClientNeedsToken()

        XCTAssertEqual(credentials.token, "new-session")
    }

    func test_anExpiredSession_staysExpired_whenTheNewLoginFails() async {
        let tokens = RenewableChatTokens()
        let bridge = RealtimeAuthBridge(tokenManager: tokens, eventBus: EventBus.shared,
                                        reauthenticate: { false })
        do {
            _ = try await bridge.realtimeClientNeedsToken()
            XCTFail("a failed login must not connect")
        } catch let error as RealtimeError {
            guard case .authenticationFailed(let reason) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(reason.contains("session expired"), reason)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}

/// Chat tokens that start expired and become valid when `renew(to:)` runs, like a new chat login.
private actor RenewableChatTokens: ChatTokenManagerProtocol {
    private var token: String?

    func renew(to newToken: String) -> Bool { token = newToken; return true }

    func saveTokens(accessToken: String, accessTokenExpiration: Date,
                    refreshToken: String, refreshTokenExpiration: Date) async throws {}
    func clearTokens() async throws { token = nil }
    func getAccessToken() async throws -> String? { token }
    func getRefreshToken() async throws -> String? { nil }
    func hasValidAccessToken() async -> Bool { token != nil }
    func hasValidRefreshToken() async -> Bool { false }
}
