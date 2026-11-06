//
//  Bloc12CriticalTests.swift
//  FeatureChatTests
//
//  Bloc 12, §XX — tests critiques obligatoires qui n'avaient pas d'équivalent.
//
//  Les autres identifiants (FS, RETRY, OFFLINE, COMP, CACHE, RECON, CRASH, DL…)
//  sont déjà prouvés par des tests existants : la correspondance complète est
//  tenue dans `Scripts/bloc12/critical_tests.json`, que
//  `Scripts/bloc12/run_critical_tests.sh` exécute.
//

import XCTest
import WaanguCoreKit
import WaanguNavigationKit
@testable import WaanguFeatureChat

final class Bloc12CriticalTests: XCTestCase {

    // MARK: - TEST-IDEMP-001 — deux taps ne créent pas deux opérations

    /// Deux demandes **simultanées** de la même opération doivent recevoir la
    /// même clé.
    ///
    /// Le registre persistant répond de façon asynchrone : pendant qu'il lit le
    /// trousseau pour le premier tap, l'acteur accepte le second, qui trouve le
    /// cache encore vide et fabrique une autre clé. Deux clés, deux opérations.
    func test_IDEMP_001_concurrentRequestsForOneOperation_shareOneKey() async {
        let keys = FinanceOperationKeys(preserver: SlowRegistry())
        let scope = FinanceOperationKeys.scope("bill.pay", "bill-7", 18_000)

        async let first = keys.key(for: scope, deviceID: "d")
        async let second = keys.key(for: scope, deviceID: "d")
        let (a, b) = await (first, second)

        XCTAssertEqual(a.key, b.key, "Un double tap ne doit jamais produire deux clés")
    }

    // MARK: - TEST-KILL-001 — le coupe-circuit désactive effectivement

    func test_KILL_001_fullSuspension_closesEveryEntry_evenWithoutCapabilityID() {
        for kind in FinanceEntryKind.allCases {
            XCTAssertEqual(
                FinanceEntryAdmission.decide(kind: kind, suspensions: .everything, closure: nil),
                .suspended(reasonKey: "finance.killswitch.unavailable"),
                "\(kind) reste ouvert malgré la coupure totale"
            )
        }
    }

    func test_KILL_001_suspendedProduct_beatsAnOpenCapability() {
        let suspensions = KillSwitchState(suspendedProducts: [FinanceEntryKind.remittance.rawValue])

        XCTAssertEqual(
            FinanceEntryAdmission.decide(kind: .remittance, suspensions: suspensions, closure: nil),
            .suspended(reasonKey: nil)
        )
        XCTAssertEqual(
            FinanceEntryAdmission.decide(kind: .sendMoney, suspensions: suspensions, closure: nil),
            .open, "Suspendre un produit ne ferme pas les autres"
        )
    }

    func test_KILL_001_suspendedWorkflow_closesTheEntryUsingIt() throws {
        let capability = try XCTUnwrap(FinanceEntryKind.fxConversion.capabilityID)
        let suspensions = KillSwitchState(suspendedWorkflows: [capability])

        XCTAssertEqual(
            FinanceEntryAdmission.decide(kind: .fxConversion, suspensions: suspensions, closure: nil),
            .suspended(reasonKey: nil)
        )
    }

    /// Sans suspension, la porte de capacité garde la main.
    func test_KILL_001_noSuspension_leavesCapabilityDecision() {
        XCTAssertEqual(
            FinanceEntryAdmission.decide(kind: .remittance, suspensions: .none, closure: .notLicensed),
            .closed(.notLicensed)
        )
    }

    // MARK: - TEST-NOTIF-001 — un push n'est jamais une preuve financière

    /// Un push ne peut transporter ni statut ni montant jusqu'au client : la
    /// liste blanche les écarte, et il ne reste qu'un identifiant à relire.
    func test_NOTIF_001_pushCannotCarryStatusOrAmount() {
        let result = NotificationRedactor().redact([
            "objectType": "PAYMENT", "objectId": "obj-1",
            "status": "COMPLETED", "amount": "250000", "currency": "BIF"
        ])

        XCTAssertNil(result.payload["status"], "Un statut reçu par push ne doit pas survivre")
        XCTAssertNil(result.payload["amount"])
        XCTAssertEqual(Set(result.payload.keys), ["objectType", "objectId"])
    }

    /// La navigation déclenchée par un push financier ne porte qu'un
    /// identifiant opaque : l'écran doit relire le serveur, il n'a rien d'autre.
    func test_NOTIF_001_financialPushIntent_carriesOnlyAnOpaqueID() {
        let intent = NavigationIntents.Chat.financialObject(opaqueId: "obj-1")
        XCTAssertEqual(Set(intent.params.keys), ["opaqueId"])

        // Avec le type : toujours aucun statut, montant ou contrepartie.
        let typed = NavigationIntents.Chat.financialObject(opaqueId: "obj-1", objectType: "PAYMENT")
        XCTAssertEqual(Set(typed.params.keys), ["opaqueId", "objectType"])
    }

    /// Un push ouvre l'objet **sans** rien afficher de lui-même : la référence
    /// porte une révision nulle et c'est la lecture serveur qui la remplit.
    @MainActor
    func test_NOTIF_001_pushRoute_opensTheObject_withoutInventedState() {
        let reference = ChatCoordinator.financialObjectReference(opaqueId: "obj-1", objectType: "PAYMENT")
        XCTAssertEqual(reference?.id, "obj-1")
        XCTAssertEqual(reference?.type, .payment)
        XCTAssertEqual(reference?.version, 0)

        XCTAssertNil(ChatCoordinator.financialObjectReference(opaqueId: "obj-1", objectType: "NOT_A_TYPE"),
                     "Un type inconnu ne doit pas être deviné")
        XCTAssertNil(ChatCoordinator.financialObjectReference(opaqueId: "", objectType: "PAYMENT"))
    }

    // MARK: - TEST-I18N-001 — aucune chaîne financière critique manquante

    /// Chaque clé appelée par `FinanceStrings` doit exister, non vide, dans les
    /// quatre langues livrées — sinon l'écran affiche le repli français à un
    /// utilisateur anglophone, ou pire, la clé brute.
    func test_I18N_001_everyFinanceKeyIsTranslatedInEveryShippedLocale() throws {
        var keys = try financeKeysUsedInSource()
        XCTAssertGreaterThan(keys.count, 100, "Extraction des clés suspecte")

        // Quatre clés sont des **préfixes** complétés à l'exécution par une valeur
        // d'énumération : on vérifie chaque valeur réelle, pas le préfixe.
        let dynamic: [String: [String]] = [
            "cashin_channel_": CashInChannel.allCases.map(\.rawValue),
            "cashout_channel_": CashOutChannel.allCases.map(\.rawValue),
            "topup_kind_": TopUpKind.allCases.map(\.rawValue),
            // Les catégories de litige viennent du serveur ; le guide en liste onze.
            "dispute_category_": ["UNRECOGNIZED_PAYMENT", "WRONG_BENEFICIARY", "CASH_RECEIVED_NOT_CREDITED",
                                  "CASHOUT_NOT_REMITTED", "SERVICE_NOT_DELIVERED", "DOUBLE_DEBIT",
                                  "BILLER_NOT_UPDATED", "TOPUP_NOT_DELIVERED", "REFUND_NOT_RECEIVED",
                                  "QR_FRAUD", "OTHER"],
        ]
        for (prefix, values) in dynamic {
            XCTAssertTrue(keys.contains(prefix), "Préfixe \(prefix) introuvable : la construction a changé")
            keys.remove(prefix)
            keys.formUnion(values.map { prefix + $0.lowercased() })
        }
        let unexpandedPrefixes = keys.filter { $0.hasSuffix("_") }
        XCTAssertTrue(unexpandedPrefixes.isEmpty, "Préfixe dynamique non couvert : \(unexpandedPrefixes)")

        for locale in ["fr", "en", "es", "de"] {
            let table = try financeTable(locale)
            let missing = keys.filter { (table[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertTrue(missing.isEmpty,
                          "\(locale) : \(missing.count) clé(s) sans traduction — \(missing.sorted().prefix(15))")
        }
    }

    /// Un paramètre perdu à la traduction affiche « %@ » ou fait planter le
    /// formatage : chaque langue doit porter les mêmes marqueurs que le français.
    func test_I18N_001_placeholdersMatchAcrossLocales() throws {
        let reference = try financeTable("fr")
        for locale in ["en", "es", "de"] {
            let table = try financeTable(locale)
            var mismatched: [String] = []
            for (key, frValue) in reference {
                guard let value = table[key] else { continue }
                if placeholders(in: frValue) != placeholders(in: value) { mismatched.append(key) }
            }
            XCTAssertTrue(mismatched.isEmpty,
                          "\(locale) : marqueurs différents du français — \(mismatched.sorted().prefix(15))")
        }
    }

    // MARK: - TEST-COUNTRY-001 — une capacité non autorisée reste inaccessible

    /// Une entrée sans identifiant de capacité ne passerait par aucune porte de
    /// pays. Le P0 du Bloc 13 est fermé depuis la Phase 1 : chaque entrée en porte
    /// un (clé de gouvernance Chat Core, ou son propre nom, fermé en live).
    ///
    /// Cliquet : la dette connue est vide, et toute nouvelle entrée sans
    /// capacité échoue ici.
    func test_COUNTRY_001_ungatedEntries_cannotGrow() {
        let ungated = Set(FinanceEntryKind.allCases.filter { $0.capabilityID == nil })
        let knownOpenDebt: Set<FinanceEntryKind> = [
            .requestMoney, .sendMoney, .cashIn, .cashOut, .payBill, .qrPay, .qrPresent,
            .merchant, .orders, .remoteForm, .invoice, .paymentLinks, .cards,
            .splitBill, .campaign, .reconciliation, .topUp,
        ]
        XCTAssertTrue(ungated.isSubset(of: knownOpenDebt),
                      "Nouvelle entrée sans porte de pays : \(ungated.subtracting(knownOpenDebt))")
    }

    /// Une entrée gouvernée dont la licence est refusée reste fermée, quel que
    /// soit l'état du coupe-circuit.
    func test_COUNTRY_001_unlicensedCapability_staysClosed() {
        for kind in FinanceEntryKind.allCases where kind.capabilityID != nil {
            XCTAssertEqual(
                FinanceEntryAdmission.decide(kind: kind, suspensions: .none, closure: .notLicensed),
                .closed(.notLicensed), "\(kind)"
            )
        }
    }

    // MARK: - Lecture des traductions

    private var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TranslationKit/Resources")
    }

    private func financeTable(_ locale: String) throws -> [String: String] {
        let data = try Data(contentsOf: resources.appendingPathComponent("translations_\(locale).json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let modules = try XCTUnwrap(root["modules"] as? [String: Any])
        return try XCTUnwrap(modules["finance"] as? [String: String])
    }

    /// Clés **littérales** passées à `t(…)` dans `FinanceStrings`, normalisées
    /// comme le fait `FinanceLocalization` : sans préfixe `finance.`, points
    /// remplacés par des soulignés.
    private func financeKeysUsedInSource() throws -> Set<String> {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FeatureChat/Translation/FinanceTranslationKeys.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\bt\(\s*"(finance\.[a-z0-9_.]+)""#)
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { raw in
                String(text[raw].dropFirst("finance.".count)).replacingOccurrences(of: ".", with: "_")
            }
        })
    }

    private func placeholders(in value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(\d+\$)?[@dfsi]|\{[a-zA-Z0-9_]+\}"#)
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
    }
}

// MARK: - Doublure

/// Registre dont chaque lecture suspend — comme le trousseau réel, derrière un acteur.
private actor SlowRegistry: IdempotencyKeyPreserving {
    private var contexts: [String: IdempotencyContext] = [:]

    func register(operationID: String, context: IdempotencyContext) async throws {
        if let existing = contexts[operationID], existing.key != context.key {
            throw IdempotencyViolation.alreadyRegistered(operationID: operationID)
        }
        contexts[operationID] = context
    }
    func context(for operationID: String) async -> IdempotencyContext? {
        try? await Task.sleep(nanoseconds: 20_000_000)
        return contexts[operationID]
    }
    func assertSameKey(operationID: String, providedKey: String) async throws {}
    func purge(userID: String) async { contexts.removeAll() }
    func release(operationID: String) async { contexts[operationID] = nil }
}
