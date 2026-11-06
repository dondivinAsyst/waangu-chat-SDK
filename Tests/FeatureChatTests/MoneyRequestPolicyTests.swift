//
//  MoneyRequestPolicyTests.swift
//  FeatureChatTests
//
//  Chapitre 17 — l'anti-harcèlement est livré avec la demande d'argent,
//  jamais après.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

private enum PolicyFixtures {
    static func open(
        maxReminders: Int = 3,
        interval: TimeInterval = 3_600,
        maxOpen: Int = 2,
        nonContacts: Bool = true,
        blocked: Bool = false
    ) -> MoneyRequestPolicy {
        MoneyRequestPolicy(
            maxRemindersPerRequest: maxReminders,
            minIntervalBetweenReminders: interval,
            maxOpenRequestsPerRecipient: maxOpen,
            allowsRequestToNonContacts: nonContacts,
            recipientHasBlockedSender: blocked
        )
    }
}

final class MoneyRequestPolicyTests: XCTestCase {

    // MARK: - Nouvelle demande

    func test_newRequestIsAllowedWithinBounds() {
        let verdict = PolicyFixtures.open().verdictForNewRequest(openRequests: 0, isContact: true)
        XCTAssertEqual(verdict, .allowed)
    }

    /// **Le blocage l'emporte sur tout.** C'est un refus de la personne, pas une
    /// borne de volume : aucun compteur ne doit pouvoir le contourner.
    func test_blockedRecipientRefusesEvenWithZeroOpenRequests() {
        let verdict = PolicyFixtures.open(blocked: true)
            .verdictForNewRequest(openRequests: 0, isContact: true)
        XCTAssertEqual(verdict, .refused(reasonKey: "finance.request.refused.blocked"))
    }

    func test_nonContactRefusedWhenPolicyForbidsIt() {
        let verdict = PolicyFixtures.open(nonContacts: false)
            .verdictForNewRequest(openRequests: 0, isContact: false)
        XCTAssertEqual(verdict, .refused(reasonKey: "finance.request.refused.not_a_contact"))
    }

    func test_tooManyOpenRequestsRefused() {
        let verdict = PolicyFixtures.open(maxOpen: 2)
            .verdictForNewRequest(openRequests: 2, isContact: true)
        XCTAssertEqual(verdict, .refused(reasonKey: "finance.request.refused.too_many_open"))
    }

    // MARK: - Relance

    func test_firstReminderIsAllowed() {
        let verdict = PolicyFixtures.open().verdictForReminder(remindersSent: 0, lastReminderAt: nil)
        XCTAssertEqual(verdict, .allowed)
    }

    /// La borne de volume : au-delà, plus aucune relance, même espacée.
    func test_reminderLimitIsEnforced() {
        let verdict = PolicyFixtures.open(maxReminders: 3)
            .verdictForReminder(
                remindersSent: 3,
                lastReminderAt: Date().addingTimeInterval(-100_000)
            )
        XCTAssertEqual(verdict, .refused(reasonKey: "finance.request.refused.reminder_limit"))
    }

    /// La borne de fréquence : relancer toutes les dix secondes est du
    /// harcèlement même en restant sous le plafond de volume.
    func test_reminderTooSoonIsRefused() {
        let verdict = PolicyFixtures.open(maxReminders: 5, interval: 3_600)
            .verdictForReminder(
                remindersSent: 1,
                lastReminderAt: Date().addingTimeInterval(-10)
            )
        XCTAssertEqual(verdict, .refused(reasonKey: "finance.request.refused.reminder_too_soon"))
    }

    func test_reminderAllowedOnceIntervalHasPassed() {
        let verdict = PolicyFixtures.open(maxReminders: 5, interval: 60)
            .verdictForReminder(
                remindersSent: 1,
                lastReminderAt: Date().addingTimeInterval(-120)
            )
        XCTAssertEqual(verdict, .allowed)
    }

    func test_blockedRecipientRefusesReminders() {
        let verdict = PolicyFixtures.open(blocked: true)
            .verdictForReminder(remindersSent: 0, lastReminderAt: nil)
        XCTAssertEqual(verdict, .refused(reasonKey: "finance.request.refused.blocked"))
    }

    // MARK: - Politique fermée

    /// **Le repli.** Zéro relance, zéro demande ouverte, pas de non-contacts.
    /// Un abus se répare ; une demande jamais partie ne fait de mal à personne.
    func test_closedPolicyRefusesEverything() {
        XCTAssertEqual(
            MoneyRequestPolicy.closed.verdictForNewRequest(openRequests: 0, isContact: true),
            .refused(reasonKey: "finance.request.refused.too_many_open")
        )
        XCTAssertEqual(
            MoneyRequestPolicy.closed.verdictForReminder(remindersSent: 0, lastReminderAt: nil),
            .refused(reasonKey: "finance.request.refused.reminder_limit")
        )
    }
}

// MARK: - Service fermé par défaut

final class ClosedMoneyRequestServiceTests: XCTestCase {

    /// La politique est rendue **fermée**, pas en erreur : la surface doit
    /// pouvoir dire pourquoi elle est fermée, et un échec technique ne dirait
    /// pas la même chose à l'utilisateur qu'une borne atteinte.
    func test_closedServiceReturnsClosedPolicyNotAnError() async {
        let result = await ClosedMoneyRequestService().policy(towards: "rcpt-1")
        guard case .success(let policy) = result else {
            return XCTFail("la politique doit être rendue, pas échouer")
        }
        XCTAssertEqual(policy, .closed)
    }

    func test_closedServiceCreatesNothing() async {
        let draft = MoneyRequestDraft(
            recipientID: "rcpt-1", amount: 1_000, currency: "BIF"
        )
        let result = await ClosedMoneyRequestService().createRequest(
            draft, idempotency: FinanceFixtures.idempotency()
        )
        guard case .failure(let error) = result else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }

    /// Un montant `nil` est un cas d'usage — montant libre — et non une erreur.
    func test_draftAcceptsFreeAmount() {
        let draft = MoneyRequestDraft(recipientID: "r", amount: nil, currency: "BIF")
        XCTAssertNil(draft.amount)
    }
}
