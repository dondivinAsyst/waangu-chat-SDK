//
//  IdempotencyPayloadGuard.swift
//  CoreKit
//
//  Même clé + payload différent = conflit — Bloc 4 §8 (GAP-04).
//

import Foundation
import CryptoKit

/// Empreinte de ce qu'une clé d'idempotence couvre réellement.
///
/// **La clé seule ne suffit pas.** `assertSameKey` vérifie qu'un retry réutilise
/// la clé d'origine — c'est nécessaire et insuffisant. Rien n'empêchait, sous la
/// même clé, d'envoyer un montant ou un bénéficiaire différent : le backend
/// aurait alors rendu la réponse de la **première** opération pour une intention
/// qui n'est plus la même, et l'utilisateur aurait vu confirmé un paiement qu'il
/// n'a pas demandé.
///
/// L'empreinte lie la clé à son contenu. Le conflit devient détectable des deux
/// côtés — localement avant l'envoi, et contractuellement côté serveur.
public enum IdempotencyPayloadGuard {

    /// Empreinte canonique d'un payload de mutation.
    ///
    /// Les clés sont triées : l'ordre de sérialisation JSON n'est pas garanti,
    /// et deux encodages du même contenu doivent donner la même empreinte.
    public static func hash(_ payload: [String: String]) -> String {
        let canonical = payload
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verdict avant émission.
    public enum Verdict: Sendable, Equatable {
        /// Première émission sous cette clé.
        case firstUse
        /// Même clé, même contenu : c'est un retry légitime.
        case sameIntent
        /// Même clé, contenu différent. **Défaut de programmation** : deux
        /// intentions distinctes partagent une clé, ce qui rendrait la réponse
        /// de l'une pour l'autre.
        case conflict(expected: String, provided: String)
    }

    public static func verdict(storedHash: String?, incoming: [String: String]) -> Verdict {
        let incomingHash = hash(incoming)
        guard let storedHash else { return .firstUse }
        return storedHash == incomingHash
            ? .sameIntent
            : .conflict(expected: storedHash, provided: incomingHash)
    }
}
