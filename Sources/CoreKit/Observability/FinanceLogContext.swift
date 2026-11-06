//
//  FinanceLogContext.swift
//  CoreKit
//
//  Contexte journalisable d'une opération financière.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.4 et §10.

import Foundation
import CryptoKit

/// Ce qu'il est permis de journaliser au sujet d'une opération financière.
///
/// Le type ne se contente pas de *recommander* la prudence : il rend l'imprudence
/// impossible à exprimer. L'identifiant d'objet financier n'est accessible nulle
/// part sous sa forme brute — il est haché à la construction et la valeur d'origine
/// n'est jamais conservée. Un site d'appel ne peut donc pas le logger par
/// inadvertance, même en interpolant la structure entière.
///
/// Interdits explicites, jamais présents ici : PAN, CVV, tokens d'accès ou de
/// rafraîchissement, données biométriques, données KYC, URL de deep link complète,
/// et le montant lorsque la politique de confidentialité l'interdit.
public struct FinanceLogContext: Sendable, CustomStringConvertible {

    /// Corrèle l'opération à travers les services. Sûr à journaliser : sans valeur
    /// pour qui ne dispose pas déjà des logs serveur.
    public let correlationID: CorrelationId

    /// Empreinte tronquée de l'identifiant d'objet financier.
    ///
    /// Suffisante pour recouper deux lignes de log entre elles, inutilisable pour
    /// interroger une API. `nil` avant qu'un objet n'existe — au moment de créer
    /// une intention, par exemple.
    public let financialObjectIDHash: String?

    /// Nature de l'objet. Ne révèle rien d'identifiant.
    public let objectType: FinancialObjectType?

    /// Révision de l'objet au moment du log. Rend lisible un désordre d'événements
    /// dans un fil de logs.
    public let objectVersion: Int?

    /// Nom court de l'opération : `"create_intent"`, `"confirm"`, `"reconcile"`.
    /// Valeur fermée côté appelant, jamais une chaîne construite depuis une entrée
    /// utilisateur ou une réponse serveur.
    public let operation: String

    // MARK: - Identifiants du Bloc 6 (§23)

    /// Trace distribuée. Sûre à journaliser : elle ne désigne qu'un chemin
    /// d'exécution, pas une personne.
    public let traceID: String?

    /// Ce qui a **causé** cette opération.
    ///
    /// Distinct de la corrélation : celle-ci regroupe des appels, la causation
    /// dit lequel a provoqué lequel. Lors d'un incident, c'est la différence
    /// entre « ces dix requêtes partagent une corrélation » et « cette
    /// confirmation vient de ce rejeu ».
    public let causationID: String?

    /// Empreinte de la clé d'idempotence.
    ///
    /// **Hachée, jamais brute.** La clé contient l'identifiant d'appareil —
    /// `IdempotencyContext.new` la compose ainsi — et la journaliser en clair
    /// permettrait de suivre un appareil à travers tous les logs.
    public let idempotencyKeyHash: String?

    /// Identifiant marchand, **en clair**.
    ///
    /// Un marchand est une entreprise, pas une personne : le journaliser ne
    /// désigne personne, et permet de repérer une panne concentrée sur un
    /// commerçant. C'est le seul identifiant de cette liste qui ne soit pas haché.
    public let merchantID: String?

    /// Empreintes des objets du Bloc 6.
    ///
    /// Tous hachés : commande, facture, transaction carte et objet de mini-app
    /// désignent l'activité d'une personne, et se recoupent avec le reste des
    /// logs pour la reconstituer.
    public let orderIDHash: String?
    public let invoiceIDHash: String?
    public let cardTransactionIDHash: String?
    public let nativeObjectIDHash: String?

    // MARK: - Construction

    /// Construit un contexte à partir d'un identifiant brut, qui est haché
    /// immédiatement puis abandonné.
    public init(
        correlationID: CorrelationId,
        financialObjectID: String?,
        objectType: FinancialObjectType? = nil,
        objectVersion: Int? = nil,
        operation: String,
        traceID: String? = nil,
        causationID: String? = nil,
        idempotencyKey: String? = nil,
        merchantID: String? = nil,
        orderID: String? = nil,
        invoiceID: String? = nil,
        cardTransactionID: String? = nil,
        nativeObjectID: String? = nil
    ) {
        self.correlationID = correlationID
        self.financialObjectIDHash = financialObjectID.map(Self.hash)
        self.objectType = objectType
        self.objectVersion = objectVersion
        self.operation = operation
        self.traceID = traceID
        self.causationID = causationID
        // Hachés à la construction, puis les valeurs brutes sont abandonnées :
        // ce qui n'existe plus en mémoire ne peut pas fuir dans une trace.
        self.idempotencyKeyHash = idempotencyKey.map(Self.hash)
        self.merchantID = merchantID
        self.orderIDHash = orderID.map(Self.hash)
        self.invoiceIDHash = invoiceID.map(Self.hash)
        self.cardTransactionIDHash = cardTransactionID.map(Self.hash)
        self.nativeObjectIDHash = nativeObjectID.map(Self.hash)
    }

    /// Construit le contexte d'une opération portant sur un objet référencé.
    ///
    /// Voie normale : la référence porte déjà type, version et corrélation, donc
    /// aucun de ces champs ne peut diverger de l'objet réel.
    public init(reference: FinancialReference, operation: String) {
        self.init(
            correlationID: reference.correlationID,
            financialObjectID: reference.id,
            objectType: reference.type,
            objectVersion: reference.version,
            operation: operation
        )
    }

    /// Contexte d'une opération qui n'a pas encore produit d'objet.
    public init(idempotency: IdempotencyContext, operation: String) {
        self.init(
            correlationID: idempotency.correlationID,
            financialObjectID: nil,
            operation: operation,
            idempotencyKey: idempotency.key
        )
    }

    /// Contexte d'une opération marchande — Bloc 6.
    ///
    /// Le marchand reste en clair, tout le reste est haché. C'est ce qui permet
    /// de dire « le prestataire de ce commerçant est tombé » sans dire « cette
    /// personne a payé chez lui ».
    public init(
        merchantID: String,
        idempotency: IdempotencyContext,
        operation: String,
        orderID: String? = nil,
        invoiceID: String? = nil,
        traceID: String? = nil
    ) {
        self.init(
            correlationID: idempotency.correlationID,
            financialObjectID: nil,
            operation: operation,
            traceID: traceID,
            idempotencyKey: idempotency.key,
            merchantID: merchantID,
            orderID: orderID,
            invoiceID: invoiceID
        )
    }

    // MARK: - Hachage

    /// SHA-256 tronqué à 16 caractères hexadécimaux.
    ///
    /// Non salé, volontairement : le hachage doit être stable entre appareils et
    /// entre sessions pour que deux logs du même objet se recoupent. La protection
    /// vient de l'entropie de l'identifiant opaque backend, pas d'un secret local
    /// — un sel par appareil rendrait d'ailleurs les logs incomparables, ce qui
    /// est précisément leur raison d'être.
    ///
    /// Ne pas utiliser sur une valeur à faible entropie : un numéro de téléphone
    /// ou un montant se retrouvent par force brute en quelques secondes.
    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

// MARK: - Rendu

public extension FinanceLogContext {

    /// Représentation destinée aux logs structurés.
    ///
    /// Toute clé absente est omise plutôt que rendue `"nil"` — une clé manquante
    /// se filtre côté agrégateur, une chaîne `"nil"` se confond avec une valeur.
    var fields: [String: String] {
        var out: [String: String] = [
            "correlation_id": correlationID.value,
            "operation": operation
        ]
        if let financialObjectIDHash { out["fin_object"] = financialObjectIDHash }
        if let objectType { out["fin_type"] = objectType.rawValue }
        if let objectVersion { out["fin_version"] = String(objectVersion) }

        // Bloc 6, §23. Tout ce qui sort ici est soit une trace d'exécution,
        // soit une empreinte, soit un identifiant d'entreprise. Aucune valeur
        // ne permet de remonter à une personne à elle seule.
        if let traceID { out["trace_id"] = traceID }
        if let causationID { out["causation_id"] = causationID }
        if let idempotencyKeyHash { out["idempotency"] = idempotencyKeyHash }
        if let merchantID { out["merchant_id"] = merchantID }
        if let orderIDHash { out["order"] = orderIDHash }
        if let invoiceIDHash { out["invoice"] = invoiceIDHash }
        if let cardTransactionIDHash { out["card_tx"] = cardTransactionIDHash }
        if let nativeObjectIDHash { out["native_object"] = nativeObjectIDHash }
        return out
    }

    /// Les classes de données que ce contexte peut porter.
    ///
    /// Sert à vérifier, en test comme à l'exécution, qu'un contexte reste dans
    /// ce que la politique autorise vers ``Recipient/telemetry``. Sans cette
    /// borne explicite, un champ ajouté demain passerait sans revue.
    var carriedDataClasses: Set<FinancialDataClass> {
        // Corrélation, trace, causation : des chemins d'exécution.
        // Empreintes : irréversibles. Marchand : une entreprise.
        // Rien ici n'excède le conversationnel.
        [.publicInfo, .conversational]
    }

    /// Ce contexte est-il journalisable au regard de la politique ?
    ///
    /// Vérifié plutôt que supposé : c'est le genre d'invariant qu'un champ
    /// ajouté à la hâte casse en silence.
    func isLoggable(under policy: any DataExposurePolicy = DefaultDataExposurePolicy()) -> Bool {
        carriedDataClasses.allSatisfy {
            policy.canExpose(dataClass: $0, recipient: .telemetry, purpose: .diagnostics)
        }
    }

    var description: String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

// MARK: - Deep links

public extension FinanceLogContext {

    /// Ce qu'il est permis de journaliser d'une URL entrante.
    ///
    /// Rend l'hôte et le **nom** des segments de chemin, jamais leurs valeurs, et
    /// jamais la query string. `waangu://chat/financial-object/abc123?token=xyz`
    /// devient `waangu://chat/financial-object/<redacted>`.
    ///
    /// Existe parce que journaliser `url` en entier — ce que faisait
    /// `AppCoordinator.handleDeepLink` — expose l'identifiant d'objet financier
    /// dans les sysdiagnose et les rapports de crash.
    static func redactedURL(_ url: URL) -> String {
        let scheme = url.scheme ?? "?"
        let host = url.host ?? "?"
        let segments = url.pathComponents.filter { $0 != "/" }

        // Le premier segment nomme la ressource et fait partie du routage ;
        // les suivants sont des identifiants.
        let rendered = segments.enumerated().map { index, segment in
            index == 0 ? segment : "<redacted>"
        }.joined(separator: "/")

        return rendered.isEmpty ? "\(scheme)://\(host)" : "\(scheme)://\(host)/\(rendered)"
    }
}
