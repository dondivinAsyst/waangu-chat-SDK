//
//  FinanceError.swift
//  CoreKit
//
//  Hiérarchie d'erreurs des opérations financières.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §22 du prompt d'origine.

import Foundation

/// Ce qui peut échouer dans une opération financière.
///
/// Distincte d'`AppError` à dessein : `AppError` décrit un transport
/// (réseau, décodage, session), alors qu'ici la question est toujours *l'argent
/// a-t-il bougé*. Les deux se croisent — un timeout HTTP est un `AppError.timeout`
/// et un `FinanceError.timeoutUnknown` — mais seule la seconde lecture interdit de
/// conclure à un échec.
public enum FinanceError: Error, Sendable, Equatable {

    // ── Autorisation ─────────────────────────────────────────
    case unauthorized
    case forbidden

    /// Compliance a refusé. La raison affichable vient du backend ; le motif
    /// réglementaire détaillé n'est jamais exposé au client.
    case complianceBlocked(displayReason: String?)

    /// La capacité n'est pas ouverte pour cet utilisateur, ce pays, ce niveau KYC.
    /// Ne devrait jamais atteindre l'utilisateur : l'entrée n'aurait pas dû exister.
    case capabilityUnavailable

    /// Le bénéficiaire n'a pas pu être résolu, ou l'a été en un acteur inutilisable.
    ///
    /// Classe d'erreur distincte de `validation` : une saisie peut être
    /// parfaitement bien formée et ne désigner personne — numéro non rattaché à un
    /// portefeuille, compte fermé, bénéficiaire hors juridiction. Les confondre
    /// ferait dire à l'utilisateur « champ invalide » là où le champ est correct.
    case recipientUnresolved(reason: RecipientRejection)

    /// Le permis d'exécution a expiré avant d'être consommé.
    ///
    /// **Non reprenable telle quelle** : les conditions ont eu le temps de
    /// changer. L'appelant repart d'un aperçu frais, sous la même clé
    /// d'idempotence — l'intention n'a pas changé, seules ses conditions.
    case executionPermitExpired

    /// Le permis a déjà servi.
    ///
    /// Signale un rejeu, pas une erreur de saisie. L'opération existe peut-être
    /// déjà : on la lit, on ne la refait pas.
    case executionPermitConsumed

    /// Les conditions ont changé entre l'aperçu et la confirmation.
    ///
    /// Porte les champs qui divergent, pour que l'interface puisse dire
    /// *quoi* a changé plutôt que « veuillez réessayer ».
    case confirmationStale(fields: [DecisionField])

    // ── Cycle de vie ─────────────────────────────────────────
    case expired
    case duplicate
    case conflict

    // ── Indéterminé ──────────────────────────────────────────

    /// Soumis, sans réponse exploitable.
    ///
    /// **Le cas central du Bloc 1.** Ne signifie pas « échec » : l'opération peut
    /// avoir abouti côté backend. Le seul traitement licite est la réconciliation.
    /// Ne jamais proposer « Réessayer » sur cette erreur.
    case timeoutUnknown

    // ── Infrastructure ───────────────────────────────────────
    case networkUnavailable
    case providerUnavailable
    case validation(field: String?)
    case server(statusCode: Int?)
}

// MARK: - Refus décidé par le serveur

/// Un refus que **le serveur a prononcé** : il a répondu, avec son code métier.
///
/// À ne pas confondre avec un échec de transport — délai dépassé, réseau absent,
/// 5xx sans enveloppe — où l'on ignore si l'opération a été exécutée. Ici on le
/// sait : elle ne l'a pas été. La distinction décide de ce que l'écran affiche
/// et de ce qui est publié dans la conversation.
///
/// Elle ne s'applique **pas** aux codes d'issue incertaine (`CF_017`, `CF_024`) :
/// le serveur y répond justement qu'il ne sait pas.
public struct FinanceServerRefusal: Error, Equatable, Sendable {

    /// Ce que la logique lit déjà — expiré, capacité fermée, conflit…
    public let error: FinanceError

    public init(_ error: FinanceError) {
        self.error = error
    }

    /// `nil` si l'erreur n'établit rien : l'issue reste inconnue.
    public static func decided(_ error: FinanceError) -> FinanceServerRefusal? {
        error == .timeoutUnknown ? nil : FinanceServerRefusal(error)
    }
}

// MARK: - Présentation

public extension FinanceError {

    /// Message destiné à l'utilisateur.
    ///
    /// Ne contient jamais de code technique. « Erreur 500 » n'apprend rien à
    /// l'utilisateur et renseigne un attaquant sur l'infrastructure ; la cause
    /// technique appartient aux logs, via `technicalDetail`.
    var userMessage: String {
        switch self {
        case .unauthorized:
            return "Vous devez vous reconnecter pour continuer."
        case .forbidden:
            return "Cette opération ne vous est pas permise."
        case .complianceBlocked(let reason):
            return reason ?? "Cette opération ne peut pas être effectuée pour le moment."
        case .recipientUnresolved(let reason):
            return reason.userMessage

        case .executionPermitExpired:
            return "Le délai de confirmation est écoulé. Reprenez l'opération."

        case .executionPermitConsumed:
            return "Cette opération a déjà été confirmée."

        case .confirmationStale:
            return "Les conditions ont changé. Vérifiez le récapitulatif avant de confirmer."

        case .capabilityUnavailable:
            return "Ce service n'est pas disponible depuis votre compte."
        case .expired:
            return "Cette opération a expiré. Reprenez-la depuis le début."
        case .duplicate:
            return "Cette opération a déjà été enregistrée."
        case .conflict:
            return "Cette opération a changé entre-temps. Actualisez pour voir son état."
        case .timeoutUnknown:
            // Ne dit jamais « échoué » : ce serait une invitation à repayer.
            return "Nous vérifions l'état de cette opération. Ne la relancez pas."
        case .networkUnavailable:
            return "Pas de connexion internet."
        case .providerUnavailable:
            return "Le service de paiement est temporairement indisponible."
        case .validation(let field):
            return field.map { "Vérifiez le champ « \($0) »." }
                ?? "Certaines informations sont incorrectes."
        case .server:
            return "Une erreur est survenue. Réessayez dans un moment."
        }
    }

    /// Détail réservé aux logs. Ne contient ni montant, ni contrepartie, ni identifiant.
    var technicalDetail: String {
        switch self {
        case .unauthorized:                return "unauthorized"
        case .forbidden:                   return "forbidden"
        case .complianceBlocked:           return "compliance_blocked"
        case .capabilityUnavailable:       return "capability_unavailable"
        case .recipientUnresolved(let r):  return "recipient_unresolved(\(r.rawValue))"
        case .executionPermitExpired:      return "execution_permit_expired"
        case .executionPermitConsumed:     return "execution_permit_consumed"
        case .confirmationStale(let f):    return "confirmation_stale(\(f.map(\.rawValue).joined(separator: ",")))"
        case .expired:                     return "expired"
        case .duplicate:                   return "duplicate"
        case .conflict:                    return "conflict"
        case .timeoutUnknown:              return "timeout_unknown"
        case .networkUnavailable:          return "network_unavailable"
        case .providerUnavailable:         return "provider_unavailable"
        case .validation(let field):       return "validation(\(field ?? "-"))"
        case .server(let code):            return "server(\(code.map(String.init) ?? "-"))"
        }
    }
}

// MARK: - Politique de reprise

public extension FinanceError {

    /// `true` si l'opération peut être **relancée telle quelle**, avec la même
    /// clé d'idempotence.
    ///
    /// `timeoutUnknown` en est exclu : c'est précisément le cas où l'opération a
    /// pu aboutir. Un retry y est un double débit potentiel, et le fait qu'il
    /// porterait la même clé d'idempotence ne suffit pas — rien ne garantit que le
    /// backend ait enregistré la première tentative.
    ///
    /// `duplicate` en est exclu aussi, pour la raison inverse : l'opération existe
    /// déjà, il faut la lire, pas la refaire.
    var isSafeToRetry: Bool {
        switch self {
        case .networkUnavailable, .providerUnavailable, .server:
            return true
        case .timeoutUnknown, .duplicate, .conflict, .expired,
             .unauthorized, .forbidden, .complianceBlocked,
             .capabilityUnavailable, .validation, .recipientUnresolved,
             .executionPermitExpired, .executionPermitConsumed, .confirmationStale:
            return false
        }
    }

    /// `true` si seule une interrogation du backend peut lever l'ambiguïté.
    var requiresReconciliation: Bool {
        switch self {
        case .timeoutUnknown, .duplicate, .conflict, .executionPermitConsumed:
            return true
        default:
            return false
        }
    }

    /// Statut à afficher tant que l'erreur n'est pas résolue.
    ///
    /// Une erreur ambiguë donne `.unknown`, jamais `.failed`.
    var displayedStatus: PaymentStatus? {
        switch self {
        case .timeoutUnknown, .conflict:   return .unknown
        case .expired:                     return .expired
        case .complianceBlocked:           return .complianceHold
        case .forbidden:                   return .denied
        default:                           return nil
        }
    }
}

// MARK: - Passerelle depuis AppError

public extension FinanceError {

    /// Traduit une erreur de transport en erreur financière.
    ///
    /// - Parameter afterSubmission: `true` si la requête a été **émise** vers le
    ///   backend avant l'échec. C'est le paramètre décisif : le même timeout est
    ///   une simple indisponibilité avant soumission, et une ambiguïté financière
    ///   après. L'appelant est le seul à le savoir, donc il doit le dire.
    static func from(_ error: AppError, afterSubmission: Bool) -> FinanceError {
        switch error {
        case .timeout:
            return afterSubmission ? .timeoutUnknown : .networkUnavailable

        case .networkError, .noInternetConnection:
            return afterSubmission ? .timeoutUnknown : .networkUnavailable

        case .serverError, .serviceUnavailable, .rateLimited:
            return afterSubmission ? .timeoutUnknown : .providerUnavailable

        case .authenticationError, .sessionExpired, .tokenRefreshFailed:
            return .unauthorized

        case .forbidden:
            return .forbidden

        case .validationError(_, let message):
            return .validation(field: message.isEmpty ? nil : message)

        case .badRequest:
            return .validation(field: nil)

        case .notFound:
            return .conflict

        case .decodingError, .emptyResponse:
            // Une réponse illisible après soumission ne prouve rien sur l'état
            // de l'opération : c'est le cas d'ambiguïté, pas une erreur de parsing.
            return afterSubmission ? .timeoutUnknown : .server(statusCode: nil)

        case .cancelled:
            return afterSubmission ? .timeoutUnknown : .validation(field: nil)

        case .biometric, .unknown:
            return afterSubmission ? .timeoutUnknown : .server(statusCode: nil)
        }
    }
}


// MARK: - RecipientRejection

/// Pourquoi un bénéficiaire n'a pas pu être retenu.
///
/// **BACKEND SOURCE OF TRUTH.** Le client ne déduit aucun de ces motifs : il les
/// reçoit. Déduire « ce numéro n'a pas de portefeuille » côté client supposerait
/// d'énumérer les comptes, ce que le contrat de lecture interdit explicitement.
public enum RecipientRejection: String, Codable, Sendable, Equatable {

    /// La saisie ne désigne aucun compte connu.
    case notFound = "NOT_FOUND"

    /// Le compte existe mais ne peut pas recevoir — fermé, suspendu, non vérifié.
    case ineligible = "INELIGIBLE"

    /// Le bénéficiaire est hors de la juridiction autorisée pour cette opération.
    case outOfJurisdiction = "OUT_OF_JURISDICTION"

    /// Refusé par le contrôle de risque ou de conformité.
    case blocked = "BLOCKED"

    /// La résolution a échoué sans motif exploitable.
    ///
    /// Ne jamais présenter comme `notFound` : « ce numéro n'existe pas » est une
    /// affirmation, et l'affirmer à tort pousse l'utilisateur à ressaisir un
    /// bénéficiaire pourtant correct.
    case undetermined = "UNDETERMINED"

    var userMessage: String {
        switch self {
        case .notFound:          return "Aucun compte ne correspond à cette saisie."
        case .ineligible:        return "Ce bénéficiaire ne peut pas recevoir ce paiement."
        case .outOfJurisdiction: return "Ce bénéficiaire n'est pas accessible depuis votre pays."
        case .blocked:           return "Ce bénéficiaire n'est pas disponible."
        case .undetermined:      return "Impossible de vérifier ce bénéficiaire pour le moment."
        }
    }

    /// Clé de message, pour le module `finance` de TranslationKit.
    ///
    /// **Ajouté après avoir vu « Undetermined » à l'écran.** `RequestMoneyView`
    /// passait `rawValue` comme clé de message : la valeur de transport
    /// `"UNDETERMINED"` remontait jusqu'à l'utilisateur, capitalisée et en
    /// anglais. Une valeur de protocole n'est pas un libellé.
    public var messageKey: String {
        switch self {
        case .notFound:          return "recipient_not_found"
        case .ineligible:        return "recipient_ineligible"
        case .outOfJurisdiction: return "recipient_out_of_jurisdiction"
        case .blocked:           return "recipient_blocked"
        case .undetermined:      return "recipient_undetermined"
        }
    }
}
