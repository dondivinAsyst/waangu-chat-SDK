//
//  FinancialCardRevalidation.swift
//  FeatureChat
//
//  Bloc 1 §8 — « Device B : ouvre la conversation → GET financial-object ».
//

import Foundation
import WaanguCoreKit

/// Les cartes d'une conversation qu'il faut relire au serveur à l'ouverture.
///
/// Une carte n'évolue que par un pointeur MQTT. Un pointeur manqué — hors
/// ligne, application tuée — la laissait sur son dernier état connu ; le
/// Bloc 1 §11.2 (« événement manquant → `refresh` comble le trou ») demande
/// qu'une lecture serveur le rattrape.
///
/// Ne relit que ce qui peut encore bouger ou n'a pas été prouvé : une carte
/// vérifiée dans un état final n'a plus rien à apprendre du serveur.
enum FinancialCardRevalidation {

    /// Plafond par ouverture : les plus récentes d'abord. Une longue
    /// conversation ne doit pas déclencher une lecture par paiement jamais fait.
    static let limit = 20

    static func references(in messages: [MessageDataItem]) -> [FinancialReference] {
        var seen = Set<String>()
        var references: [FinancialReference] = []
        for message in messages.reversed() where message.typeMessage == .ISMONEY {
            guard let reference = reference(for: message),
                  seen.insert(reference.id).inserted else { continue }
            references.append(reference)
            if references.count == limit { break }
        }
        return references
    }

    static func reference(for message: MessageDataItem) -> FinancialReference? {
        if let payload = message.message.financial {
            return payload.reference.type.isKnown && needsServerRead(payload) ? payload.reference : nil
        }
        // Carte d'attente : la référence, et la nature si le message l'a portée.
        // Sans nature, rien n'est lu — la deviner transformait une demande en
        // paiement. La révision vient du serveur.
        guard let id = message.transactionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              let type = message.message.financialObjectType, type.isKnown else { return nil }
        return FinancialReference(type: type, id: id, version: 0, correlationID: CorrelationId())
    }

    static func needsServerRead(_ payload: FinancialCardPayload) -> Bool {
        payload.verification != .verified || !payload.status.isTerminal
    }
}
