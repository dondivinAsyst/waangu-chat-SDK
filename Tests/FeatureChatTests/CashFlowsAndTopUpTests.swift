//
//  CashFlowsAndTopUpTests.swift
//  FeatureChatTests
//
//  Chapitres 19, 20, 21 et 23.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - Chapitre 19 — Cash-In

final class CashInTests: XCTestCase {

    private func instruction(
        status: PaymentStatus = .pending,
        expiresIn: TimeInterval? = 3_600
    ) -> CashInInstruction {
        CashInInstruction(
            reference: FinanceFixtures.reference(),
            channel: .agent,
            status: status,
            depositReference: "DEP-4821",
            instructionKeys: ["cashin.agent.step1", "cashin.agent.step2"],
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            amount: 50_000,
            currency: "BIF"
        )
    }

    /// Une instruction périmée doit être **remplacée**, jamais réutilisée :
    /// déposer sous une référence expirée met l'argent dans un dépôt que
    /// personne n'attend plus.
    func test_expiredInstructionIsNotActionable() {
        XCTAssertFalse(instruction(expiresIn: -1).isActionable())
        XCTAssertTrue(instruction(expiresIn: 3_600).isActionable())
    }

    func test_terminalInstructionIsNotActionable() {
        XCTAssertFalse(instruction(status: .completed).isActionable())
    }

    /// **L'idempotence client ne protège pas d'un double versement physique.**
    /// Tant qu'un dépôt est en vol, en proposer un second invite à verser deux fois.
    func test_pendingDepositFlagsDoubleDepositRisk() {
        XCTAssertTrue(instruction(status: .pending).wouldRiskDoubleDeposit)
        XCTAssertFalse(instruction(status: .completed).wouldRiskDoubleDeposit)
    }

    /// Les instructions sont des **clés**, jamais des phrases composées ici :
    /// elles varient par canal, partenaire et pays.
    func test_instructionsAreLocalisationKeys() {
        for key in instruction().instructionKeys {
            XCTAssertFalse(key.contains(" "), "\(key) doit être une clé")
        }
    }

    /// Aucun canal ouvert se dit autrement qu'une panne.
    func test_closedCashInReturnsNoChannelsNotAnError() async {
        let result = await ClosedCashIn().availableChannels()
        guard case .success(let channels) = result else { return XCTFail("attendu") }
        XCTAssertTrue(channels.isEmpty)
    }

    func test_unknownChannelFailsRatherThanFallingBack() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(CashInChannel.self, from: Data("\"CARRIER_PIGEON\"".utf8))
        )
    }
}

// MARK: - Chapitre 20 — Cash-Out

final class CashOutTests: XCTestCase {

    private func authorization(
        code: String = "483920",
        status: PaymentStatus = .authorized,
        expiresIn: TimeInterval = 900
    ) -> CashOutAuthorization {
        CashOutAuthorization(
            reference: FinanceFixtures.reference(),
            channel: .agent,
            status: status,
            code: code,
            amount: 20_000,
            currency: "BIF",
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    /// **Le code est un porteur de valeur.** Le type refuse de se décrire en
    /// entier plutôt que de compter sur la discipline de chaque `print`.
    func test_descriptionNeverLeaksTheCode() {
        let auth = authorization(code: "483920")
        XCTAssertFalse(auth.description.contains("483920"))
        XCTAssertTrue(auth.description.contains("redacted"))
    }

    /// Partout sauf sur l'écran de retrait, seules les deux dernières positions
    /// apparaissent.
    func test_maskedCodeRevealsOnlyTheLastTwo() {
        XCTAssertEqual(authorization(code: "483920").maskedCode, "••••20")
        XCTAssertEqual(authorization(code: "12").maskedCode, "••")
    }

    func test_expiredCodeIsNotPresentable() {
        XCTAssertFalse(authorization(expiresIn: -1).isPresentable())
        XCTAssertTrue(authorization(expiresIn: 900).isPresentable())
    }

    func test_terminalAuthorizationIsNotPresentable() {
        XCTAssertFalse(authorization(status: .completed).isPresentable())
    }

    /// **L'échec de révocation doit être visible.** Un utilisateur qui croit
    /// avoir révoqué un code compromis et ne l'a pas fait est dans une situation
    /// pire que s'il le savait.
    func test_closedRevokeFailsLoudly() async {
        let result = await ClosedCashOut().revoke(
            FinanceFixtures.reference(), idempotency: FinanceFixtures.idempotency()
        )
        guard case .failure(let error) = result else {
            return XCTFail("la révocation ne doit pas réussir en silence")
        }
        XCTAssertEqual(error, .capabilityUnavailable)
    }
}

// MARK: - Chapitre 21 — Pay Bill

final class BillPayingTests: XCTestCase {

    private func bill(
        due: Decimal = 12_000,
        partial: Bool = false,
        fetchedAgo: TimeInterval = 10
    ) -> Bill {
        Bill(
            reference: FinanceFixtures.reference(),
            billerID: "regideso",
            customerLabel: "Compteur 4821",
            amountDue: due,
            currency: "BIF",
            arrears: nil,
            dueDate: nil,
            fetchedAt: Date().addingTimeInterval(-fetchedAgo),
            allowsPartialPayment: partial
        )
    }

    /// Une facture datée ne se paie pas en silence : le montant a pu changer.
    func test_staleBillIsDetected() {
        XCTAssertFalse(bill(fetchedAgo: 10).isStale())
        XCTAssertTrue(bill(fetchedAgo: 400).isStale())
    }

    /// Sans accord du facturier, seul le montant exact passe.
    func test_partialPaymentRefusedWhenBillerForbidsIt() {
        let b = bill(due: 12_000, partial: false)
        XCTAssertTrue(b.accepts(amount: 12_000))
        XCTAssertFalse(b.accepts(amount: 5_000))
    }

    func test_partialPaymentAllowedWhenBillerPermitsIt() {
        XCTAssertTrue(bill(due: 12_000, partial: true).accepts(amount: 5_000))
    }

    /// Payer plus que le dû créerait un avoir que le Chat ne sait pas suivre.
    func test_overpaymentIsRefused() {
        XCTAssertFalse(bill(due: 12_000, partial: true).accepts(amount: 20_000))
        XCTAssertFalse(bill(due: 12_000, partial: true).accepts(amount: 0))
    }

    func test_closedBillingListsNoCategories() async {
        let result = await ClosedBillPaying().categories()
        guard case .success(let categories) = result else { return XCTFail("attendu") }
        XCTAssertTrue(categories.isEmpty)
    }

    /// **GAP-01.** Le formulaire vient du modèle existant de CoreKit, pas d'un
    /// second modèle écrit à côté. Ce test échouerait si quelqu'un réintroduisait
    /// un `DynamicForm` local : la signature ne compilerait plus.
    func test_formUsesTheExistingDynamicBillerModel() async {
        let result = await ClosedBillPaying().form(for: "regideso")
        guard case .failure(let error) = result else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }
}

// MARK: - Chapitre 23 — Top-Up et succès partiel

final class TopUpPartialSuccessTests: XCTestCase {

    private func order(_ statuses: [PaymentStatus]) -> TopUpOrder {
        TopUpOrder(
            reference: FinanceFixtures.reference(),
            results: statuses.enumerated().map { i, s in
                TopUpLineResult(id: "line-\(i)", msisdn: "2576100000\(i)", status: s)
            }
        )
    }

    func test_allSucceeded() {
        XCTAssertEqual(order([.completed, .confirmed]).aggregate, .allSucceeded)
    }

    func test_allFailed() {
        XCTAssertEqual(order([.failed, .failed]).aggregate, .allFailed)
    }

    /// **Le cas propre au chapitre 23.** Trois lignes sur cinq abouties :
    /// afficher « échoué » sur une opération partiellement débitée est un faux
    /// état, et le Bloc 1 a été écrit pour les empêcher.
    func test_partialSuccessIsItsOwnOutcome() {
        let result = order([.completed, .completed, .completed, .failed, .failed]).aggregate
        XCTAssertEqual(result, .partial(succeeded: 3, failed: 2))
    }

    /// **L'ignorance l'emporte sur tout.** Une ligne `unknown` interdit de
    /// conclure « tout a réussi » comme « tout a échoué » : l'utilisateur doit
    /// voir qu'on ne sait pas, pas une moyenne rassurante.
    func test_oneUnknownLineMakesTheWholeOrderUndetermined() {
        XCTAssertEqual(order([.completed, .completed, .unknown]).aggregate, .undetermined)
        XCTAssertEqual(order([.failed, .unknown]).aggregate, .undetermined)
    }

    func test_inFlightWinsOverPartialCounting() {
        XCTAssertEqual(order([.completed, .processing, .failed]).aggregate, .inFlight)
    }

    func test_emptyOrderIsUndetermined() {
        XCTAssertEqual(TopUpOrder(reference: FinanceFixtures.reference(), results: []).aggregate,
                       .undetermined)
    }

    /// **Isolation d'échec.** Rejouer l'ordre entier redébiterait les lignes
    /// déjà abouties : seules les lignes en échec franc sont relançables.
    func test_onlyFrankFailuresAreRetryable() {
        let o = order([.completed, .failed, .unknown, .processing, .expired])
        let retryable = o.retryableLines.map(\.status)
        XCTAssertEqual(Set(retryable), Set([.failed, .expired]))
        XCTAssertFalse(retryable.contains(.unknown), "une ligne ambiguë peut avoir abouti")
        XCTAssertFalse(retryable.contains(.completed))
    }
}

// MARK: - GAP-01 / GAP-06 — types de champ inconnus

final class DynamicFieldKindTests: XCTestCase {

    /// Les types connus se rendent.
    func test_knownInputTypesAreRenderable() {
        for raw in ["text", "String", "number", "NUMERIC", "phone", "msisdn", "email", "date", ""] {
            XCTAssertNotNil(SupportedFieldKind(rawInputType: raw), raw)
        }
    }

    /// **La règle du §13.** Un type inconnu ne retombe pas sur du texte : il
    /// n'est pas rendable. Un sélecteur de compte rendu en saisie libre
    /// laisserait taper n'importe quoi là où le facturier attend une valeur
    /// d'une liste fermée.
    func test_unknownInputTypeIsNotRenderable() {
        for raw in ["smartcard", "meterSelector", "quelqueChoseDeNeuf"] {
            XCTAssertNil(SupportedFieldKind(rawInputType: raw), "\(raw) ne doit pas être deviné")
        }
    }

    func test_keyboardMatchesTheKind() {
        XCTAssertEqual(SupportedFieldKind(rawInputType: "number")?.keyboard, .numberPad)
        XCTAssertEqual(SupportedFieldKind(rawInputType: "phone")?.keyboard, .phonePad)
        XCTAssertEqual(SupportedFieldKind(rawInputType: "email")?.keyboard, .emailAddress)
    }
}
