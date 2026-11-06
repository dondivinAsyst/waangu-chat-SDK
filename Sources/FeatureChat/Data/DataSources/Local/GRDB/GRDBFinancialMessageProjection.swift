//
//  GRDBFinancialMessageProjection.swift
//  FeatureChat
//
//  Bloc 1, lot 1.4 — la révision retenue par le store, recopiée dans les messages.
//

import Foundation
import WaanguCoreKit

/// ``FinancialMessageProjecting`` sur la table des messages du chat.
///
/// La conversation observe `MessageModel` (`GRDBMessageDataSource.observeMessages`) :
/// réécrire la ligne suffit pour que la bulle se redessine, sans canal propre à
/// la finance vers l'interface.
final class GRDBFinancialMessageProjection: FinancialMessageProjecting {

    private let store: any DatabaseRepositoryProtocol

    init(store: any DatabaseRepositoryProtocol) {
        self.store = store
    }

    @discardableResult
    func project(_ payload: FinancialCardPayload) async throws -> Int {
        var rewritten = 0

        for var message in try await messages(referencing: payload.reference.id) {
            // Ne jamais reculer. Le store a déjà tranché, mais deux projections
            // peuvent s'exécuter dans le désordre ; la ligne garde alors la plus
            // récente. À révision égale, on réécrit : seule la vérification peut
            // avoir bougé (`FinancialObjectStore.revalidate`).
            if let stored = message.content.financialObjectVersion,
               stored > payload.reference.version {
                continue
            }
            // Jamais de changement de nature. Une lecture faite sous un type
            // supposé — le pointeur MQTT n'en porte aucun et suppose `PAYMENT` —
            // ne doit pas faire d'une demande d'argent un paiement reçu.
            if let storedType = message.content.financialObjectType,
               storedType != payload.reference.type.rawValue {
                continue
            }

            message.content.applyFinancial(payload)
            message.updatedAt = Date()
            try await store.save(message)
            rewritten += 1
        }

        return rewritten
    }

    /// La nature que le fil connaît déjà pour cet objet, s'il y figure.
    ///
    /// Le pointeur MQTT n'en porte aucune et suppose `PAYMENT` : une demande
    /// était alors relue par `/financial/objects`, et la réponse — typée
    /// paiement — écartée par le garde de nature. Avec la nature du message, la
    /// demande se relit par `/request-money`, et la carte du demandeur suit.
    func storedType(forObjectID objectID: String) async -> FinancialObjectType? {
        guard let messages = try? await messages(referencing: objectID) else { return nil }
        return messages.lazy
            .compactMap { $0.content.financialObjectType.flatMap(FinancialObjectType.init(rawValue:)) }
            .first { $0.isKnown }
    }

    /// Les messages de paiement portant cet identifiant d'objet.
    ///
    /// `paymentRef` n'est pas une colonne : `MessageContentModel` est sérialisé
    /// dans `json_payload`. Le filtre sur `type`, lui indexé, réduit d'abord la
    /// recherche aux seuls messages de paiement ; `json_extract` ne lit ensuite
    /// que ceux-là. `CAST … AS TEXT` : la colonne est un BLOB, que les fonctions
    /// JSON de SQLite refusent tel quel.
    private func messages(referencing objectID: String) async throws -> [MessageModel] {
        try await store.fetch(
            MessageModel.self,
            query: QuerySpec(filter: FilterSpec(
                "type = %@ AND json_extract(CAST(json_payload AS TEXT), '$.content.paymentRef') = %@",
                .string(MessageTypeModel.payment.rawValue),
                .string(objectID)
            ))
        )
    }
}
