//
//  FinancialActor.swift
//  CoreKit
//
//  Qui participe à une opération financière — Bloc 2, chapitre 10.
//

import Foundation

/// Une partie prenante d'une opération financière.
///
/// **BACKEND SOURCE OF TRUTH.** Aucun champ n'est déductible côté client : le
/// type d'acteur, son statut de vérification, sa juridiction et ses permissions
/// sont établis par le backend et transportés. Un client qui déduirait qu'un
/// numéro appartient à un marchand parce qu'il figure dans une conversation
/// marchande donnerait à la conversation un pouvoir financier — ce que
/// l'architecture interdit.
public struct FinancialActor: Codable, Sendable, Hashable {

    /// Identifiant opaque émis par le backend. Sans signification métier.
    public let actorID: String

    public let type: FinancialActorType

    /// Nom affichable, tel que le backend l'a établi.
    ///
    /// Jamais résolu depuis l'annuaire local : un nom de contact peut désigner
    /// quelqu'un d'autre que le bénéficiaire réel, et c'est précisément le levier
    /// d'une fraude au bénéficiaire.
    public let displayName: String

    public let verification: VerificationStatus

    /// Juridiction de l'acteur. JURISDICTION CONTROLLED.
    public let jurisdiction: String?

    /// Ce que **cet** acteur a le droit de faire sur **cet** objet.
    ///
    /// Distinct de `FinanceCapabilities`, qui décrit ce que l'utilisateur courant
    /// a le droit de faire en général. « A le droit d'envoyer de l'argent » ne dit
    /// rien sur « a le droit d'annuler cet objet-ci ».
    public let permissions: Set<FinancialPermission>

    public init(
        actorID: String,
        type: FinancialActorType,
        displayName: String,
        verification: VerificationStatus = .unverified,
        jurisdiction: String? = nil,
        permissions: Set<FinancialPermission> = []
    ) {
        self.actorID = actorID
        self.type = type
        self.displayName = displayName
        self.verification = verification
        self.jurisdiction = jurisdiction
        self.permissions = permissions
    }
}

// MARK: - Type d'acteur

public enum FinancialActorType: String, Codable, Sendable, CaseIterable {
    case user          = "USER"
    case merchant      = "MERCHANT"
    case agent         = "AGENT"
    case superAgent    = "SUPER_AGENT"
    case organization  = "ORGANIZATION"
    case institution   = "INSTITUTION"
    case biller        = "BILLER"
    case bank          = "BANK"
    case sacco         = "SACCO"
    case microfinance  = "MICROFINANCE"
    case copilot       = "COPILOT"
    case humanSupport  = "HUMAN_SUPPORT"

    /// Décodage défensif : un type d'acteur introduit après ce client devient
    /// `.user`… **non**. Il n'y a pas de repli sûr ici, contrairement à
    /// `PaymentStatus.unknown` : traiter une institution inconnue comme un
    /// particulier changerait les règles applicables. L'absence de repli est
    /// délibérée — un type inconnu fait échouer le décodage de l'acteur, et
    /// l'appelant traite l'acteur comme non résolu.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = FinancialActorType(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Type d'acteur inconnu : \(raw)")
            )
        }
        self = value
    }
}

// MARK: - Vérification

/// Ce que le backend a établi sur l'identité de l'acteur.
///
/// `unverified` n'est pas une valeur par défaut commode : c'est une information
/// que la carte **doit** afficher. Un bénéficiaire non vérifié présenté comme un
/// bénéficiaire ordinaire est le levier de la fraude au bénéficiaire.
public enum VerificationStatus: String, Codable, Sendable, CaseIterable {

    case unverified      = "UNVERIFIED"
    case pending         = "PENDING"
    case verified        = "VERIFIED"

    /// Compte officiel — institution, service public, marchand certifié.
    case officialAccount = "OFFICIAL_ACCOUNT"

    /// Vérification retirée après coup. **Plus grave que `unverified`** : quelque
    /// chose a été révoqué, et l'interface ne doit pas les confondre.
    case revoked         = "REVOKED"

    /// Un statut inconnu de ce client ne devient jamais `verified`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VerificationStatus(rawValue: raw) ?? .unverified
    }

    /// `true` si l'interface a le droit d'afficher un badge de confiance.
    public var showsTrustBadge: Bool {
        self == .verified || self == .officialAccount
    }

    /// `true` si l'utilisateur doit être averti avant de confirmer.
    public var warrantsWarning: Bool {
        self == .unverified || self == .revoked
    }
}

// MARK: - Permissions

/// Ce qui est permis sur un objet financier donné.
///
/// Axe distinct de `FinanceCapabilities` : celui-ci porte sur l'objet et
/// l'acteur, celui-là sur le produit et le marché. Les confondre est un défaut
/// d'autorisation, pas une simplification.
public enum FinancialPermission: String, Codable, Sendable, CaseIterable {
    case read     = "READ"
    case share    = "SHARE"
    case initiate = "INITIATE"
    case confirm  = "CONFIRM"
    case execute  = "EXECUTE"
    case cancel   = "CANCEL"
    case refund   = "REFUND"
    case dispute  = "DISPUTE"
    case support  = "SUPPORT"

    /// Une permission inconnue est ignorée, jamais accordée.
    ///
    /// Le décodage d'un `Set` tolérant est écrit côté appelant : ici, l'inconnu
    /// fait simplement échouer ce membre, que `decodePermissions` écarte.
    public static func decodeTolerantly(_ raw: [String]) -> Set<FinancialPermission> {
        Set(raw.compactMap(FinancialPermission.init(rawValue:)))
    }
}
