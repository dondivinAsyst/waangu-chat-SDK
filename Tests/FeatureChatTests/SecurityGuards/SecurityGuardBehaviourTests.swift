//
//  SecurityGuardBehaviourTests.swift
//  FeatureChatTests
//
//  TEST-GUARDS-001 — ce que trois gardes de sécurité garantissent réellement.
//
//  Écrits à partir du code des gardes (2026-10-06), pas des brouillons de
//  Tests/EnterprisePhase8/9*, qui appelaient des API inexistantes.
//
//  Aucune de ces gardes n'est appelée en production aujourd'hui :
//  MessageConfirmationGuard est injectée dans le Chat sans être appelée,
//  PolicyApprovalGuard et CacheStaleGuard n'ont aucun appelant.
//
//  Les « vérifications de signature » des deux premières ne contrôlent qu'une
//  longueur. Les tests `knownGap` le consignent avec XCTExpectFailure : ils
//  passent tant que la faiblesse existe, et échouent dès qu'une vraie
//  vérification arrive — il faudra alors retirer XCTExpectFailure.
//

import XCTest
import WaanguCoreKit
@testable import WaanguSecurityKit
@testable import WaanguStorageKit

// MARK: - MessageConfirmationGuard

final class MessageConfirmationGuardBehaviourTests: XCTestCase {

    private let sut = MessageConfirmationGuard(logger: AppLogger.shared)
    private let wellFormedSignature = String(repeating: "a", count: 64)

    private func isValid(_ result: MessageConfirmationValidationResult) -> Bool {
        if case .valid = result { return true }
        return false
    }

    private func reason(_ result: MessageConfirmationValidationResult) -> String? {
        if case .invalid(let reason) = result { return reason }
        return nil
    }

    func test_freshConfirmation_withWellFormedSignature_isValid() async {
        let result = await sut.validate(messageId: "m1", serverSignature: wellFormedSignature, timestamp: Date())
        XCTAssertTrue(isValid(result))
    }

    func test_confirmationOlderThanFiveMinutes_isRejected() async {
        let result = await sut.validate(messageId: "m1", serverSignature: wellFormedSignature,
                                        timestamp: Date().addingTimeInterval(-301))
        XCTAssertEqual(reason(result), "Confirmation expired")
    }

    func test_confirmationFromTheFuture_isRejected() async {
        let result = await sut.validate(messageId: "m1", serverSignature: wellFormedSignature,
                                        timestamp: Date().addingTimeInterval(60))
        XCTAssertEqual(reason(result), "Confirmation expired")
    }

    func test_shortOrEmptySignature_isRejected() async {
        for signature in ["", String(repeating: "a", count: 63)] {
            let result = await sut.validate(messageId: "m1", serverSignature: signature, timestamp: Date())
            XCTAssertEqual(reason(result), "Invalid signature", "length \(signature.count)")
        }
    }

    /// B31 — n'importe quelle chaîne de 64 caractères passe pour une signature serveur.
    func test_knownGap_forgedSignatureOfValidLength_shouldBeRejected() async {
        let forged = String(repeating: "0", count: 64)
        let result = await sut.validate(messageId: "m1", serverSignature: forged, timestamp: Date())
        XCTExpectFailure("B31: the guard checks signature length only, not authenticity")
        XCTAssertFalse(isValid(result), "A forged signature was accepted")
    }
}

// MARK: - PolicyApprovalGuard

final class PolicyApprovalGuardBehaviourTests: XCTestCase {

    /// Instance partagée : chaque test utilise ses propres identifiants.
    private let sut = PolicyApprovalGuard.shared
    private let wellFormedSignature = String(repeating: "b", count: 64)

    private func newPolicyId() -> String { "policy-\(UUID().uuidString)" }

    func test_mobileCanNeverApproveAPolicy_whateverTheSourceClaims() async {
        for source in [ApprovalSource.local, .unknown, .backend] {
            let policyId = newPolicyId()
            do {
                try await sut.approvePolicy(policyId: policyId, policyType: .privacyPolicy, source: source)
                XCTFail("Approval succeeded with source \(source)")
            } catch let error as PolicyApprovalGuard.PolicyApprovalError {
                let expected: PolicyApprovalGuard.PolicyApprovalError =
                    source == .backend ? .invalidApprovalSource : .localApprovalForbidden
                XCTAssertEqual(error, expected, "source \(source)")
            } catch {
                XCTFail("Unexpected error \(error)")
            }
            let approved = await sut.isBackendApproved(policyId: policyId)
            XCTAssertFalse(approved)
        }
    }

    func test_blockedAttemptsAreRecorded() async throws {
        let policyId = newPolicyId()
        _ = try? await sut.approvePolicy(policyId: policyId, policyType: .termsOfService, source: .local)
        let attempts = await sut.getBlockedAttempts().filter { $0.policyId == policyId }
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.blocked, true)
    }

    func test_backendApprovalWithoutEvidence_isRejected() async {
        let policyId = newPolicyId()
        do {
            try await sut.registerBackendApproval(policyId: policyId, policyType: .paymentPolicy, version: "1",
                                                  backendSignature: wellFormedSignature, approvedBy: "ops",
                                                  evidenceRefs: [], timestamp: Date())
            XCTFail("Approval without evidence was accepted")
        } catch {
            XCTAssertEqual(error as? PolicyApprovalGuard.PolicyApprovalError, .missingEvidenceRefs)
        }
        let approved = await sut.isBackendApproved(policyId: policyId)
        XCTAssertFalse(approved)
    }

    func test_backendApprovalWithShortSignature_isRejected() async {
        let policyId = newPolicyId()
        do {
            try await sut.registerBackendApproval(policyId: policyId, policyType: .paymentPolicy, version: "1",
                                                  backendSignature: "short", approvedBy: "ops",
                                                  evidenceRefs: ["ev-1"], timestamp: Date())
            XCTFail("Approval with a short signature was accepted")
        } catch {
            XCTAssertEqual(error as? PolicyApprovalGuard.PolicyApprovalError, .invalidBackendSignature)
        }
    }

    func test_registeredApproval_isScopedToItsVersion() async throws {
        let policyId = newPolicyId()
        try await sut.registerBackendApproval(policyId: policyId, policyType: .compliancePolicy, version: "2.1",
                                              backendSignature: wellFormedSignature, approvedBy: "ops",
                                              evidenceRefs: ["ev-1"], timestamp: Date())
        let approved = await sut.isBackendApproved(policyId: policyId)
        let sameVersion = await sut.isPolicyVersionApproved(policyId: policyId, version: "2.1")
        let otherVersion = await sut.isPolicyVersionApproved(policyId: policyId, version: "2.2")
        XCTAssertTrue(approved)
        XCTAssertTrue(sameVersion)
        XCTAssertFalse(otherVersion)
    }

    /// B31 — une « approbation backend » se fabrique avec 64 caractères quelconques.
    func test_knownGap_forgedBackendSignature_shouldBeRejected() async {
        let policyId = newPolicyId()
        try? await sut.registerBackendApproval(policyId: policyId, policyType: .paymentPolicy, version: "1",
                                               backendSignature: String(repeating: "0", count: 64),
                                               approvedBy: "anyone", evidenceRefs: ["made-up"], timestamp: Date())
        let approved = await sut.isBackendApproved(policyId: policyId)
        XCTExpectFailure("B31: verifyBackendSignature checks length only, not an HMAC")
        XCTAssertFalse(approved, "A forged backend approval was registered")
    }
}

// MARK: - CacheStaleGuard

final class CacheStaleGuardBehaviourTests: XCTestCase {

    private let sut = CacheStaleGuard.shared

    private func newKey() -> String { "cache-\(UUID().uuidString)" }

    private let critical: [CacheStaleGuard.ActionType] = [.payment, .transfer, .authentication, .authorization, .criticalAction]

    func test_criticalClassification() async {
        for action in critical {
            let isCritical = await sut.isCriticalAction(action)
            XCTAssertTrue(isCritical, action.rawValue)
        }
        let nonCritical = await sut.isCriticalAction(.nonCritical)
        XCTAssertFalse(nonCritical)
    }

    func test_staleCache_blocksEveryCriticalAction() async {
        let key = newKey()
        await sut.registerCache(key: key, ttl: -1)   // already expired
        for action in critical {
            do {
                try await sut.validateCacheForAction(key: key, actionType: action)
                XCTFail("\(action.rawValue) ran on a stale cache")
            } catch {
                XCTAssertEqual(error as? CacheStaleGuard.CacheStaleError, .staleCacheForCriticalAction, action.rawValue)
            }
        }
    }

    func test_staleCache_stillAllowsNonCriticalActions() async throws {
        let key = newKey()
        await sut.registerCache(key: key, ttl: -1)
        try await sut.validateCacheForAction(key: key, actionType: .nonCritical)
    }

    func test_freshCache_allowsCriticalActions() async throws {
        let key = newKey()
        await sut.registerCache(key: key, ttl: 60)
        let stale = await sut.isStale(key: key)
        XCTAssertFalse(stale)
        try await sut.validateCacheForAction(key: key, actionType: .payment)
    }

    /// Sans entrée, la garde laisse passer : l'appelant doit alors lire au serveur.
    func test_unknownKey_isReportedStale_butDoesNotBlock() async throws {
        let key = newKey()
        let stale = await sut.isStale(key: key)
        XCTAssertTrue(stale)
        try await sut.validateCacheForAction(key: key, actionType: .payment)
    }
}
