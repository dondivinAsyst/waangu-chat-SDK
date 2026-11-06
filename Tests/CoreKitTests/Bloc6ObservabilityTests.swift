import Testing
import Foundation
@testable import WaanguCoreKit

/// Observabilité financière — Bloc 6, §23.
///
/// Une trace se conserve, se copie, et se lit par des gens qui n'ont jamais
/// consenti à voir ces données. Ces tests vérifient qu'aucune valeur brute
/// n'atteint les journaux.
@Suite("Bloc 6 — observabilité")
struct Bloc6ObservabilityTests {

    private func context(
        merchantID: String? = nil,
        orderID: String? = nil,
        invoiceID: String? = nil,
        cardTransactionID: String? = nil,
        nativeObjectID: String? = nil,
        idempotencyKey: String? = nil
    ) -> FinanceLogContext {
        FinanceLogContext(
            correlationID: CorrelationId(), financialObjectID: "obj-secret-1",
            objectType: .payment, objectVersion: 3, operation: "confirm",
            traceID: "trace-1", causationID: "cause-1",
            idempotencyKey: idempotencyKey, merchantID: merchantID,
            orderID: orderID, invoiceID: invoiceID,
            cardTransactionID: cardTransactionID, nativeObjectID: nativeObjectID
        )
    }

    // MARK: - Aucune valeur brute

    /// L'identifiant d'objet est haché à la construction, puis la valeur brute
    /// est abandonnée : ce qui n'existe plus en mémoire ne peut pas fuir.
    @Test("L'identifiant d'objet n'apparaît jamais en clair")
    func objectIDNeverAppearsRaw() {
        let rendered = context().description
        #expect(!rendered.contains("obj-secret-1"))
        #expect(rendered.contains("fin_object="))
    }

    /// **La clé d'idempotence contient l'identifiant d'appareil** —
    /// `IdempotencyContext.new` la compose ainsi. En clair, elle permettrait de
    /// suivre un appareil à travers tous les logs.
    @Test("La clé d'idempotence n'apparaît jamais en clair")
    func idempotencyKeyNeverAppearsRaw() {
        let key = "device-abc-123-\(UUID().uuidString)"
        let rendered = context(idempotencyKey: key).description

        #expect(!rendered.contains(key))
        #expect(!rendered.contains("device-abc-123"))
        #expect(rendered.contains("idempotency="))
    }

    @Test("Commande, facture, transaction carte et objet natif sont hachés")
    func bloc6IdentifiersAreHashed() {
        let rendered = context(
            orderID: "order-raw-1", invoiceID: "invoice-raw-1",
            cardTransactionID: "cardtx-raw-1", nativeObjectID: "native-raw-1"
        ).description

        for raw in ["order-raw-1", "invoice-raw-1", "cardtx-raw-1", "native-raw-1"] {
            #expect(!rendered.contains(raw), "\(raw) est apparu en clair")
        }
        #expect(rendered.contains("order="))
        #expect(rendered.contains("invoice="))
        #expect(rendered.contains("card_tx="))
        #expect(rendered.contains("native_object="))
    }

    /// **La seule exception, et elle est motivée.** Un marchand est une
    /// entreprise, pas une personne : le journaliser permet de repérer une
    /// panne concentrée sur un commerçant sans désigner qui a payé chez lui.
    @Test("Le marchand reste en clair, seul de sa catégorie")
    func merchantStaysReadable() {
        let rendered = context(merchantID: "merchant-42").description
        #expect(rendered.contains("merchant_id=merchant-42"))
    }

    // MARK: - Hachage

    /// Le hachage doit être **stable** entre appareils et sessions : deux logs
    /// du même objet doivent se recouper, sinon les journaux ne servent à rien.
    @Test("Le hachage est stable pour une même valeur")
    func hashIsStable() {
        let first = FinanceLogContext(correlationID: CorrelationId(),
                                      financialObjectID: "same-id", operation: "x")
        let second = FinanceLogContext(correlationID: CorrelationId(),
                                       financialObjectID: "same-id", operation: "y")
        #expect(first.financialObjectIDHash == second.financialObjectIDHash)
        #expect(first.financialObjectIDHash != nil)
    }

    @Test("Deux valeurs différentes donnent deux empreintes différentes")
    func hashDiscriminates() {
        let a = FinanceLogContext(correlationID: CorrelationId(),
                                  financialObjectID: "id-a", operation: "x")
        let b = FinanceLogContext(correlationID: CorrelationId(),
                                  financialObjectID: "id-b", operation: "x")
        #expect(a.financialObjectIDHash != b.financialObjectIDHash)
    }

    // MARK: - Champs

    /// Une clé absente se filtre côté agrégateur ; une chaîne `"nil"` se
    /// confond avec une valeur.
    @Test("Les champs absents sont omis, jamais rendus \"nil\"")
    func absentFieldsAreOmitted() {
        let minimal = FinanceLogContext(correlationID: CorrelationId(),
                                        financialObjectID: nil, operation: "create")
        let fields = minimal.fields

        #expect(fields["operation"] == "create")
        #expect(fields["correlation_id"] != nil)
        #expect(fields["merchant_id"] == nil)
        #expect(fields["order"] == nil)
        #expect(!minimal.description.contains("nil"))
    }

    /// Les §23 exigent la corrélation et la causation côte à côte : l'une
    /// regroupe des appels, l'autre dit lequel a provoqué lequel.
    @Test("Corrélation, trace et causation coexistent")
    func correlationTraceAndCausationCoexist() {
        let fields = context().fields
        #expect(fields["correlation_id"] != nil)
        #expect(fields["trace_id"] == "trace-1")
        #expect(fields["causation_id"] == "cause-1")
    }

    /// Le raccourci marchand garde la discipline : marchand en clair, reste
    /// haché.
    @Test("Le contexte marchand hache tout sauf le marchand")
    func merchantContextKeepsDiscipline() {
        let idempotency = IdempotencyContext.new(deviceID: "device-xyz")
        let logged = FinanceLogContext(
            merchantID: "m-1", idempotency: idempotency,
            operation: "merchant_payment", orderID: "order-raw", invoiceID: "invoice-raw"
        )
        let rendered = logged.description

        #expect(rendered.contains("merchant_id=m-1"))
        #expect(!rendered.contains("order-raw"))
        #expect(!rendered.contains("invoice-raw"))
        #expect(!rendered.contains("device-xyz"))
    }

    /// Le contexte construit depuis une idempotence en porte l'empreinte —
    /// sinon la corrélation entre une tentative et son log serait perdue.
    @Test("Un contexte d'idempotence porte l'empreinte de sa clé")
    func idempotencyContextCarriesHash() {
        let idempotency = IdempotencyContext.new(deviceID: "d")
        let logged = FinanceLogContext(idempotency: idempotency, operation: "create")
        #expect(logged.idempotencyKeyHash != nil)
        #expect(!logged.description.contains(idempotency.key))
    }

    // MARK: - Conformité à la politique

    /// L'invariant qu'un champ ajouté à la hâte casserait en silence : rien de
    /// ce que porte le contexte n'excède ce que la politique autorise vers la
    /// télémétrie.
    @Test("Le contexte reste journalisable au regard de la politique")
    func contextStaysLoggable() {
        #expect(context(merchantID: "m-1", orderID: "o-1").isLoggable())

        let classes = context().carriedDataClasses
        #expect(classes.allSatisfy { $0 <= .conversational })
        #expect(!classes.contains(.secret))
        #expect(!classes.contains(.highlySensitive))
    }

    /// Une politique qui interdirait la télémétrie doit rendre le contexte
    /// non journalisable — la vérification ne doit pas être une formalité.
    @Test("Une politique restrictive rend le contexte non journalisable")
    func restrictivePolicyBlocksLogging() {
        struct DenyAll: DataExposurePolicy {
            func canExpose(dataClass: FinancialDataClass, recipient: Recipient,
                           purpose: Purpose) -> Bool { false }
        }
        #expect(!context().isLoggable(under: DenyAll()))
    }
}
