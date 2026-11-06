//
//  FinanceOperationKeys.swift
//  FeatureChat
//
//  Une clé d'idempotence par opération logique — Bloc 10, §4 et §21.E.
//

import Foundation
import CryptoKit
import WaanguCoreKit

/// Tient les clés d'idempotence des écrans financiers, **une par opération
/// logique**, et les fait survivre à la fermeture de l'écran comme au crash.
///
/// **Le défaut qu'elle corrige.** Trente-six appels de soumission fabriquaient
/// leur clé *à chaque appel*. Le verrou d'écran empêchait le double appui pendant
/// l'envoi, pas la **nouvelle tentative après une erreur** : un délai dépassé,
/// l'utilisateur voit l'échec, appuie de nouveau, et le serveur reçoit une
/// seconde opération qu'il n'a aucun moyen de rapprocher de la première.
///
/// **Pourquoi persistée.** Tenue dans l'état de la vue, la clé disparaissait avec
/// l'écran : fermer, rouvrir et payer de nouveau refabriquait une clé neuve — le
/// même double débit, un geste plus loin. Elle vit donc dans
/// `IdempotencyKeyPreserving`, le registre du Bloc 1 : trousseau, espace de noms
/// par compte, purgé à la déconnexion, clés expirées écartées au chargement.
///
/// **Pourquoi pas une seule clé par écran.** Un même écran conduit plusieurs
/// opérations distinctes — créer un partage, y verser, le clore. Une clé commune
/// ferait écarter la seconde comme doublon de la première.
///
/// **Pourquoi la charge utile fait partie de la portée.** Si l'utilisateur
/// corrige le montant après une erreur, rejouer l'ancienne clé ferait rendre par
/// le serveur l'opération d'avant, sous l'apparence d'une réussite.
///
/// UI debounce ≠ idempotence serveur : ce type fait la seconde.
public actor FinanceOperationKeys {

    private let preserver: (any IdempotencyKeyPreserving)?

    /// Cache du processus. Évite une lecture du trousseau par soumission, et
    /// garde la protection **même si le registre refuse d'enregistrer** — voir
    /// ``key(for:deviceID:)``.
    private var cache: [String: IdempotencyContext] = [:]

    /// Résolutions en cours, par portée.
    ///
    /// Un acteur est réentrant : pendant que la première demande attend le
    /// trousseau, une seconde — le double tap — entre, trouve le cache vide et
    /// fabrique une autre clé. Deux clés, donc deux opérations côté serveur. Les
    /// demandes concurrentes attendent ici la **même** résolution.
    private var pending: [String: Task<IdempotencyContext, Never>] = [:]

    /// - Parameter preserver: `nil` ⇒ protection limitée au processus. C'est le
    ///   cas des aperçus et des tests ; l'application branche le registre réel.
    public init(preserver: (any IdempotencyKeyPreserving)? = nil) {
        self.preserver = preserver
    }

    /// La clé de cette opération — créée au premier appel, **rendue à l'identique
    /// ensuite**, y compris après fermeture de l'écran ou relance de l'app.
    ///
    /// Si le registre refuse d'enregistrer — registre fermé, trousseau
    /// indisponible — la clé reste tenue en mémoire. Ce n'est pas la protection
    /// complète, mais c'est strictement mieux qu'une clé neuve par tentative, qui
    /// était l'état antérieur.
    public func key(for scope: String, deviceID: String) async -> IdempotencyContext {
        if let cached = cache[scope] { return cached }
        if let inFlight = pending[scope] { return await inFlight.value }

        let operationID = Self.operationID(for: scope)
        let preserver = self.preserver
        let resolution = Task<IdempotencyContext, Never> {
            if let resumed = await preserver?.context(for: operationID) { return resumed }
            let fresh = IdempotencyContext.new(deviceID: deviceID)
            try? await preserver?.register(operationID: operationID, context: fresh)
            return fresh
        }
        pending[scope] = resolution
        let context = await resolution.value
        pending[scope] = nil
        cache[scope] = context
        return context
    }

    /// Oublie la clé d'une opération **aboutie**.
    ///
    /// À n'appeler que sur une issue établie côté serveur. Sur une erreur — et à
    /// plus forte raison sur une issue inconnue — la clé doit survivre : c'est
    /// elle qui fait rendre le résultat d'origine à la tentative suivante au lieu
    /// d'en exécuter un second.
    public func release(_ scope: String) async {
        cache[scope] = nil
        await preserver?.release(operationID: Self.operationID(for: scope))
    }

    /// Registre de repli, **partagé** et limité au processus.
    ///
    /// Une instance unique, et non `FinanceOperationKeys()` écrit en ligne : un
    /// repli construit dans un `body` renaîtrait vide à chaque réévaluation de la
    /// vue, et chaque tentative retrouverait une clé neuve — le défaut même que
    /// ce type existe pour corriger.
    public static let processLocal = FinanceOperationKeys()

    /// Nombre de clés tenues en mémoire. Exposé pour les tests.
    public var count: Int { cache.count }

    // MARK: - Portée

    /// Compose une portée à partir de l'opération et de ce qui est soumis.
    ///
    /// Les parties sont jointes par un séparateur qui ne peut pas apparaître
    /// dans un identifiant backend, pour que `("a|b", "c")` et `("a", "b|c")` ne
    /// produisent pas la même portée.
    public nonisolated static func scope(_ operation: String,
                                         _ parts: CustomStringConvertible...) -> String {
        ([operation] + parts.map(\.description)).joined(separator: "\u{1F}")
    }

    /// Identifiant d'opération persisté : **l'empreinte** de la portée, jamais la
    /// portée elle-même.
    ///
    /// Une portée contient la description de la charge utile — montant, nom du
    /// bénéficiaire, numéro. L'écrire telle quelle comme identifiant la ferait
    /// entrer en clair dans le trousseau, où rien ne justifie qu'elle soit.
    /// L'empreinte suffit à retrouver la clé et ne révèle rien.
    public nonisolated static func operationID(for scope: String) -> String {
        let digest = SHA256.hash(data: Data(scope.utf8))
        return "op." + digest.map { String(format: "%02x", $0) }.joined()
    }
}
