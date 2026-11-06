//
//  FinancialObjectStore.swift
//  FeatureChat
//
//  Garde de version des objets financiers — tâche 5.1.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.2.

import Foundation
import WaanguCoreKit

/// État courant des objets financiers visibles dans les conversations.
///
/// **Seul endroit du Chat où l'état d'un objet financier change.** Tout le reste
/// — MQTT, sync, réponse HTTP, push — passe par `apply`, et `apply` refuse toute
/// révision qui n'est pas strictement plus récente.
///
/// Sans ce point de passage unique, chaque site d'écriture devrait se souvenir de
/// comparer les versions ; il suffit qu'un seul oublie pour qu'un `processing`
/// retardataire écrase un `confirmed`.
public actor FinancialObjectStore {

    /// Objets connus, indexés par identité (type + id), pas par référence :
    /// deux révisions du même objet doivent se retrouver à la même place.
    private var objects: [String: FinancialCardPayload] = [:]

    /// Identités dont la charge courante est un écho local, pas une vérité backend.
    ///
    /// Un écho local est ce que le client affiche entre l'envoi d'une opération et
    /// la réponse qui fait autorité. Il ne porte **aucune** révision qui lui soit
    /// propre : il réutilise celle de l'objet backend dont il dérive. C'est ce qui
    /// permet de ne jamais fabriquer de version — et donc de ne jamais rendre
    /// inapplicable la correction backend qui suivra.
    private var localEchoes: Set<String> = []

    /// Nombre de transitions refusées par la machine à états.
    ///
    /// **Compteur distinct de `rejectedStaleCount`, et ce n'est pas un détail.**
    /// Une révision périmée signale un désordre d'événements côté transport ;
    /// une transition refusée signale que quelqu'un affirme une évolution
    /// impossible — bug backend, rejeu croisé entre objets, ou service tiers mal
    /// corrélé. Mélanger les deux ferait pointer la meilleure alerte du
    /// dispositif vers la mauvaise cause.
    public private(set) var forbiddenTransitionCount = 0

    /// Nombre de révisions rejetées pour cause de péremption.
    ///
    /// Exposé parce que c'est le signal d'observabilité clé du Bloc 1 : un taux
    /// non nul révèle un désordre d'événements côté transport, invisible autrement.
    public private(set) var rejectedStaleCount = 0

    /// Nombre de charges refusées parce qu'issues d'une session précédente.
    ///
    /// Compteur distinct : une valeur non nulle signale une fuite potentielle
    /// entre comptes, pas un désordre de transport.
    public private(set) var foreignSessionRejectedCount = 0

    /// Identifie la session courante. Change à chaque connexion de compte.
    private var sessionToken = UUID()

    /// Jeton à relever avant une requête, à repasser à ``apply(_:session:)``.
    public var currentSessionToken: UUID { sessionToken }

    /// Ouvre une session : purge l'état précédent et invalide les réponses en vol.
    ///
    /// L'ordre compte. Le jeton est remplacé **avant** la purge : une réponse
    /// qui arriverait pendant celle-ci porte déjà l'ancien jeton et sera
    /// refusée, au lieu d'être écrite juste après le nettoyage.
    ///
    /// - Parameter erasingPersistence: `false` à l'ouverture d'une session
    ///   **restaurée** au lancement. La persistance est rangée par compte : la
    ///   garder ne peut rien montrer à un autre compte, et l'effacer détruirait
    ///   précisément ce que le lancement doit reprendre — un paiement laissé en
    ///   vol par un kill.
    public func beginSession(erasingPersistence: Bool = true) {
        sessionToken = UUID()
        clear(erasingPersistence: erasingPersistence)
    }

    /// Conserve l'état entre deux lancements — GAP-15.
    ///
    /// `nil` ⇒ magasin en mémoire seule, comportement d'origine. La
    /// réconciliation au démarrage à froid ne trouve alors rien à reprendre.
    private let persistence: (any FinancialObjectPersisting)?

    /// Abonnés au flux de changements — lot 1.4.
    ///
    /// `onChange` est une injection unique : un seul consommateur, décidé à la
    /// construction. La timeline, une vue de détail ouverte et la projection
    /// persistée en veulent trois à la fois. Un flux multi-abonnés évite que
    /// chacun se construise son propre cache — ce qui créerait la deuxième
    /// source d'état financier que le plan interdit.
    private var changeSubscribers: [UUID: AsyncStream<FinancialCardPayload>.Continuation] = [:]

    private let onChange: @Sendable (FinancialCardPayload) async -> Void
    private let onStaleRejected: @Sendable (FinancialReference, Int) async -> Void
    private let onForbiddenTransition: @Sendable (FinancialReference, String) async -> Void

    public init(
        persistence: (any FinancialObjectPersisting)? = nil,
        onChange: @escaping @Sendable (FinancialCardPayload) async -> Void = { _ in },
        onStaleRejected: @escaping @Sendable (FinancialReference, Int) async -> Void = { _, _ in },
        onForbiddenTransition: @escaping @Sendable (FinancialReference, String) async -> Void = { _, _ in }
    ) {
        self.persistence = persistence
        self.onChange = onChange
        self.onStaleRejected = onStaleRejected
        self.onForbiddenTransition = onForbiddenTransition
    }

    // MARK: - Lecture

    public func current(for reference: FinancialReference) -> FinancialCardPayload? {
        objects[reference.identityKey]
    }

    public func currentVersion(for reference: FinancialReference) -> Int? {
        objects[reference.identityKey]?.reference.version
    }

    public var allObjects: [FinancialCardPayload] { Array(objects.values) }

    /// Objets qu'une réconciliation doit reprendre.
    public var needingReconciliation: [FinancialCardPayload] {
        objects.values.filter(\.needsReconciliation)
    }

    // MARK: - Écriture

    /// Applique une révision si et seulement si elle est plus récente.
    ///
    /// - Returns: `true` si l'état a changé.
    ///
    /// Une révision identique est refusée au même titre qu'une plus ancienne :
    /// un événement rejoué porte la même version que celui déjà appliqué, et le
    /// réappliquer relancerait les effets de bord attachés au changement
    /// (animation, notification, analytics) sans qu'aucune donnée n'ait bougé.
    @discardableResult
    public func apply(_ incoming: FinancialCardPayload) async -> Bool {
        await apply(incoming, session: nil)
    }

    /// Applique une charge en vérifiant qu'elle appartient à la session courante
    /// — lot 2.5.
    ///
    /// - Parameter session: jeton relevé **avant** l'appel réseau. `nil` saute
    ///   le contrôle, pour les appelants qui n'émettent pas de requête (MQTT,
    ///   sync, hydratation) et dont la charge n'a pas pu traverser un
    ///   changement de compte.
    ///
    /// Une réponse partie sous le compte A et reçue après connexion de B doit
    /// être jetée : l'écrire afficherait les paiements de A dans les
    /// conversations de B. Annuler la requête en vol ne suffit pas — une
    /// réponse déjà décodée n'est plus annulable, elle ne peut qu'être refusée
    /// à l'écriture.
    @discardableResult
    public func apply(_ incoming: FinancialCardPayload, session: UUID?) async -> Bool {
        if let session, session != sessionToken {
            foreignSessionRejectedCount += 1
            return false
        }
        let key = incoming.reference.identityKey

        guard let existing = objects[key] else {
            // Premier contact avec cet objet : rien à comparer.
            //
            // Persisté comme les suivants — lot 2.1. Ce chemin ne le faisait
            // pas, et c'est le plus important de tous : un objet vu une seule
            // fois avant un kill est précisément celui dont l'issue est
            // inconnue. Ne sauvegarder que les révisions *ultérieures* revient
            // à ne rien pouvoir reprendre d'une opération qui n'en a jamais eu.
            objects[key] = incoming
            forgetHydrated(key)
            await persist(incoming)
            await broadcast(incoming)
            return true
        }

        // Un écho local ne fait pas autorité : toute vérité backend le remplace,
        // quelle que soit la comparaison de versions. Sans cette porte, l'écho
        // partagerait la révision de l'objet dont il dérive et bloquerait par
        // égalité la première réponse authentique.
        if localEchoes.contains(key) {
            localEchoes.remove(key)
            objects[key] = incoming
            forgetHydrated(key)
            // La vérité backend qui remplace un écho est un état à conserver ;
            // l'écho lui-même ne l'était pas.
            await persist(incoming)
            await broadcast(incoming)
            return true
        }

        guard incoming.reference.supersedes(existing.reference) else {
            rejectedStaleCount += 1
            await onStaleRejected(incoming.reference, existing.reference.version)
            return false
        }

        // La révision est plus récente. Reste à savoir si l'évolution qu'elle
        // décrit est possible : « plus récent » et « licite » sont deux
        // questions distinctes, et seule la première était posée jusqu'ici.
        switch FinancialObjectStateMachine.verdict(from: existing.status, to: incoming.status) {
        case .allowed, .unknown:
            // `unknown` passe délibérément : une transition que cette version ne
            // sait pas classer est requêtée, pas bloquée. Un client déployé ne
            // doit pas figer un état introduit après lui.
            break

        case .forbidden(let reason):
            forbiddenTransitionCount += 1
            await onForbiddenTransition(incoming.reference, reason)
            // L'état courant est conservé. On ne choisit pas entre deux vérités
            // contradictoires : c'est au backend de trancher, via réconciliation.
            return false
        }

        objects[key] = incoming
        await persist(incoming)
        await broadcast(incoming)
        return true
    }

    /// Affiche l'état optimiste d'une opération que le client vient d'émettre.
    ///
    /// À n'utiliser que lorsque le backend n'a pas encore rendu de révision pour
    /// cette étape. La charge réutilise la référence — donc la version — de
    /// l'objet dont elle dérive : le garde de version n'a rien de nouveau à
    /// comparer, et rien de faux à mémoriser.
    ///
    /// La prochaine charge backend pour cette identité l'écrase sans condition.
    ///
    /// - Returns: `true` si l'état affiché a changé.
    ///
    /// - Parameter persisting: `true` pour l'**inscription avant soumission**
    ///   d'une opération qui peut déplacer de l'argent. L'écho reste remplacé
    ///   sans condition par la première vérité backend, mais il survit à un kill :
    ///   au lancement suivant, il est relu du disque et requêté. Sans cela, une
    ///   opération tuée en vol ne laissait aucune trace, et l'utilisateur la
    ///   refaisait sous une clé neuve — second débit.
    @discardableResult
    public func applyLocalEcho(_ incoming: FinancialCardPayload,
                               persisting: Bool = false) async -> Bool {
        let key = incoming.reference.identityKey

        // Un écho ne recouvre jamais une révision backend plus récente que
        // l'objet dont il dérive — sinon un événement arrivé pendant la
        // confirmation serait perdu.
        if let existing = objects[key],
           !localEchoes.contains(key),
           existing.reference.version > incoming.reference.version {
            return false
        }

        objects[key] = incoming
        localEchoes.insert(key)
        if persisting { await persist(incoming) }
        await broadcast(incoming)
        return true
    }

    // MARK: - Observation (lot 1.4)

    /// Flux des charges retenues.
    ///
    /// N'émet que ce que le magasin a **accepté** : une révision périmée ou une
    /// transition interdite ne produit rien. Un abonné peut donc afficher ce
    /// qu'il reçoit sans refaire la comparaison de versions — refaire ce
    /// contrôle ailleurs, c'est l'occasion de le faire différemment.
    public func changes() -> AsyncStream<FinancialCardPayload> {
        let (stream, continuation) = AsyncStream<FinancialCardPayload>.makeStream()
        let id = UUID()
        changeSubscribers[id] = continuation

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        changeSubscribers.removeValue(forKey: id)
    }

    /// Notifie l'injection historique **et** les abonnés du flux.
    ///
    /// Les deux, parce que `onChange` reste le point d'injection de la
    /// télémétrie déjà câblée : la remplacer casserait le comptage sans rien
    /// apporter.
    private func broadcast(_ payload: FinancialCardPayload) async {
        await onChange(payload)
        for continuation in changeSubscribers.values {
            continuation.yield(payload)
        }
    }

    /// Met à jour la **seule vérification**, à révision inchangée.
    ///
    /// Répond au cas que `apply` ne peut pas traiter sans se contredire : une
    /// clé de signature installée après coup, ou un simple rafraîchissement,
    /// doit pouvoir faire passer une carte de « non vérifiée » à « vérifiée »
    /// sans que le backend ait produit une nouvelle révision.
    ///
    /// `apply` refuse l'égalité de révision, et c'est correct — un événement
    /// rejoué porte la même version et ne doit pas relancer les effets de bord.
    /// Mais une revalidation authentique porte elle aussi la même version. Les
    /// distinguer ne peut pas se faire sur la révision : cela se fait sur **ce
    /// qui a changé**. Ici, seule la vérification a le droit de bouger.
    ///
    /// Un montant, une devise ou un statut différent à révision égale n'est pas
    /// une revalidation : c'est une contradiction, et elle est refusée. Deux
    /// vérités divergentes sous la même révision se tranchent par
    /// réconciliation, jamais par écrasement.
    ///
    /// - Returns: `true` si la vérification a effectivement changé.
    @discardableResult
    public func revalidate(_ incoming: FinancialCardPayload) async -> Bool {
        let key = incoming.reference.identityKey

        guard let existing = objects[key] else { return false }
        guard existing.reference.identifies(incoming.reference) else { return false }
        guard existing.reference.version == incoming.reference.version else { return false }

        // Une revalidation ne change rien d'autre que le verdict.
        guard existing.status == incoming.status,
              existing.amount == incoming.amount,
              existing.currency == incoming.currency else { return false }

        // Rien de neuf : ne pas notifier pour ne pas relancer les effets de bord.
        guard existing.verification != incoming.verification else { return false }

        objects[key] = incoming
        await persist(incoming)
        await broadcast(incoming)
        return true
    }

    /// Note qu'une lecture serveur a rendu **la même** révision.
    ///
    /// Sans cela, un objet relu sans changement gardait l'heure de sa lecture
    /// précédente : le délai de grâce de la réconciliation ne s'écoulait jamais
    /// et l'objet était repris à chaque passe. Rien d'autre ne change — pas de
    /// diffusion, rien à rafraîchir à l'écran.
    public func markChecked(_ reference: FinancialReference, at date: Date = Date()) {
        let key = reference.identityKey
        guard let existing = objects[key],
              existing.reference.version == reference.version else { return }
        objects[key] = existing.checked(at: date)
    }

    /// `true` si l'état courant de cette identité est un écho local non confirmé.
    /// Exposé pour les tests et pour l'observabilité, jamais pour décider d'un affichage.
    public func isLocalEcho(_ reference: FinancialReference) -> Bool {
        localEchoes.contains(reference.identityKey)
    }

    /// Applique plusieurs révisions, dans n'importe quel ordre.
    ///
    /// L'ordre d'arrivée n'a pas d'importance : seule la plus récente survit.
    /// C'est ce qui rend une resynchronisation en vrac sûre.
    @discardableResult
    public func applyAll(_ incoming: [FinancialCardPayload]) async -> Int {
        var applied = 0
        for payload in incoming {
            if await apply(payload) { applied += 1 }
        }
        return applied
    }

    /// Vide le magasin — déconnexion, changement de compte.
    ///
    /// Obligatoire au changement de compte : conserver les objets du compte
    /// précédent afficherait les paiements de quelqu'un d'autre.
    /// Ce que la persistance a retenu du lancement précédent.
    ///
    /// N'écrase jamais un objet déjà présent : la mémoire est plus fraîche que
    /// le disque, et une hydratation tardive ne doit pas ramener un état ancien.
    public func hydrate() async {
        guard let persistence else { return }
        // Un état final ne se reprend pas : le requêter à chaque lancement
        // coûterait une lecture par paiement jamais clos, sans rien apprendre.
        for stored in await persistence.load()
        where objects[stored.identityKey] == nil
            && PaymentStatus(rawValue: stored.status)?.isTerminal != true {
            hydratedIdentities.insert(stored.identityKey)
            hydratedObjects[stored.identityKey] = stored
        }
    }

    /// Les références restaurées, prêtes à être requêtées — lot 2.2.
    ///
    /// `hydratedIdentities` ne portait que des clés `"type:id"`, dont on ne peut
    /// pas reconstruire une ``FinancialReference`` : il manquait le type
    /// décodé et la révision. Une liste sans consommateur possible n'est pas une
    /// restauration.
    ///
    /// La corrélation est **neuve** à dessein : elle identifie une opération,
    /// pas un objet. Rejouer celle du lancement précédent ferait remonter deux
    /// requêtes distinctes sous la même trace.
    public var hydratedReferences: [FinancialReference] {
        hydratedObjects.values.compactMap { stored in
            guard let type = FinancialObjectType(rawValue: stored.type) else { return nil }
            return FinancialReference(
                type: type,
                id: stored.id,
                version: stored.version,
                correlationID: CorrelationId()
            )
        }
    }

    /// Identités connues du disque mais dont la charge n'a pas encore été relue.
    ///
    /// Elles ne portent pas d'affichage — seulement de quoi savoir qu'il faut
    /// les requêter. Reconstruire une carte depuis le disque afficherait un état
    /// daté comme s'il était courant.
    public private(set) var hydratedIdentities: Set<String> = []

    /// Ce que le disque a rendu, conservé le temps de le requêter.
    private var hydratedObjects: [String: PersistedFinancialObject] = [:]

    private func persist(_ payload: FinancialCardPayload) async {
        guard let persistence else { return }
        await persistence.save(PersistedFinancialObject(
            type: payload.reference.type.rawValue,
            id: payload.reference.id,
            version: payload.reference.version,
            status: payload.status.rawValue,
            lastKnownAt: payload.lastRefreshedAt
        ))
    }

    /// Une identité relue du disque a reçu sa vérité backend : elle n'est plus
    /// à restaurer. Sans ce retrait, chaque passe de restauration la requêtait
    /// de nouveau.
    private func forgetHydrated(_ key: String) {
        hydratedObjects[key] = nil
        hydratedIdentities.remove(key)
    }

    /// Retire un objet — et seulement lui — de la mémoire et du disque.
    ///
    /// Sert au refus serveur : l'inscription faite juste avant l'appel ne
    /// correspond à aucune opération.
    public func discard(_ reference: FinancialReference) {
        let key = reference.identityKey
        objects[key] = nil
        localEchoes.remove(key)
        forgetHydrated(key)
        Task { [persistence] in
            await persistence?.remove(type: reference.type.rawValue, id: reference.id)
        }
    }

    public func clear(erasingPersistence: Bool = true) {
        hydratedIdentities.removeAll()
        hydratedObjects.removeAll()
        objects.removeAll()
        localEchoes.removeAll()
        rejectedStaleCount = 0
        forbiddenTransitionCount = 0
        guard erasingPersistence else { return }
        Task { [persistence] in await persistence?.clear() }
    }
}
