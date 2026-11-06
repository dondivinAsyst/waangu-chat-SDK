//
//  SyncIntegrity.swift
//  CoreKit
//
//  Curseurs, séquences et frontière transactionnelle — Bloc 8, §15 et §16.
//
//  Ferme P0-4, P0-5, P0-7 et P0-8 de l'audit du Bloc 8.
//

import Foundation

// MARK: - Curseur (§15)

/// Où en est un flux d'événements.
public struct EventCursor: Codable, Sendable, Hashable {

    /// Le flux concerné — une conversation, un compte, un type d'objet.
    public let streamID: String

    /// Position dans ce flux. Monotone croissante côté serveur.
    public let sequence: Int64

    /// Jeton opaque rendu par le serveur, quand il en fournit un.
    ///
    /// Préféré à `sequence` pour repartir : un serveur qui pagine sur autre
    /// chose qu'un entier — un timestamp composite, un identifiant de segment —
    /// ne doit pas être forcé dans un modèle numérique par le client.
    public let opaqueToken: String?

    public init(streamID: String, sequence: Int64, opaqueToken: String? = nil) {
        self.streamID = streamID
        self.sequence = sequence
        self.opaqueToken = opaqueToken
    }
}

/// Un événement portant de quoi être ordonné et dédupliqué.
public protocol VersionedEvent: Sendable {

    /// Identifiant unique de l'événement. Base de la déduplication.
    var eventID: String { get }

    /// Position dans le flux.
    var sequence: Int64 { get }

    /// Version de l'objet après application.
    var objectVersion: Int64 { get }
}

// MARK: - Verdict de séquence (§15)

/// Ce qu'il faut faire d'un événement entrant.
///
/// Le §15 énonce quatre règles ; elles ne sont appliquées nulle part dans le
/// chemin de synchronisation qui tourne. Sans elles, un événement rejoué
/// réapplique son effet et un trou passe inaperçu — les deux silencieusement.
public enum SequenceVerdict: Sendable, Equatable {

    /// À appliquer : c'est le suivant attendu.
    case apply

    /// Déjà vu. À ignorer sans erreur — un rejeu est normal sur un réseau
    /// instable, ce n'est pas une anomalie à remonter.
    case duplicate

    /// Antérieur à l'état local. Ignoré : une version ancienne ne doit jamais
    /// écraser une plus récente.
    case stale

    /// **Trou détecté.** Des événements manquent entre l'état local et
    /// celui-ci. Ne pas appliquer : appliquer un événement dont les
    /// prédécesseurs manquent produit un état que rien ne pourra réconcilier.
    case gap(expected: Int64, received: Int64)

    /// Position incohérente ou inconnue — requêter l'état autoritatif.
    case requery

    public var permitsApplication: Bool { self == .apply }
}

/// Décide du sort d'un événement au vu de l'état local.
///
/// Fonction pure : testable exhaustivement, ce que le §32 (property-based)
/// exige — `apply(e)` deux fois doit égaler `apply(e)` une fois, et c'est ici
/// que la seconde application est arrêtée.
public enum SequenceGuard {

    /// - Parameters:
    ///   - incoming: séquence de l'événement reçu.
    ///   - lastApplied: dernière séquence appliquée localement, `nil` si aucune.
    ///   - seenEventIDs: identifiants déjà appliqués, pour la déduplication.
    ///   - eventID: identifiant de l'événement reçu.
    public static func verdict(
        incoming: Int64,
        lastApplied: Int64?,
        eventID: String,
        seenEventIDs: Set<String>
    ) -> SequenceVerdict {

        // La déduplication par identifiant précède tout raisonnement de
        // position : un même événement peut arriver par MQTT et par l'API avec
        // la même séquence, et ce n'est pas un trou.
        if seenEventIDs.contains(eventID) { return .duplicate }

        guard let lastApplied else {
            // Aucun état local : on ne peut pas juger d'un trou. Le premier
            // événement d'un flux vide est accepté, la synchro initiale ayant
            // établi la base.
            return .apply
        }

        if incoming <= 0 { return .requery }

        if incoming == lastApplied { return .duplicate }
        if incoming < lastApplied { return .stale }
        if incoming == lastApplied + 1 { return .apply }

        return .gap(expected: lastApplied + 1, received: incoming)
    }
}

// MARK: - Validation (§16)

/// Ce que vaut un événement avant même d'être ordonné.
///
/// Le §16 impose `download → validate → apply`. L'étape de validation
/// n'existe pas dans le moteur actuel : un payload malformé est appliqué et
/// échoue au fond, ou pire, s'applique à moitié.
public enum ValidationVerdict: Sendable, Equatable {

    case valid

    /// Structurellement invalide. Rejeté et compté, sans arrêter la page :
    /// un événement corrompu ne doit pas bloquer les suivants.
    case malformed(reason: String)

    /// Valide mais destiné à un autre compte ou tenant.
    ///
    /// **Le cas le plus grave de la liste.** Le §4 (visite 4) en fait une fuite
    /// cross-account. Appliquer un tel événement écrit les données de
    /// quelqu'un d'autre dans la base locale.
    case foreignScope

    public var permitsApplication: Bool { self == .valid }
}

// MARK: - Frontière transactionnelle (§16)

/// Une page d'événements, prête à être appliquée.
///
/// Distincte de ``SyncPage`` (`Protocols/Storage/Sync/SyncPage.swift`), qui est
/// un type de transport : `Codable`, curseur en `String`, sans contrainte
/// d'ordonnancement sur ses éléments. Celle-ci est un type de domaine — ses
/// événements sont ``VersionedEvent``, donc ordonnables, et son curseur est un
/// ``EventCursor`` typé. Les fusionner obligerait le transport à connaître la
/// séquence, ou le domaine à être sérialisable ; ni l'un ni l'autre n'est vrai.
public struct VersionedSyncPage<Event: VersionedEvent>: Sendable {

    public let events: [Event]

    /// Le curseur **après** cette page. N'est persisté qu'au commit.
    public let nextCursor: EventCursor?

    public init(events: [Event], nextCursor: EventCursor?) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

/// La preuve qu'une page a été appliquée et committée.
///
/// Ce type n'existe que pour rendre l'ordre du §16 impossible à inverser.
/// ``SyncCursorPersisting`` ne prend pas un curseur — il prend un reçu. Il n'y
/// a donc **aucune signature** permettant de persister un curseur avant le
/// commit des données, ce qui est la façon dont un curseur en avance sur ses
/// données se crée.
///
/// Ce n'est pas une preuve cryptographique : un appelant déterminé peut
/// fabriquer un reçu. C'est une barrière contre l'erreur, pas contre la
/// malveillance — et l'inversion du §16 est une erreur, jamais une attaque.
public struct CommitReceipt: Sendable, Hashable {

    public let cursor: EventCursor
    public let appliedCount: Int
    public let rejectedCount: Int
    public let committedAt: Date

    public init(cursor: EventCursor, appliedCount: Int,
                rejectedCount: Int, committedAt: Date) {
        self.cursor = cursor
        self.appliedCount = appliedCount
        self.rejectedCount = rejectedCount
        self.committedAt = committedAt
    }
}

/// Applique une page **atomiquement**.
public protocol SyncTransactionBoundary: Sendable {

    associatedtype Event: VersionedEvent

    /// Valide, ordonne, applique et committe en une seule transaction.
    ///
    /// Tout ou rien. Le moteur actuel applique les événements un par un hors
    /// transaction : un crash au troisième d'une page de dix laisse un état
    /// partiel que le curseur, non avancé, fera rejouer — et seule
    /// l'idempotence de chaque delegate, jamais vérifiée, empêche alors le
    /// doublon.
    func applyAtomically(_ page: VersionedSyncPage<Event>) async -> Result<CommitReceipt, SyncError>
}

/// Persiste le curseur, et seulement après un commit.
public protocol SyncCursorPersisting: Sendable {

    /// - Parameter receipt: rendu par ``SyncTransactionBoundary/applyAtomically(_:)``.
    func persist(_ receipt: CommitReceipt) async -> Result<Void, SyncError>

    /// Le curseur courant d'un flux.
    func cursor(for streamID: String) async -> EventCursor?
}

// MARK: - Merge (§17)

/// Marque un type dont deux versions divergentes peuvent être fusionnées
/// localement.
///
/// **Aucun type financier ne doit s'y conformer.** Le §17 interdit le merge
/// local du montant, de la devise, du settlement, du statut de transaction, de
/// la décision Compliance et du permis d'exécution — pour ceux-là, le serveur
/// tranche, toujours.
///
/// `AuthoritativeSync` expose aujourd'hui `ConflictResolution.merge(T)` sur un
/// `T: Syncable` sans contrainte : rien n'empêche un objet financier d'emprunter
/// ce chemin. Le composant étant mort, c'est sans conséquence aujourd'hui, et
/// ce serait une porte ouverte le jour où quelqu'un le câble.
///
/// La conformité est donc **la** décision de sécurité : un brouillon, une
/// préférence d'affichage, un ordre de liste peuvent se fusionner. Un montant,
/// jamais.
public protocol LocallyMergeable: Sendable {

    /// Fusionne deux versions concurrentes de façon déterministe.
    ///
    /// Déterministe est essentiel : deux appareils appliquant le même merge
    /// dans un ordre différent doivent converger. Un merge qui dépend de
    /// l'heure locale ou d'un aléa diverge.
    static func merge(local: Self, remote: Self) -> Self
}

/// Marque un type dont seul le serveur fixe la valeur.
///
/// Les conflits se résolvent par « le serveur gagne », sans exception et sans
/// interrogation de l'utilisateur.
public protocol ServerAuthoritative: Sendable {}

/// Ce qu'on fait de deux versions divergentes.
public enum ConflictOutcome<T: Sendable>: Sendable {

    case useRemote(T)
    case useLocal(T)

    /// Fusionné — réservé aux types ``LocallyMergeable``.
    case merged(T)

    /// L'utilisateur doit trancher. Réservé aux brouillons (§17).
    case userChoice(local: T, remote: T)
}

public enum ConflictResolver {

    /// Pour tout ce dont le serveur est l'autorité : il gagne.
    ///
    /// Générique sur ``ServerAuthoritative`` et non sur `Sendable` : appeler
    /// cette fonction sur un type qui ne s'est pas déclaré server-authoritative
    /// ne compile pas, ce qui force à choisir explicitement la politique de
    /// chaque type plutôt que de laisser la plus permissive par défaut.
    public static func resolve<T: ServerAuthoritative>(
        local: T, remote: T
    ) -> ConflictOutcome<T> {
        .useRemote(remote)
    }

    /// Pour ce qui se fusionne réellement.
    public static func resolve<T: LocallyMergeable>(
        local: T, remote: T
    ) -> ConflictOutcome<T> {
        .merged(T.merge(local: local, remote: remote))
    }
}
