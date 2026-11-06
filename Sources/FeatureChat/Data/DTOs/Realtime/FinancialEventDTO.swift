//
//  FinancialEventDTO.swift
//  FeatureChat
//
//  Notification d'évolution d'objet financier — tâche 7.2.
//
//  **BACKEND CONTRACT REQUIRED** — contrat #7.

import Foundation
import WaanguCoreKit

/// Ce que le fil temps réel transporte au sujet d'un objet financier.
///
/// **Ne porte aucun statut.** C'est délibéré, et c'est la différence entre une
/// notification et une vérité : un statut transporté par MQTT arriverait sans
/// garantie d'ordre, sans signature vérifiable et sans corrélation à la requête
/// qui l'a produit. Il serait donc appliqué à l'aveugle.
///
/// Le seul usage licite de cet événement est de déclencher une lecture serveur.
public struct FinancialEventDTO: Codable, Sendable, Equatable {

    public let objectType: String
    public let objectId: String

    /// Révision annoncée.
    ///
    /// Sert uniquement à éviter une lecture inutile : si elle n'est pas
    /// supérieure à la révision connue, rien n'a changé pour ce client. Elle ne
    /// permet **jamais** de mettre à jour l'état — seule la réponse serveur le peut.
    public let version: Int

    public let correlationId: String?

    public init(objectType: String, objectId: String, version: Int, correlationId: String?) {
        self.objectType = objectType
        self.objectId = objectId
        self.version = version
        self.correlationId = correlationId
    }

    /// Référence à requêter, ou `nil` si le type est inconnu de cette version.
    public func toReference() -> FinancialReference? {
        guard let type = FinancialObjectType(rawValue: objectType) else { return nil }
        return FinancialReference(
            type: type,
            id: objectId,
            version: version,
            // Corrélation absente → on en frappe une neuve.
            //
            // **Ne jamais retomber sur `objectId`.** La corrélation est
            // journalisée en clair (`FinanceLogContext.fields`), alors que
            // l'identifiant d'objet y est haché. Aliaser l'un sur l'autre
            // republierait en clair exactement ce que le hachage protège.
            correlationID: correlationId.map(CorrelationId.init(value:)) ?? CorrelationId()
        )
    }
}
