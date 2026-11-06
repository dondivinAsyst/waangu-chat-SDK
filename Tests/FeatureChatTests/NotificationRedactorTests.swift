//
//  NotificationRedactorTests.swift
//  FeatureChatTests
//
//  Chapitre 20 et §28 — un code de retrait ne fuit pas en notification.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class NotificationRedactorTests: XCTestCase {

    private let redactor = NotificationRedactor()

    /// **Le cas qui justifie tout le fichier.** Un code de retrait est un
    /// porteur de valeur : quiconque le lit sur un écran verrouillé peut
    /// retirer l'argent.
    func test_cashOutCodeNeverSurvives() {
        let result = redactor.redact([
            "objectId": "obj-1",
            "cashOutCode": "483920"
        ])
        XCTAssertNil(result.payload["cashOutCode"])
        XCTAssertEqual(result.forbiddenEncountered, ["cashOutCode"])
        XCTAssertEqual(result.payload["objectId"], "obj-1")
    }

    func test_allKnownSecretsAreStripped() {
        var payload = ["objectId": "obj-1"]
        for key in NotificationRedactor.forbiddenKeys { payload[key] = "valeur-sensible" }

        let result = redactor.redact(payload)

        for key in NotificationRedactor.forbiddenKeys {
            XCTAssertNil(result.payload[key], "\(key) ne doit jamais survivre")
        }
        XCTAssertEqual(result.forbiddenEncountered.count, NotificationRedactor.forbiddenKeys.count)
    }

    /// **Liste blanche, pas liste noire.** Un champ sensible arrivant sous un nom
    /// que cette version ne connaît pas doit disparaître quand même — c'est la
    /// seule protection qui survit à un backend qui évolue.
    func test_unknownFieldIsDroppedEvenIfNotInTheForbiddenList() {
        let result = redactor.redact([
            "objectId": "obj-1",
            "nouveauChampSecretDeLAnneeProchaine": "483920"
        ])
        XCTAssertNil(result.payload["nouveauChampSecretDeLAnneeProchaine"])
        XCTAssertEqual(result.droppedKeys, ["nouveauChampSecretDeLAnneeProchaine"])
        // Écarté sans être signalé comme interdit : ce n'est pas un incident
        // backend, seulement un champ que ce client ne sait pas afficher.
        XCTAssertTrue(result.forbiddenEncountered.isEmpty)
    }

    /// Le montant et la contrepartie ne sont pas des secrets, et ne passent pas
    /// non plus : « 250 000 BIF de Jean D. » désigne une somme **et** une
    /// relation, sur un écran que n'importe qui peut lire.
    func test_amountAndCounterpartyDoNotSurvive() {
        let result = redactor.redact([
            "objectId": "obj-1",
            "amount": "250000",
            "counterpartyName": "Jean D."
        ])
        XCTAssertNil(result.payload["amount"])
        XCTAssertNil(result.payload["counterpartyName"])
    }

    func test_allowedRoutingFieldsSurvive() {
        let result = redactor.redact([
            "type": "PAYMENT_RECEIVED",
            "objectId": "obj-1",
            "conversationId": "conv-9",
            "version": "4",
            "correlationId": "corr-1"
        ])
        XCTAssertEqual(result.payload.count, 5)
        XCTAssertTrue(result.droppedKeys.isEmpty)
    }

    /// La détection est insensible à la casse : `PIN`, `Pin` et `pin` sont le
    /// même champ pour un backend, et doivent l'être pour le filtre.
    func test_forbiddenDetectionIsCaseInsensitive() {
        let result = redactor.redact(["objectId": "o", "PIN": "1234", "Cvv": "999"])
        XCTAssertNil(result.payload["PIN"])
        XCTAssertNil(result.payload["Cvv"])
        XCTAssertEqual(result.forbiddenEncountered.count, 2)
    }

    // MARK: - Texte visible

    /// Les corps sont des **clés**, jamais des phrases : une notification
    /// financière en français chez un anglophone est une régression de produit.
    func test_bodiesAreLocalisationKeys() {
        for kind in FinancialNotificationKind.allCases {
            let body = redactor.safeBody(for: kind)
            XCTAssertTrue(body.hasPrefix("notification.finance."), "\(kind)")
            XCTAssertFalse(body.contains(" "), "\(kind) doit être une clé, pas une phrase")
        }
    }

    func test_securityAndActionHidePreview() {
        XCTAssertTrue(redactor.requiresHiddenPreview(for: .securityAlert))
        XCTAssertTrue(redactor.requiresHiddenPreview(for: .actionRequired))
        XCTAssertFalse(redactor.requiresHiddenPreview(for: .paymentReceived))
    }

    /// Une nature inconnue devient la plus discrète, celle qui invite à ouvrir
    /// l'application plutôt qu'à conclure quoi que ce soit.
    func test_unknownKindFallsBackToActionRequired() throws {
        let decoded = try JSONDecoder().decode(
            FinancialNotificationKind.self,
            from: Data("\"SOMETHING_NEW\"".utf8)
        )
        XCTAssertEqual(decoded, .actionRequired)
        XCTAssertTrue(redactor.requiresHiddenPreview(for: decoded))
    }
}
