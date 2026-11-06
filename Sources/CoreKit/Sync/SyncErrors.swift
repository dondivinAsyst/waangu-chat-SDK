//
//  SyncErrors.swift
//  CoreKit
//
//  Taxonomie des erreurs de synchronisation — Bloc 8, §39 et §9.
//
//  Ferme P0-6. Réutilise ``RetryPolicy`` et ``FinancialRetryDecision``
//  (`FinancialResilience.swift`) plutôt que de redéfinir un backoff : la
//  politique financière — une seule tentative, requête plutôt que rejeu — est
//  déjà écrite et correcte.
//

import Foundation

/// Ce qui a empêché une synchronisation d'aboutir.
///
/// Le moteur actuel (`FeatureSyncEngine.runPaginatedPull`) fait ceci :
///
/// ```swift
/// } catch {
///     #if DEBUG
///     print("... Pull interrupted: \(error.localizedDescription)")
///     #endif
///     break
/// }
/// ```
///
/// Un réseau coupé, un curseur invalide, un 403 et une réponse malformée
/// sortent de la boucle de la même façon. En `RELEASE`, l'événement ne laisse
/// **aucune trace**. Distinguer les cas n'est pas du confort : la moitié de ces
/// erreurs ne doit jamais être réessayée, et l'autre moitié doit l'être
/// différemment.
public enum SyncError: Error, Sendable, Equatable {

    /// Pas de réseau. Ni une faute ni un incident.
    case offline

    /// Requête partie, pas de réponse dans le délai.
    case timeout

    /// Session invalide ou expirée. **Jamais de retry automatique** — le §9
    /// l'interdit sans renouvellement contrôlé, faute de quoi un client boucle
    /// sur un refresh qui échoue.
    case unauthorized

    /// Droit refusé. Rejouer ne changera rien.
    case forbidden

    /// Conflit exigeant une résolution (§17).
    case conflict(objectID: String?)

    /// La donnée locale est en retard sur le serveur.
    case stale

    /// Ressource expirée — devis, permis, aperçu.
    case expired

    /// Appareil ou session révoqué. Impose une purge locale (§18).
    case revoked

    /// Le curseur n'est plus reconnu par le serveur. Impose une resynchro
    /// complète, jamais une reprise.
    case invalidCursor

    /// Réponse illisible.
    case malformedPayload(reason: String)

    /// Serveur indisponible — 502, 503.
    case serverUnavailable(retryAfter: TimeInterval?)

    /// **La requête est partie, l'issue est inconnue.**
    ///
    /// Le §10 en fait un cas à part entière : ne pas rejouer, requêter l'état
    /// autoritatif. Pour une mutation financière, c'est la différence entre un
    /// débit et deux.
    case unknownOutcome(operationID: String?)

    /// Échec définitif. Part en dead-letter.
    case permanentFailure(code: String)

    /// Un événement destiné à un autre compte ou tenant a été reçu.
    ///
    /// Traité comme une erreur et non comme un filtre silencieux : c'est le
    /// signal d'un défaut d'autorisation côté serveur ou d'un topic mal résolu
    /// (§14), et il doit remonter.
    case foreignScope
}

// MARK: - Classification (§9)

/// Ce qu'il faut faire d'une erreur.
public enum SyncDisposition: Sendable, Equatable {

    /// Réessayer après ce délai.
    case retry(after: TimeInterval)

    /// Ne pas rejouer — interroger l'état autoritatif (§10).
    case requery

    /// Renouveler la session, de façon contrôlée, puis reprendre.
    case reauthenticate

    /// Repartir de zéro : le curseur ne vaut plus rien.
    case fullResync

    /// Purger les données sensibles locales et arrêter (§18, §43).
    case purgeAndStop

    /// Sans issue automatique : dossier mort, à examiner.
    case deadLetter(reasonKey: String)

    /// L'utilisateur doit trancher.
    case userAction(reasonKey: String)
}

public extension SyncError {

    /// La conduite à tenir.
    ///
    /// Les interdictions du §9 sont ici, en dur : `unauthorized`, `forbidden`,
    /// `conflict`, `expired` et les échecs métier ne produisent **jamais**
    /// `.retry`. C'est l'endroit unique où cette règle vit ; la recopier dans
    /// chaque appelant est exactement ce qui finit par en oublier une.
    func disposition(attempt: Int, policy: RetryPolicy = .read) -> SyncDisposition {
        switch self {

        case .offline:
            // Ce n'est pas une erreur à compter : le réseau reviendra. On
            // n'épuise pas les tentatives sur une absence de réseau.
            return .retry(after: 0)

        case .timeout:
            guard let delay = policy.nextDelay(afterAttempt: attempt) else {
                return .requery
            }
            return .retry(after: delay)

        case .serverUnavailable(let retryAfter):
            // `Retry-After` du serveur fait autorité sur notre backoff : il
            // sait quand il sera prêt, nous non.
            if let retryAfter { return .retry(after: retryAfter) }
            guard let delay = policy.nextDelay(afterAttempt: attempt) else {
                return .deadLetter(reasonKey: "sync.error.server_unavailable")
            }
            return .retry(after: delay)

        case .unauthorized:
            return .reauthenticate

        case .revoked:
            return .purgeAndStop

        case .invalidCursor:
            return .fullResync

        case .unknownOutcome:
            return .requery

        case .stale:
            return .requery

        case .conflict:
            return .userAction(reasonKey: "sync.error.conflict")

        case .expired:
            return .userAction(reasonKey: "sync.error.expired")

        case .forbidden:
            return .deadLetter(reasonKey: "sync.error.forbidden")

        case .foreignScope:
            return .deadLetter(reasonKey: "sync.error.foreign_scope")

        case .malformedPayload:
            return .deadLetter(reasonKey: "sync.error.malformed")

        case .permanentFailure(let code):
            return .deadLetter(reasonKey: "sync.error.permanent.\(code)")
        }
    }

    /// Clé de message affichable.
    ///
    /// Le §39 l'exige : jamais « Une erreur est survenue ». Un utilisateur
    /// hors ligne, un utilisateur dont la session a expiré et un utilisateur
    /// dont l'appareil a été révoqué doivent faire trois choses différentes ;
    /// un message unique les laisse tous les trois bloqués.
    var displayMessageKey: String {
        switch self {
        case .offline:              return "sync.error.offline"
        case .timeout:              return "sync.error.timeout"
        case .unauthorized:         return "sync.error.session_expired"
        case .forbidden:            return "sync.error.forbidden"
        case .conflict:             return "sync.error.conflict"
        case .stale:                return "sync.error.stale"
        case .expired:              return "sync.error.expired"
        case .revoked:              return "sync.error.device_revoked"
        case .invalidCursor:        return "sync.error.resync_required"
        case .malformedPayload:     return "sync.error.malformed"
        case .serverUnavailable:    return "sync.error.server_unavailable"
        case .unknownOutcome:       return "sync.error.checking"
        case .permanentFailure:     return "sync.error.permanent"
        case .foreignScope:         return "sync.error.foreign_scope"
        }
    }

    /// À remonter comme incident plutôt que comme aléa d'exploitation.
    var isSecurityIncident: Bool {
        switch self {
        case .foreignScope, .revoked, .forbidden: return true
        default:                                   return false
        }
    }
}

// MARK: - Correspondance HTTP (§28)

public extension SyncError {

    /// Traduit un statut HTTP.
    ///
    /// - Parameter isMutation: une requête qui écrit. Un timeout sur une
    ///   mutation devient ``unknownOutcome`` et non ``timeout`` : l'écriture a
    ///   pu aboutir côté serveur, et la traiter comme un simple échec réseau
    ///   est précisément ce qui produit le double effet.
    static func from(statusCode: Int, retryAfter: TimeInterval? = nil,
                     isMutation: Bool = false, operationID: String? = nil) -> SyncError? {
        switch statusCode {
        case 200...299:  return nil
        case 401:        return .unauthorized
        case 403:        return .forbidden
        case 409:        return .conflict(objectID: nil)
        case 410:        return .invalidCursor
        case 422:        return .permanentFailure(code: "unprocessable")
        case 429:        return .serverUnavailable(retryAfter: retryAfter)
        case 400, 404:   return .permanentFailure(code: "http_\(statusCode)")
        case 502, 503:   return .serverUnavailable(retryAfter: retryAfter)
        case 500, 504:
            return isMutation
                ? .unknownOutcome(operationID: operationID)
                : .serverUnavailable(retryAfter: retryAfter)
        default:
            return .permanentFailure(code: "http_\(statusCode)")
        }
    }
}

// MARK: - Dead letter (§9, §26)

/// Une opération qu'aucun retry ne sauvera.
public struct DeadLetterEntry: Sendable, Hashable, Codable, Identifiable {

    public let id: String

    /// L'opération concernée, pour la corrélation de bout en bout (§27).
    public let correlationID: String
    public let operationID: String?
    public let streamID: String?

    /// Motif, en clé — jamais une phrase composée, jamais un payload.
    public let reasonKey: String

    public let attemptCount: Int
    public let firstFailedAt: Date
    public let lastFailedAt: Date

    public init(id: String, correlationID: String, operationID: String? = nil,
                streamID: String? = nil, reasonKey: String, attemptCount: Int,
                firstFailedAt: Date, lastFailedAt: Date) {
        self.id = id
        self.correlationID = correlationID
        self.operationID = operationID
        self.streamID = streamID
        self.reasonKey = reasonKey
        self.attemptCount = attemptCount
        self.firstFailedAt = firstFailedAt
        self.lastFailedAt = lastFailedAt
    }
}

/// Recueille ce qui a définitivement échoué.
///
/// Sans ce puits, une opération morte disparaît : c'est le comportement actuel,
/// où le `break` de la boucle de pull ne laisse rien derrière lui. Le §6
/// (visite d'exploitation) en fait une exigence — sans dead-letter, le support
/// n'a rien à examiner.
public protocol DeadLetterSink: Sendable {

    func record(_ entry: DeadLetterEntry) async

    func pending() async -> [DeadLetterEntry]

    /// Rejeu manuel, déclenché par un opérateur — jamais automatique.
    func retryManually(id: String) async -> Result<Void, SyncError>
}
