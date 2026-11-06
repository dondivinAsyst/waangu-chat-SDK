//
//  Bloc5ContractsTests.swift
//  FeatureChatTests
//
//  Chapitres 34 à 43 — gates §29 à §34.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - §16 — Les quatre portes

final class CapabilityGateTests: XCTestCase {

    private func capability(
        enabled: Bool = true, licensed: Bool = true,
        compliance: Bool = true, partner: Bool = true,
        from: Date = Date().addingTimeInterval(-3_600),
        until: Date? = nil
    ) -> FinancialCapability {
        FinancialCapability(
            capabilityID: FinancialCapabilityID.remittance, country: "BI",
            enabled: enabled, licensed: licensed,
            complianceApproved: compliance, partnerApproved: partner,
            effectiveFrom: from, effectiveUntil: until, configVersion: "v1"
        )
    }

    func test_allFourGatesOpenMakesItAvailable() {
        XCTAssertTrue(capability().isAvailable())
        XCTAssertNil(capability().closure())
    }

    /// **Chaque porte ferme seule.** Une capacité activée, licenciée et
    /// approuvée partenaire mais refusée par la conformité reste fermée.
    func test_eachGateClosesIndependently() {
        XCTAssertEqual(capability(enabled: false).closure(), .notEnabled)
        XCTAssertEqual(capability(licensed: false).closure(), .notLicensed)
        XCTAssertEqual(capability(compliance: false).closure(), .complianceWithheld)
        XCTAssertEqual(capability(partner: false).closure(), .partnerWithheld)
    }

    /// La licence l'emporte : on rapporte la cause la plus structurelle, celle
    /// qui ne se lèvera pas d'elle-même.
    func test_licenceIsReportedBeforeCompliance() {
        let both = capability(licensed: false, compliance: false)
        XCTAssertEqual(both.closure(), .notLicensed)
    }

    func test_periodBoundsClose() {
        let future = capability(from: Date().addingTimeInterval(3_600))
        XCTAssertEqual(future.closure(), .notYetEffective)

        let past = capability(until: Date().addingTimeInterval(-1))
        XCTAssertEqual(past.closure(), .expired)
    }

    /// **Le silence du backend n'est pas une autorisation.** Une capacité
    /// absente du catalogue est fermée.
    func test_absentCapabilityIsClosed() async {
        let gates = ClosedCapabilityGates()
        let closure = await gates.closure(for: FinancialCapabilityID.investment)
        XCTAssertEqual(closure, .notEnabled)
        let available = await gates.isAvailable(FinancialCapabilityID.investment)
        XCTAssertFalse(available)
    }

    /// Liste vide, pas liste de capacités désactivées.
    func test_closedGatesReturnNothing() async {
        let caps = await ClosedCapabilityGates().capabilities()
        XCTAssertTrue(caps.isEmpty)
    }

    func test_everyClosureHasAMessageKey() {
        for closure in CapabilityClosure.allCases {
            XCTAssertTrue(closure.messageKey.hasPrefix("finance.capability.closed."))
        }
    }
}

// MARK: - §31 — Gate quote

final class FinancialQuoteTests: XCTestCase {

    private func quote(
        rate: Decimal = 1.5, reference: Decimal? = 1.45,
        executable: Bool = true, validFor: TimeInterval = 300,
        fees: [QuoteFee] = []
    ) -> FinancialQuote {
        let q = FinancialQuote(
            quoteID: "q-1", quoteVersion: "1",
            sourceCurrency: "CAD", targetCurrency: "BIF",
            sourceAmount: 100, targetAmount: 150,
            exchangeRate: rate, referenceRate: reference,
            fees: fees, taxes: [],
            totalDebit: 105, totalReceive: 150,
            validUntil: Date().addingTimeInterval(validFor),
            serverTimestamp: Date(), quoteHash: "", executable: executable
        )
        // Rejoue avec l'empreinte correcte, comme le ferait le backend.
        return FinancialQuote(
            quoteID: q.quoteID, quoteVersion: q.quoteVersion,
            sourceCurrency: q.sourceCurrency, targetCurrency: q.targetCurrency,
            sourceAmount: q.sourceAmount, targetAmount: q.targetAmount,
            exchangeRate: q.exchangeRate, referenceRate: q.referenceRate,
            fees: q.fees, taxes: q.taxes,
            totalDebit: q.totalDebit, totalReceive: q.totalReceive,
            validUntil: q.validUntil, serverTimestamp: q.serverTimestamp,
            quoteHash: q.computedHash, executable: q.executable
        )
    }

    func test_intactQuoteVerifies() {
        XCTAssertTrue(quote().isIntact)
    }

    /// **Gate §31.** Un devis altéré est détecté avant soumission.
    func test_tamperedQuoteIsDetected() {
        let original = quote()
        let tampered = FinancialQuote(
            quoteID: original.quoteID, quoteVersion: original.quoteVersion,
            sourceCurrency: original.sourceCurrency, targetCurrency: original.targetCurrency,
            sourceAmount: original.sourceAmount,
            targetAmount: 9_999_999,                       // ← altéré
            exchangeRate: original.exchangeRate, referenceRate: original.referenceRate,
            fees: original.fees, taxes: original.taxes,
            totalDebit: original.totalDebit, totalReceive: original.totalReceive,
            validUntil: original.validUntil, serverTimestamp: original.serverTimestamp,
            quoteHash: original.quoteHash,                 // ← empreinte d'origine
            executable: original.executable
        )
        XCTAssertFalse(tampered.isIntact)
    }

    /// Un devis **indicatif** n'est pas exécutable, même valide.
    func test_indicativeQuoteIsNotExecutable() {
        XCTAssertFalse(quote(executable: false).isExecutable())
        XCTAssertTrue(quote(executable: true).isExecutable())
    }

    func test_expiredQuoteIsNotExecutable() {
        XCTAssertFalse(quote(validFor: -1).isExecutable())
    }

    /// La marge n'est calculable que si le backend rend le taux de référence.
    /// Sans lui, **le client ne l'estime pas** : une marge inventée est une
    /// information fausse là où l'utilisateur compare des offres.
    func test_marginRequiresAReferenceRate() {
        XCTAssertNotNil(quote(rate: 1.5, reference: 1.45).marginPercent)
        XCTAssertNil(quote(rate: 1.5, reference: nil).marginPercent)
    }

    func test_divergenceNamesWhatChanged() {
        let before = quote(rate: 1.5)
        let after = quote(rate: 1.9)
        XCTAssertTrue(before.divergences(from: after).contains(.exchangeRate))
    }

    /// Un devis réédité à conditions identiques ne force pas un nouvel accord.
    func test_sameConditionsProduceNoDivergence() {
        XCTAssertTrue(quote().divergences(from: quote()).isEmpty)
    }

    /// Une nature de frais inconnue reste **visible et comptée** : la masquer
    /// ferait un total supérieur à la somme des lignes affichées.
    func test_unknownFeeKindIsKeptAsOther() throws {
        let decoded = try JSONDecoder().decode(
            QuoteFee.FeeKind.self, from: Data("\"SOMETHING_NEW\"".utf8)
        )
        XCTAssertEqual(decoded, .other)
    }
}

// MARK: - §34 — Corridors et sens

final class RemittanceTests: XCTestCase {

    private func corridor(available: Bool = true) -> RemittanceCorridor {
        RemittanceCorridor(
            sourceCountry: "CA", targetCountry: "BI",
            sourceCurrency: "CAD", targetCurrencies: ["BIF"],
            partnerID: "p-1", deliveryMethods: [.mobileMoney, .cashPickup],
            isAvailable: available, cancellationWindowSeconds: 900
        )
    }

    /// **L'activation de A→B n'active jamais B→A** (§34).
    func test_reverseCorridorIsADistinctIdentity() {
        let ca_bi = corridor()
        XCTAssertEqual(ca_bi.id, "CA->BI")
        XCTAssertEqual(ca_bi.reversedIdentity, "BI->CA")
        XCTAssertNotEqual(ca_bi.id, ca_bi.reversedIdentity)
    }

    func test_unavailableCorridorSendsNothing() {
        XCTAssertFalse(corridor(available: false).allowsSending(to: "BIF"))
    }

    func test_unsupportedTargetCurrencyIsRefused() {
        XCTAssertFalse(corridor().allowsSending(to: "RWF"))
        XCTAssertTrue(corridor().allowsSending(to: "BIF"))
    }

    /// Fixer les deux montants reviendrait à imposer un taux.
    func test_quoteRequestMustFixExactlyOneAmount() {
        let sourceOnly = RemittanceQuoteRequest(
            corridorID: "CA->BI", deliveryMethod: .mobileMoney,
            sourceAmount: 100, targetAmount: nil, targetCurrency: "BIF"
        )
        XCTAssertTrue(sourceOnly.isWellFormed)

        let both = RemittanceQuoteRequest(
            corridorID: "CA->BI", deliveryMethod: .mobileMoney,
            sourceAmount: 100, targetAmount: 150, targetCurrency: "BIF"
        )
        XCTAssertFalse(both.isWellFormed)

        let neither = RemittanceQuoteRequest(
            corridorID: "CA->BI", deliveryMethod: .mobileMoney,
            sourceAmount: nil, targetAmount: nil, targetCurrency: "BIF"
        )
        XCTAssertFalse(neither.isWellFormed)
    }

    /// **Le moment où l'argent quitte le compte** change la nature d'un échec :
    /// avant, il n'y a rien à rembourser ; après, il y a un remboursement à suivre.
    func test_debitBoundaryIsExplicit() {
        for before in [RemittanceState.draft, .quoted, .quoteExpired, .cancelled] {
            XCTAssertFalse(before.hasDebitedSender, "\(before)")
        }
        for after in [RemittanceState.funded, .submitted, .partnerProcessing, .delivered, .failed] {
            XCTAssertTrue(after.hasDebitedSender, "\(after)")
        }
    }

    func test_terminalStatesNeverReopen() {
        for terminal in [RemittanceState.delivered, .refunded, .cancelled, .blocked] {
            for target in RemittanceState.allCases where target != terminal {
                XCTAssertFalse(
                    RemittanceStateMachine.isAllowed(from: terminal, to: target),
                    "\(terminal) -> \(target)"
                )
            }
        }
    }

    /// Un échec après débit mène au remboursement, pas au néant.
    func test_failureAfterDebitLeadsToRefund() {
        XCTAssertTrue(RemittanceStateMachine.isAllowed(from: .failed, to: .refundPending))
        XCTAssertTrue(RemittanceStateMachine.isAllowed(from: .returned, to: .refundPending))
        XCTAssertTrue(RemittanceStateMachine.isAllowed(from: .refundPending, to: .refunded))
    }

    /// Un état inconnu devient `complianceReview` : ni abouti, ni échoué, et
    /// aucune action utilisateur.
    func test_unknownStateFallsBackToComplianceReview() throws {
        let decoded = try JSONDecoder().decode(
            RemittanceState.self, from: Data("\"SOMETHING_NEW\"".utf8)
        )
        XCTAssertEqual(decoded, .complianceReview)
        XCTAssertFalse(decoded.isTerminal)
    }

    /// Une méthode de livraison inconnue fait échouer le décodage : proposer
    /// « retrait espèces » là où le partenaire fait un dépôt bancaire enverrait
    /// quelqu'un attendre à un guichet pour rien.
    func test_unknownDeliveryMethodIsRefused() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(RemittanceDeliveryMethod.self, from: Data("\"DRONE\"".utf8))
        )
    }
}

// MARK: - §27 — Soldes

final class CurrencyWalletTests: XCTestCase {

    private func wallet(available: Int64 = 100_000, asOf: Date = Date()) -> CurrencyWallet {
        CurrencyWallet(id: "w-1", currency: "BIF", availableMinorUnits: available,
                       exponent: 0, asOf: asOf)
    }

    private let bif = CurrencyCode(code: "BIF", exponent: 0)

    /// **Un solde périmé ne couvre rien**, quel que soit son chiffre.
    func test_staleBalanceCoversNothing() {
        let stale = wallet(asOf: Date().addingTimeInterval(-120))
        XCTAssertTrue(stale.isStale())
        XCTAssertFalse(stale.appearsToCover(Money(minorUnits: 1, currency: bif)))
    }

    func test_freshBalanceCoversWithinItsAmount() {
        let fresh = wallet(available: 100_000)
        XCTAssertTrue(fresh.appearsToCover(Money(minorUnits: 100_000, currency: bif)))
        XCTAssertFalse(fresh.appearsToCover(Money(minorUnits: 100_001, currency: bif)))
    }

    /// Une autre devise ne se convertit pas côté client.
    func test_otherCurrencyNeverCovers() {
        let cad = CurrencyCode(code: "CAD", exponent: 2)
        XCTAssertFalse(wallet().appearsToCover(Money(minorUnits: 1, currency: cad)))
    }
}

// MARK: - §11-§12 — Crédit

final class CreditTests: XCTestCase {

    /// **Une simulation n'engage aucun prêteur.** Le champ existe pour que
    /// l'interface ne puisse pas la présenter comme une offre.
    func test_simulationIsAlwaysIndicative() {
        let sim = CreditSimulation(
            productID: "p", amount: 100_000, termMonths: 12,
            monthlyPayment: 9_000, totalCost: 108_000,
            effectiveRatePercent: 16, currency: "BIF"
        )
        XCTAssertTrue(sim.isIndicativeOnly)
    }

    func test_offerExpires() {
        let expired = CreditOffer(
            id: "o", approvedAmount: 100_000, currency: "BIF", termMonths: 12,
            ratePercent: 16, totalCost: 108_000,
            expiresAt: Date().addingTimeInterval(-1),
            disclosureDocumentID: "d", consentVersion: "v1"
        )
        XCTAssertTrue(expired.isExpired())
        XCTAssertFalse(expired.isAcceptable())
    }

    /// Sans consentement au partage de données, aucune demande ne part.
    func test_applicationRequiresDataSharingConsent() {
        let refused = CreditApplicationDraft(
            productID: "p", amount: 100_000, termMonths: 12,
            hasConsentedToDataSharing: false, consentVersion: "v1"
        )
        XCTAssertFalse(refused.isSubmittable)

        let ok = CreditApplicationDraft(
            productID: "p", amount: 100_000, termMonths: 12,
            hasConsentedToDataSharing: true, consentVersion: "v1"
        )
        XCTAssertTrue(ok.isSubmittable)
    }

    func test_declinedAndClosedAreTerminal() {
        for terminal in [CreditApplicationState.declined, .closed] {
            for target in CreditApplicationState.allCases where target != terminal {
                XCTAssertFalse(
                    CreditApplicationStateMachine.isAllowed(from: terminal, to: target),
                    "\(terminal) -> \(target)"
                )
            }
        }
    }

    /// Un état inconnu devient `underReview` : ni approuvé — ce qui promettrait
    /// un crédit — ni refusé.
    func test_unknownApplicationStateIsUnderReview() throws {
        let decoded = try JSONDecoder().decode(
            CreditApplicationState.self, from: Data("\"SOMETHING\"".utf8)
        )
        XCTAssertEqual(decoded, .underReview)
    }

    /// Un type de crédit inconnu est refusé : les régimes juridiques diffèrent.
    func test_unknownCreditKindIsRefused() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(CreditKind.self, from: Data("\"CRYPTO_LOAN\"".utf8))
        )
    }

    /// Aucune simulation locale n'est possible.
    func test_closedCreditSimulatesNothing() async {
        let result = await ClosedCredit().simulate(
            CreditSimulationRequest(productID: "p", amount: 1, termMonths: 1)
        )
        guard case .failure(let e) = result else { return XCTFail("attendu") }
        XCTAssertEqual(e, .capabilityUnavailable)
    }
}

// MARK: - §13-§14 — Épargne et investissement

final class SavingsInvestmentTests: XCTestCase {

    private func pocket(state: SavingsPocketState = .active,
                        restrictions: [String] = [],
                        matures: Date? = nil) -> SavingsPocket {
        SavingsPocket(
            id: "p-1", name: "Vacances", kind: .pocket, currency: "BIF",
            exponent: 0, balanceMinorUnits: 50_000, targetMinorUnits: 100_000,
            state: state, withdrawalRestrictionKeys: restrictions,
            maturesAt: matures, asOf: Date()
        )
    }

    func test_progressIsADisplayRatio() {
        XCTAssertEqual(pocket().progressPercent, 50)
    }

    func test_restrictedPocketRefusesWithdrawal() {
        XCTAssertFalse(pocket(state: .restricted).allowsWithdrawal())
        XCTAssertFalse(pocket(restrictions: ["locked.until.maturity"]).allowsWithdrawal())
    }

    /// Une épargne bloquée ne se retire pas avant échéance.
    func test_lockedSavingsRefusesBeforeMaturity() {
        let future = Date().addingTimeInterval(86_400)
        XCTAssertFalse(pocket(matures: future).allowsWithdrawal())
        XCTAssertTrue(pocket(matures: Date().addingTimeInterval(-1)).allowsWithdrawal())
    }

    /// Un état inconnu devient `restricted` : consultable, sans mouvement.
    func test_unknownPocketStateIsRestricted() throws {
        let decoded = try JSONDecoder().decode(
            SavingsPocketState.self, from: Data("\"SOMETHING\"".utf8)
        )
        XCTAssertEqual(decoded, .restricted)
        XCTAssertFalse(decoded.allowsMovement)
    }

    /// **Sans profil investisseur, rien n'est souscriptible.**
    func test_noProfileMeansNothingIsSuitable() {
        let product = InvestmentProduct(
            id: "f-1", kind: .fund, issuerID: "i", name: "Fonds",
            currency: "BIF", exponent: 0, riskLevelKey: "risk.high", minimumSuitabilityLevel: 3
        )
        XCTAssertFalse(product.isSuitable(for: nil))
    }

    func test_profileBelowRequirementIsNotSuitable() {
        let product = InvestmentProduct(
            id: "f-1", kind: .fund, issuerID: "i", name: "Fonds",
            currency: "BIF", exponent: 0, riskLevelKey: "risk.high", minimumSuitabilityLevel: 3
        )
        let low = InvestorProfile(suitabilityLevel: 2, horizonKey: "h",
                                  riskToleranceKey: "r", establishedAt: Date())
        let high = InvestorProfile(suitabilityLevel: 3, horizonKey: "h",
                                   riskToleranceKey: "r", establishedAt: Date())
        XCTAssertFalse(product.isSuitable(for: low))
        XCTAssertTrue(product.isSuitable(for: high))
    }

    /// Un profil périmé ne vaut plus rien.
    func test_expiredProfileIsNotSuitable() {
        let product = InvestmentProduct(
            id: "f-1", kind: .fund, issuerID: "i", name: "Fonds",
            currency: "BIF", exponent: 0, riskLevelKey: "r", minimumSuitabilityLevel: 1
        )
        let expired = InvestorProfile(
            suitabilityLevel: 5, horizonKey: "h", riskToleranceKey: "r",
            establishedAt: Date().addingTimeInterval(-10_000),
            expiresAt: Date().addingTimeInterval(-1)
        )
        XCTAssertFalse(product.isSuitable(for: expired))
    }

    /// Sans reconnaissance du risque de **cette version**, aucun ordre.
    func test_orderRequiresRiskAcknowledgement() {
        let bif = CurrencyCode(code: "BIF", exponent: 0)
        let refused = InvestmentOrderDraft(
            productID: "f", side: .subscribe,
            amount: Money(minorUnits: 10_000, currency: bif),
            riskDisclosureVersion: "v2", hasAcknowledgedRisk: false
        )
        XCTAssertFalse(refused.isSubmittable)
    }

    func test_closedInvestmentHasNoProfile() async {
        let result = await ClosedInvestment().investorProfile()
        guard case .success(let profile) = result else { return XCTFail("attendu") }
        XCTAssertNil(profile)
    }
}

// MARK: - §15 — Copilot borné

final class CopilotBoundaryTests: XCTestCase {

    /// **Une réponse sans source est une invention**, et le type ne permet pas
    /// d'en construire une.
    func test_answerWithoutSourceCannotExist() {
        XCTAssertNil(CopilotAnswer(
            textKey: "copilot.summary", sourceOperationIDs: [],
            toolID: "summary", correlationID: CorrelationId(value: "c")
        ))
    }

    func test_answerWithSourceIsValid() {
        XCTAssertNotNil(CopilotAnswer(
            textKey: "copilot.summary", sourceOperationIDs: ["op-1"],
            toolID: "summary", correlationID: CorrelationId(value: "c")
        ))
    }

    /// Sans accord explicite, aucun outil ne s'exécute.
    func test_toolWithoutUserGrantExecutesNothing() {
        let denied = ToolAuthorization(
            toolID: "t", grantedByUser: false, correlationID: CorrelationId(value: "c")
        )
        XCTAssertFalse(denied.permitsExecution)
    }
}

// MARK: - §24 — Gouvernance des champs

final class FieldGovernanceTests: XCTestCase {

    /// **L'invariant du registre.** Aucune entrée ne doit être incohérente.
    func test_registryHasNoIncoherentEntry() {
        XCTAssertTrue(
            FinancialFieldRegistry.incoherentEntries.isEmpty,
            "Champs incohérents : \(FinancialFieldRegistry.incoherentEntries.map(\.fieldName))"
        )
    }

    /// Un champ dont le backend fait autorité et que le client peut écrire est
    /// un champ que le client peut fabriquer.
    func test_backendFieldWritableByClientIsAViolation() {
        let bad = FieldGovernance(
            fieldName: "exchangeRate", domain: "quote", type: "Decimal", required: true,
            sensitive: false, sourceOfTruth: .backend, writableByClient: true,
            persistedLocally: false, auditable: true, redactedInLogs: false,
            contractVersion: "1.0"
        )
        XCTAssertTrue(bad.violations.contains(.backendFieldWritableByClient))
    }

    /// Un champ sensible non redacté finit en clair dans un journal consulté
    /// après incident.
    func test_sensitiveFieldMustBeRedacted() {
        let bad = FieldGovernance(
            fieldName: "token", domain: "delivery", type: "String", required: true,
            sensitive: true, sourceOfTruth: .partner, writableByClient: false,
            persistedLocally: false, auditable: true, redactedInLogs: false,
            contractVersion: "1.0"
        )
        XCTAssertTrue(bad.violations.contains(.sensitiveFieldNotRedacted))
    }

    /// Un champ sensible persisté survit à la perte de l'appareil.
    func test_sensitiveFieldMustNotBePersisted() {
        let bad = FieldGovernance(
            fieldName: "code", domain: "cashOut", type: "String", required: true,
            sensitive: true, sourceOfTruth: .backend, writableByClient: false,
            persistedLocally: true, auditable: true, redactedInLogs: true,
            contractVersion: "1.0"
        )
        XCTAssertTrue(bad.violations.contains(.sensitiveFieldPersisted))
    }

    /// Toute valeur financière exécutable a le backend ou le partenaire pour
    /// autorité — jamais le client.
    func test_noFinancialValueIsClientOwned() {
        let financialDomains = ["quote", "wallet", "credit", "investment"]
        for entry in FinancialFieldRegistry.entries where financialDomains.contains(entry.domain) {
            XCTAssertNotEqual(entry.sourceOfTruth, .client, entry.fieldName)
            XCTAssertFalse(entry.writableByClient, entry.fieldName)
        }
    }
}
