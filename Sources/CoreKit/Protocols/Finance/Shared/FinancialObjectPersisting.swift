//
//  FinancialObjectPersisting.swift
//  CoreKit
//
//  Persistance de l'état financier — Bloc 1 §5, Bloc 4 (GAP-15).
//

import Foundation

/// Conserve l'état des objets financiers entre deux lancements.
///
/// **Le défaut que ce contrat ferme.** `FinancialObjectStore` vit en mémoire.
/// La réconciliation au démarrage à froid, câblée depuis le Bloc 1, reprend donc
/// un magasin vide : un paiement laissé en `unknown` par un kill d'application
/// n'est jamais repris, alors que c'est précisément le cas pour lequel la
/// réconciliation existe.
///
/// Ne persiste **aucun secret** : ni code de retrait, ni jeton, ni voucher. La
/// charge d'une carte financière ne contient que ce que le backend a rendu et
/// que l'utilisateur voit déjà à l'écran.
public protocol FinancialObjectPersisting: Sendable {

    /// Relit l'état conservé. Toute erreur donne une liste vide : un magasin
    /// illisible se répare par une réconciliation, pas par un échec au lancement.
    func load() async -> [PersistedFinancialObject]

    /// Enregistre l'état courant d'un objet.
    func save(_ object: PersistedFinancialObject) async

    /// Retire un objet — refus serveur d'une opération inscrite avant l'appel.
    func remove(type: String, id: String) async

    /// Vide tout — déconnexion, changement de compte.
    func clear() async
}

/// Ce qui est conservé d'un objet financier.
///
/// Volontairement plus pauvre que la charge d'affichage : seuls l'identité, la
/// révision, le statut et l'instant de lecture. Tout le reste se relit auprès du
/// backend, et conserver moins réduit d'autant ce qui peut fuir d'un appareil
/// perdu.
public struct PersistedFinancialObject: Codable, Sendable, Hashable {

    public let type: String
    public let id: String
    public let version: Int
    public let status: String

    /// Horodatage **serveur** de la dernière lecture, quand il est connu.
    public let lastKnownAt: Date

    public init(type: String, id: String, version: Int, status: String, lastKnownAt: Date) {
        self.type = type
        self.id = id
        self.version = version
        self.status = status
        self.lastKnownAt = lastKnownAt
    }

    public var identityKey: String { Self.identityKey(type: type, id: id) }

    /// La même identité, sans objet sous la main — pour retirer une ligne.
    public static func identityKey(type: String, id: String) -> String { "\(type):\(id)" }
}

public extension PersistedFinancialObject {

    /// `true` si cet objet doit être repris au démarrage.
    ///
    /// Les états finaux ne sont pas repris : ils ne changeront plus, et les
    /// requêter à chaque lancement produirait une salve d'appels inutiles.
    var needsReconciliationOnLaunch: Bool {
        guard let parsed = PaymentStatus(rawValue: status) else {
            // Un statut que cette version ne connaît pas est repris : c'est le
            // cas d'un client mis à jour après un changement backend, et
            // l'ignorer laisserait un objet dans un état illisible.
            return true
        }
        return !parsed.isTerminal
    }
}
