import Testing
import Foundation
@testable import WaanguCoreKit

/// Niveau 6 — versionnement et compatibilité de schéma (§25).
///
/// Les tests contractuels que le §25 réclame : compatibilité ascendante,
/// version incompatible, champs inconnus, objet expiré, signature absente.
@Suite("Bloc 6 — contrats de niveau 6")
struct Bloc6ContractLevel6Tests {

    private func v(_ major: Int, _ minor: Int) -> SchemaVersion {
        SchemaVersion(major: major, minor: minor)
    }

    // MARK: - Compatibilité de schéma

    @Test("Une version identique est pleinement compatible")
    func identicalVersionIsFullyCompatible() {
        let verdict = SchemaVersion.compatibility(of: v(2, 1), against: v(2, 1))
        #expect(verdict == .fullyCompatible)
        #expect(verdict.permitsRead)
        #expect(verdict.permitsWrite)
    }

    /// Le backend ajoute un champ ; les clients déployés continuent de lire.
    /// C'est tout l'intérêt d'une mineure.
    @Test("Une mineure supérieure reste lisible")
    func higherMinorIsForwardCompatible() {
        let verdict = SchemaVersion.compatibility(of: v(2, 5), against: v(2, 1))
        #expect(verdict == .forwardCompatible(unknownFieldsPossible: true))
        #expect(verdict.permitsRead)
    }

    /// **Le point qui compte.** Lire un objet plus récent est acceptable ; le
    /// réécrire effacerait en silence les champs qu'on n'a pas décodés.
    @Test("Une mineure supérieure interdit la réécriture")
    func forwardCompatibleForbidsWrite() {
        let verdict = SchemaVersion.compatibility(of: v(2, 5), against: v(2, 1))
        #expect(verdict.permitsRead)
        #expect(!verdict.permitsWrite)
    }

    @Test("Une mineure inférieure reste pleinement compatible")
    func lowerMinorIsFullyCompatible() {
        #expect(SchemaVersion.compatibility(of: v(2, 0), against: v(2, 3)) == .fullyCompatible)
    }

    /// Une majeure différente est une rupture : un champ a disparu ou changé de
    /// sens, et le client ne sait pas ce qu'il lirait.
    @Test("Une majeure différente est incompatible, dans les deux sens")
    func differentMajorIsIncompatible() {
        let newer = SchemaVersion.compatibility(of: v(3, 0), against: v(2, 1))
        let older = SchemaVersion.compatibility(of: v(1, 9), against: v(2, 1))

        #expect(newer == .incompatible(expected: v(2, 1), received: v(3, 0)))
        #expect(older == .incompatible(expected: v(2, 1), received: v(1, 9)))
        #expect(!newer.permitsRead)
        #expect(!older.permitsRead)
    }

    // MARK: - Encodage

    /// La fidélité de l'aller-retour, pas sa graphie.
    ///
    /// `SchemaVersion` préexiste au Bloc 6 et s'encode en objet. Imposer ici la
    /// forme `"2.7"` que j'aurais préférée changerait le format d'un type déjà
    /// émis par le backend et déjà persisté : le test vérifie donc ce qui
    /// compte — une version relue est la version écrite.
    @Test("Une version fait un aller-retour fidèle")
    func versionRoundTrips() throws {
        for version in [v(0, 0), v(1, 0), v(2, 7), v(12, 345)] {
            let encoded = try JSONEncoder().encode(version)
            let decoded = try JSONDecoder().decode(SchemaVersion.self, from: encoded)
            #expect(decoded == version)
        }
    }

    /// Une version mal formée **fait échouer le décodage**. Retomber sur `1.0`
    /// ferait traiter un objet inconnu comme un objet de première version.
    @Test("Une version mal formée est rejetée")
    func malformedVersionIsRejected() {
        let malformed = [
            "{}",                       // les deux composantes manquent
            "{\"major\": 2}",             // la mineure manque
            "{\"minor\": 1}",             // la majeure manque
            "{\"major\": \"deux\", \"minor\": 1}", // mauvais type
            "\"2.1\"",                   // chaîne : pas la forme attendue
        ]
        for raw in malformed {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(SchemaVersion.self, from: Data(raw.utf8))
            }
        }
    }

    @Test("Les versions s'ordonnent par majeure puis mineure")
    func versionsOrderCorrectly() {
        #expect(v(1, 9) < v(2, 0))
        #expect(v(2, 1) < v(2, 10))
        #expect(!(v(2, 0) < v(2, 0)))
    }

    // MARK: - Enveloppe typée

    private struct SamplePayload: Codable, Sendable, Equatable {
        let amount: Int
    }

    private func envelope(schema: SchemaVersion) -> TypedEventEnvelope<SamplePayload> {
        TypedEventEnvelope(
            metadata: EventEnvelope(
                eventID: "e-1", eventType: FinancialEventType.paymentConfirmed,
                schemaVersion: schema, aggregateID: "p-1", aggregateVersion: 3,
                occurredAt: Date(), producer: "payments",
                correlationID: CorrelationId()
            ),
            payload: SamplePayload(amount: 1_000),
            traceID: "t-1", idempotencyKey: "k-1"
        )
    }

    @Test("L'enveloppe typée fait un aller-retour complet")
    func typedEnvelopeRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let source = envelope(schema: v(1, 0))
        let restored = try decoder.decode(TypedEventEnvelope<SamplePayload>.self,
                                          from: encoder.encode(source))

        #expect(restored.payload == source.payload)
        #expect(restored.metadata.eventID == "e-1")
        #expect(restored.traceID == "t-1")
        #expect(restored.idempotencyKey == "k-1")
    }

    @Test("La compatibilité de l'enveloppe suit celle du schéma")
    func envelopeCompatibilityFollowsSchema() {
        #expect(envelope(schema: v(1, 0)).envelopeCompatibility(with: v(1, 0)) == .fullyCompatible)
        #expect(!envelope(schema: v(2, 0)).envelopeCompatibility(with: v(1, 0)).permitsRead)
        #expect(envelope(schema: v(1, 4)).envelopeCompatibility(with: v(1, 0)).permitsRead)
    }

    /// Un champ inconnu dans la charge ne casse pas le décodage : c'est ce que
    /// la compatibilité ascendante promet.
    @Test("Un champ inconnu dans la charge ne casse pas le décodage")
    func unknownPayloadFieldIsIgnored() throws {
        let json = """
        {"amount": 500, "champInconnuAjouteParLeBackend": "quelque chose"}
        """
        let decoded = try JSONDecoder().decode(SamplePayload.self, from: Data(json.utf8))
        #expect(decoded.amount == 500)
    }

    /// Un champ **requis** manquant doit échouer : l'accepter produirait un
    /// objet à moitié construit qu'on croirait complet.
    @Test("Un champ requis manquant fait échouer le décodage")
    func missingRequiredFieldFails() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SamplePayload.self, from: Data("{}".utf8))
        }
    }

    // MARK: - Objets expirés et non signés

    /// Un objet expiré ne s'utilise pas, quel que soit le reste de son contenu.
    @Test("Les objets datés refusent l'usage après expiration")
    func expiredObjectsAreRefused() {
        let now = Date()
        let context = SignedDeepLinkContext(
            appID: "a", objectType: "o", objectID: "1", contextID: "c",
            issuedAt: now.addingTimeInterval(-120), expiresAt: now.addingTimeInterval(-1),
            nonce: "n", signature: "s"
        )
        #expect(context.hasExpired(at: now))

        let capability = CardProvisioningCapability(
            cardID: "c-1", isAvailable: true, handoffID: "h",
            expiresAt: now.addingTimeInterval(-1)
        )
        #expect(!capability.isUsable(at: now))
    }

    /// Un retour de mini-app qui prétend un aboutissement sans contexte signé
    /// est la forme exacte d'un lien fabriqué pour faire croire à un paiement.
    @Test("Un aboutissement prétendu sans preuve est signalé")
    func completionWithoutProofIsFlagged() {
        let reference = NativeObjectReference(appID: "waangu.ride", objectType: "ride",
                                              objectID: "r-1")
        let unproven = NativeAppCallback(reference: reference, claimedLifecycle: .completed,
                                         receivedAt: Date())
        let harmless = NativeAppCallback(reference: reference, claimedLifecycle: .inProgress,
                                         receivedAt: Date())

        #expect(unproven.claimsCompletionWithoutProof)
        #expect(!harmless.claimsCompletionWithoutProof)
    }

    // MARK: - Noms d'événements

    /// Des constantes plutôt que des chaînes libres : une faute de frappe
    /// produit un abonnement qui ne reçoit jamais rien, et ce silence ne se
    /// distingue pas d'une absence d'activité.
    @Test("Les noms d'événements suivent la convention pointée")
    func eventTypesFollowConvention() {
        let names = [
            FinancialEventType.merchantVerified,
            FinancialEventType.invoicePaid,
            FinancialEventType.paymentConfirmed,
            FinancialEventType.cardTransactionCaptured,
            FinancialEventType.splitContributionPaid,
            FinancialEventType.collectionDisbursementCreated,
            FinancialEventType.nativeObjectUpdated,
            FinancialEventType.reconciliationOpened,
        ]
        for name in names {
            #expect(name.contains("."))
            #expect(name == name.lowercased())
            #expect(!name.hasPrefix("."))
            #expect(!name.hasSuffix("."))
        }
    }
}
