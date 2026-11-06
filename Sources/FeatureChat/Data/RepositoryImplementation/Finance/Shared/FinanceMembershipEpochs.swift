//
//  FinanceMembershipEpochs.swift
//  FeatureChat
//
//  Époque d'appartenance par conversation — INTEGRATION_CHAT_FINANCE-2.md §0.5.
//

import Foundation

/// Ce que le serveur sait de notre appartenance à chaque conversation.
///
/// Chat Core verrouille les mutations financières sur deux faits : être membre
/// de la conversation (`CF_014` sinon) et porter l'**époque** courante de cette
/// appartenance en `X-Membership-Epoch` (`CF_074` si elle est absente ou
/// périmée). L'époque change quand l'appartenance change — départ, exclusion,
/// réintégration — et une requête qui porte l'ancienne est refusée : c'est ce
/// qui empêche une opération préparée avant une exclusion de s'exécuter après.
///
/// Le registre est synchrone parce que l'en-tête se pose à la construction de
/// la requête, là où rien n'attend. Il ne survit pas au lancement : une époque
/// qu'on ne connaît pas se lit au serveur, elle ne se devine pas.
final class FinanceMembershipEpochs: @unchecked Sendable {

    static let shared = FinanceMembershipEpochs()

    private let lock = NSLock()
    private var epochs: [String: Int] = [:]

    init() {}

    /// L'époque connue de cette conversation, ou `nil` si elle ne l'est pas.
    ///
    /// `nil` ⇒ l'en-tête n'est pas posé. Inventer une valeur ferait refuser la
    /// requête par `CF_074` en affirmant une époque fausse ; l'omettre laisse le
    /// serveur décider avec ce qu'il a.
    func epoch(for conversationID: String) -> Int? {
        guard !conversationID.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return epochs[conversationID]
    }

    /// Retient l'époque rendue par le serveur.
    ///
    /// Jamais en arrière : une réponse plus ancienne arrivée après une plus
    /// récente ne doit pas rétablir une époque déjà dépassée.
    func remember(_ epoch: Int, for conversationID: String) {
        guard !conversationID.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if let known = epochs[conversationID], known >= epoch { return }
        epochs[conversationID] = epoch
    }

    /// Oublie ce qu'on croyait savoir — après un `CF_074`, la prochaine lecture
    /// rapporte l'époque courante.
    func forget(_ conversationID: String) {
        lock.lock()
        defer { lock.unlock() }
        epochs.removeValue(forKey: conversationID)
    }

    /// Déconnexion, changement de compte.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        epochs.removeAll()
    }
}
