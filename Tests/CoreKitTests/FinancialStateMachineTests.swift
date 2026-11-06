//
//  FinancialStateMachineTests.swift
//  CoreKitTests
//
//  Bloc 9, §4 — « Interdire toute transition financière non autorisée ».
//

import XCTest
@testable import WaanguCoreKit

/// Vérifie les tables de transition financières.
///
/// Elles étaient écrites, correctes en lecture, et **sans aucun test**. Une
/// table de transition non testée est précisément l'endroit où une transition
/// illégale passe : la table dit non, personne ne vérifie qu'on la consulte, et
/// une virgule déplacée ouvre un chemin que rien ne signale.
final class FinancialStateMachineTests: XCTestCase {

    // MARK: - Mandats

    /// Une révocation est **définitive**. Si `revoked` retrouvait une sortie,
    /// un prélèvement que l'utilisateur a coupé pourrait redémarrer.
    func test_mandate_revokedIsTerminal() {
        for target in MandateStatus.allCases where target != .revoked {
            XCTAssertFalse(
                MandateStateMachine.isAllowed(from: .revoked, to: target),
                "revoked → \(target) doit être refusé : la révocation est définitive."
            )
        }
    }

    func test_mandate_expiredIsTerminal() {
        for target in MandateStatus.allCases where target != .expired {
            XCTAssertFalse(MandateStateMachine.isAllowed(from: .expired, to: target))
        }
    }

    /// Un mandat ne devient pas actif sans passer par l'approbation : c'est
    /// l'étape où l'utilisateur consent au prélèvement récurrent.
    func test_mandate_cannotActivateWithoutApproval() {
        XCTAssertFalse(MandateStateMachine.isAllowed(from: .pendingConsent, to: .active),
                       "Activer sans approbation sauterait le consentement.")
        XCTAssertTrue(MandateStateMachine.isAllowed(from: .pendingApproval, to: .active))
    }

    func test_mandate_suspendedCanResume() {
        XCTAssertTrue(MandateStateMachine.isAllowed(from: .active, to: .suspended))
        XCTAssertTrue(MandateStateMachine.isAllowed(from: .suspended, to: .active))
    }

    // MARK: - Transferts internationaux

    /// Un envoi livré ne repart pas. `delivered` est un fait constaté chez le
    /// partenaire, pas un état révisable côté client.
    func test_remittance_deliveredIsTerminal() {
        for target in RemittanceState.allCases where target != .delivered {
            XCTAssertFalse(
                RemittanceStateMachine.isAllowed(from: .delivered, to: target),
                "delivered → \(target) doit être refusé."
            )
        }
    }

    /// On ne soumet pas un envoi non financé : ce serait promettre au partenaire
    /// un argent qui n'a pas été prélevé.
    func test_remittance_cannotSubmitBeforeFunding() {
        XCTAssertFalse(RemittanceStateMachine.isAllowed(from: .quoted, to: .submitted))
        XCTAssertTrue(RemittanceStateMachine.isAllowed(from: .funded, to: .submitted))
    }

    /// Un devis périmé se re-cote, il ne se finance pas.
    func test_remittance_expiredQuoteCannotBeFunded() {
        XCTAssertFalse(RemittanceStateMachine.isAllowed(from: .quoteExpired, to: .funded),
                       "Financer un devis périmé exécuterait un taux disparu.")
        XCTAssertTrue(RemittanceStateMachine.isAllowed(from: .quoteExpired, to: .quoted))
    }

    /// Un échec peut aller vers le remboursement — l'argent prélevé doit revenir.
    func test_remittance_failureLeadsToRefund() {
        XCTAssertTrue(RemittanceStateMachine.isAllowed(from: .failed, to: .refundPending))
    }

    // MARK: - Crédit

    /// Une demande refusée est terminale : la rouvrir contournerait la décision
    /// du prêteur.
    func test_credit_declinedIsTerminal() {
        for target in CreditApplicationState.allCases where target != .declined {
            XCTAssertFalse(
                CreditApplicationStateMachine.isAllowed(from: .declined, to: target),
                "declined → \(target) doit être refusé."
            )
        }
    }

    /// On n'accepte pas une offre qui n'a pas été émise.
    func test_credit_cannotAcceptBeforeOffer() {
        XCTAssertFalse(CreditApplicationStateMachine.isAllowed(from: .approved, to: .accepted))
        XCTAssertTrue(CreditApplicationStateMachine.isAllowed(from: .offerIssued, to: .accepted))
    }

    /// Une offre expirée ne s'accepte pas : elle repasse en revue.
    func test_credit_expiredOfferCannotBeAccepted() {
        XCTAssertFalse(CreditApplicationStateMachine.isAllowed(from: .offerExpired, to: .accepted),
                       "Accepter une offre expirée engagerait à des conditions caduques.")
    }

    /// Les fonds ne sont pas versés avant acceptation.
    func test_credit_cannotDisburseBeforeAcceptance() {
        XCTAssertFalse(CreditApplicationStateMachine.isAllowed(from: .offerIssued,
                                                              to: .disbursementPending))
        XCTAssertTrue(CreditApplicationStateMachine.isAllowed(from: .accepted,
                                                             to: .disbursementPending))
    }

    // MARK: - Invariant transversal

    /// Rester dans le même état est toujours toléré : une remise du même
    /// événement ne doit pas être traitée comme une transition illégale.
    func test_sameStateIsAlwaysAllowed() {
        XCTAssertTrue(MandateStateMachine.isAllowed(from: .active, to: .active))
        XCTAssertTrue(RemittanceStateMachine.isAllowed(from: .funded, to: .funded))
        XCTAssertTrue(CreditApplicationStateMachine.isAllowed(from: .underReview, to: .underReview))
    }
}
