//
//  ChatErrorCategoryTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.11 — les onze catégories d'erreur de la spécification (§16.1),
//  lues depuis `AppError`, `APIError` et `URLError`.
//

import XCTest
import WaanguCoreKit
import WaanguNetworkKit
@testable import WaanguFeatureChat

final class ChatErrorCategoryTests: XCTestCase {

    private struct Unrecognised: Error {}

    func test_appError_isMappedToItsCategory() {
        let expected: [(AppError, ChatErrorCategory)] = [
            (.noInternetConnection, .networkUnavailable),
            (.networkError("x"), .networkUnavailable),
            (.timeout, .timeout),
            (.serverError, .serviceUnavailable),
            (.serviceUnavailable, .serviceUnavailable),
            (.rateLimited, .rateLimited),
            (.notFound, .resourceNotFound),
            (.forbidden, .permissionDenied),
            (.badRequest(message: "x"), .validationFailed),
            (.validationError(statusCode: 422, message: "x"), .validationFailed),
            (.validationError(statusCode: 409, message: "x"), .conflict),
            (.authenticationError("x"), .authenticationRequired),
            (.sessionExpired, .sessionExpired),
            (.tokenRefreshFailed, .sessionExpired),
            (.decodingError("x"), .unknown),
            (.cancelled, .unknown),
            (.unknown("x"), .unknown),
        ]
        for (error, category) in expected {
            XCTAssertEqual(ChatErrorCategory(error), category, "\(error)")
        }
    }

    func test_apiError_isMappedToItsCategory() {
        let offline = URLError(.notConnectedToInternet)
        let expected: [(APIError, ChatErrorCategory)] = [
            (.noInternetConnection, .networkUnavailable),
            (.networkConnectionLost, .networkUnavailable),
            (.networkError(offline), .networkUnavailable),
            (.sslError(offline), .networkUnavailable),
            (.timeout, .timeout),
            (.unauthorized, .authenticationRequired),
            (.forbidden, .permissionDenied),
            (.notFound, .resourceNotFound),
            (.badRequest(message: nil), .validationFailed),
            (.clientError(statusCode: 422, message: nil), .validationFailed),
            (.clientError(statusCode: 409, message: nil), .conflict),
            (.serverError(statusCode: 503), .serviceUnavailable),
            (.circuitBreakerOpen(endpointKey: "k"), .serviceUnavailable),
            (.rateLimited(endpointKey: "k"), .rateLimited),
            (.cancelled, .unknown),
            (.custom("x"), .unknown),
        ]
        for (error, category) in expected {
            XCTAssertEqual(ChatErrorCategory(error), category, "\(error)")
        }
    }

    func test_urlError_isMappedToItsCategory() {
        XCTAssertEqual(ChatErrorCategory(URLError(.notConnectedToInternet)), .networkUnavailable)
        XCTAssertEqual(ChatErrorCategory(URLError(.networkConnectionLost)), .networkUnavailable)
        XCTAssertEqual(ChatErrorCategory(URLError(.timedOut)), .timeout)
        XCTAssertEqual(ChatErrorCategory(URLError(.userAuthenticationRequired)), .authenticationRequired)
        XCTAssertEqual(ChatErrorCategory(URLError(.badURL)), .unknown)
    }

    /// Une erreur que le Chat ne connaît pas n'est jamais rangée « au plus proche ».
    func test_anErrorOfAnotherType_isUnknown() {
        XCTAssertEqual(ChatErrorCategory(Unrecognised()), .unknown)
    }

    func test_everyCategoryOfTheSpecification_exists() {
        XCTAssertEqual(Set(ChatErrorCategory.allCases.map(\.rawValue)), [
            "networkUnavailable", "sessionExpired", "authenticationRequired", "permissionDenied",
            "resourceNotFound", "validationFailed", "rateLimited", "serviceUnavailable",
            "conflict", "timeout", "unknown",
        ])
    }

    // MARK: ChatLaunchFailure

    func test_launchFailure_carriesTheCategory_andLogsIt() {
        let launch = ChatLaunchContext(route: .conversation(id: "conv_SECRET"), source: .push)

        let failure = ChatLaunchFailure(launch: launch, error: AppError.sessionExpired)

        XCTAssertEqual(failure.category, .sessionExpired)
        XCTAssertTrue(failure.logLine.contains("category=sessionExpired"), failure.logLine)
        XCTAssertFalse(failure.logLine.contains("SECRET"), failure.logLine)
    }
}
