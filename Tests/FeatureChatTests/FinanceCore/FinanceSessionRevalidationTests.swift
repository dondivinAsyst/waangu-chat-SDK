//
//  FinanceSessionRevalidationTests.swift
//  FeatureChatTests
//
//  §1.6 — un instantané pris avant la reprise de session ne conclut pas seul.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

@MainActor
final class FinanceSessionRevalidationTests: XCTestCase {

    /// Ce qu'une reprise (`POST /session/resume`) peut lever.
    func test_restrictionsAResumeCanClear() {
        for restriction: FinanceSessionViewModel.Restriction in [.countryClosed, .sessionLocked,
                                                                 .paymentsDisabled, .readDenied] {
            XCTAssertTrue(FinanceSessionViewModel.mayClearAfterResume(restriction), "\(restriction)")
        }
    }

    /// Ce qu'elle ne lève pas : le serveur l'a décidé, pas l'instantané.
    func test_restrictionsAResumeCannotClear() {
        for restriction: FinanceSessionViewModel.Restriction in [.serviceSuspended, .safeMode, .unavailable] {
            XCTAssertFalse(FinanceSessionViewModel.mayClearAfterResume(restriction), "\(restriction)")
        }
    }
}
