//
//  FinancialPrivacyEngine.swift
//  CoreKit
//
//  Classification et exposition des données — Bloc 6, §24.
//

import Foundation

/// Sensibilité d'une donnée financière.
///
/// Distinct de ``DataClassifier``, qui devine une nature à partir d'une chaîne.
/// Ici, la classe est **déclarée** par qui produit la donnée : deviner marche
/// jusqu'au format qu'on n'avait pas prévu, et ce jour-là un numéro de carte
/// passe pour du texte ordinaire.
///
/// L'ordre est significatif — `Comparable` permet d'exprimer « au moins aussi
/// sensible que », qui est la forme naturelle d'une règle d'exposition.
public enum FinancialDataClass: Int, Sendable, Codable, Comparable, CaseIterable {

    /// Publiable : nom d'enseigne, catégorie marchande.
    case publicInfo      = 0

    /// Visible dans un fil de conversation : libellé d'opération, statut.
    case conversational  = 1

    /// Détail d'une transaction : montant, contrepartie, référence.
    case transactional   = 2

    /// Solde, historique agrégé, identité vérifiée.
    case sensitive       = 3

    /// Coordonnées bancaires, quatre derniers chiffres, pièces d'identité.
    case highlySensitive = 4

    /// PAN, CVV, PIN, OTP, cryptogramme, clé. **Ne s'expose jamais.**
    case secret          = 5

    public static func < (lhs: FinancialDataClass, rhs: FinancialDataClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Une classe inconnue devient `secret`.
    ///
    /// Le sens de la dégradation est tout : se tromper vers `secret` masque une
    /// donnée anodine, se tromper vers `publicInfo` expose un PAN.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = FinancialDataClass(rawValue: raw) ?? .secret
    }

    /// Aucune exposition n'est concevable, quel que soit le destinataire.
    public var isNeverExposable: Bool { self == .secret }

    /// Doit apparaître masquée si elle apparaît.
    public var requiresMasking: Bool { self >= .highlySensitive }

    /// Toute exposition doit laisser une trace d'audit.
    public var requiresAudit: Bool { self >= .sensitive }
}

// MARK: - Destinataire et finalité

/// À qui l'on montre.
public enum Recipient: Sendable, Hashable {

    /// Le titulaire lui-même, sur son appareil authentifié.
    case accountHolder

    /// Un participant de la conversation.
    case conversationParticipant(actorID: String)

    /// Un marchand ou prestataire.
    case merchant(merchantID: String)

    /// Le support, dans le cadre d'un dossier ouvert.
    case support(caseID: String)

    /// Une mini-app propriétaire.
    case nativeApp(appID: String)

    /// Les journaux, la télémétrie, les rapports de crash.
    ///
    /// Un destinataire à part entière : les traces se conservent, se copient et
    /// se lisent par des gens qui n'ont jamais consenti à voir ces données.
    case telemetry
}

/// Pourquoi l'on montre.
///
/// La finalité est le second terme de la règle : la même donnée se justifie
/// pour un remboursement et ne se justifie pas pour de la publicité. Sans elle,
/// une autorisation accordée une fois vaudrait pour tous les usages.
public enum Purpose: String, Sendable, Hashable, Codable {
    case displayToOwner    = "DISPLAY_TO_OWNER"
    case executePayment    = "EXECUTE_PAYMENT"
    case resolveDispute    = "RESOLVE_DISPUTE"
    case reconcile         = "RECONCILE"
    case customerSupport   = "CUSTOMER_SUPPORT"
    case fraudInvestigation = "FRAUD_INVESTIGATION"
    case diagnostics       = "DIAGNOSTICS"
    case analytics         = "ANALYTICS"
}

// MARK: - Politique

/// Décide si une donnée peut être exposée.
public protocol DataExposurePolicy: Sendable {

    func canExpose(
        dataClass: FinancialDataClass,
        recipient: Recipient,
        purpose: Purpose
    ) -> Bool
}

/// La politique par défaut du dépôt.
///
/// Écrite en dur plutôt que rendue par le backend, et c'est délibéré : ces
/// règles ne doivent pas pouvoir être assouplies par une réponse réseau. Un
/// backend compromis ou une réponse falsifiée pourrait sinon élargir ce que le
/// client accepte de montrer.
public struct DefaultDataExposurePolicy: DataExposurePolicy {

    public init() {}

    public func canExpose(dataClass: FinancialDataClass,
                          recipient: Recipient,
                          purpose: Purpose) -> Bool {

        // Rien, jamais, pour personne. Aucune finalité ne justifie un PAN,
        // un CVV, un PIN ou un cryptogramme hors du système de cartes.
        if dataClass.isNeverExposable { return false }

        switch recipient {

        case .accountHolder:
            // Le titulaire voit ses propres données — sauf les secrets, déjà
            // écartés. Une finalité d'analyse ne s'applique pas à lui.
            return purpose != .analytics

        case .conversationParticipant:
            // Un participant voit ce qui relève de la conversation, jamais un
            // solde ni une identité vérifiée. Sans cette borne, partager une
            // opération dans un groupe révélerait la situation financière de
            // celui qui la partage.
            return dataClass <= .conversational

        case .merchant:
            // Le marchand a besoin du détail de la transaction qui le concerne,
            // et de rien de plus.
            guard dataClass <= .transactional else { return false }
            return purpose == .executePayment
                || purpose == .resolveDispute
                || purpose == .reconcile

        case .support:
            // Le support voit large, mais seulement dans un dossier ouvert et
            // pour une finalité de traitement — jamais pour du diagnostic
            // technique ni de l'analyse.
            guard dataClass <= .highlySensitive else { return false }
            return purpose == .customerSupport
                || purpose == .resolveDispute
                || purpose == .fraudInvestigation

        case .nativeApp:
            // Une mini-app reçoit de quoi afficher sa carte et exécuter son
            // paiement. Elle n'a aucune raison de connaître un solde.
            guard dataClass <= .transactional else { return false }
            return purpose == .executePayment || purpose == .displayToOwner

        case .telemetry:
            // Les journaux ne portent que du public et du conversationnel, et
            // uniquement pour diagnostiquer. Une trace se conserve, se copie et
            // se lit par des gens qui n'ont jamais consenti à voir ces données.
            guard dataClass <= .conversational else { return false }
            return purpose == .diagnostics
        }
    }
}

// MARK: - Application

/// Applique la politique à une valeur.
///
/// Rend le résultat **explicite** plutôt qu'un booléen : « masqué » et
/// « refusé » ne s'affichent pas pareil, et les confondre ferait disparaître
/// une ligne là où un `••••` suffisait.
public enum ExposureOutcome: Sendable, Equatable {

    /// Exposable telle quelle.
    case exposed(String)

    /// Exposable masquée.
    case masked(String)

    /// Non exposable. `reasonKey` dit pourquoi, pour l'audit.
    case withheld(reasonKey: String)

    public var displayValue: String? {
        switch self {
        case .exposed(let value), .masked(let value): return value
        case .withheld:                               return nil
        }
    }
}

/// Le moteur qui applique la politique et rend une valeur prête à afficher.
public struct FinancialPrivacyEngine: Sendable {

    private let policy: any DataExposurePolicy

    public init(policy: any DataExposurePolicy = DefaultDataExposurePolicy()) {
        self.policy = policy
    }

    /// Expose une valeur, ou la masque, ou la retient.
    ///
    /// Le masquage n'est **pas** une exposition partielle décidée ici : il ne
    /// s'applique qu'à une donnée déjà autorisée, dont la classe impose une
    /// forme réduite. Une donnée refusée ne se masque pas — elle disparaît.
    public func expose(
        _ value: String,
        dataClass: FinancialDataClass,
        to recipient: Recipient,
        for purpose: Purpose
    ) -> ExposureOutcome {

        guard policy.canExpose(dataClass: dataClass, recipient: recipient, purpose: purpose) else {
            return .withheld(reasonKey: "privacy.withheld.\(purpose.rawValue.lowercased())")
        }

        guard dataClass.requiresMasking else { return .exposed(value) }
        return .masked(Self.mask(value))
    }

    /// Masque en ne gardant que les quatre derniers caractères.
    ///
    /// Quatre suffisent à reconnaître sa propre donnée et ne suffisent à
    /// personne pour s'en servir. Une valeur trop courte est masquée
    /// **entièrement** : garder quatre caractères sur cinq ne masque rien.
    public static func mask(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 6 else {
            return String(repeating: "•", count: max(trimmed.count, 4))
        }
        return "•••• \(trimmed.suffix(4))"
    }

    /// Cette exposition doit-elle être tracée ?
    public func requiresAudit(dataClass: FinancialDataClass) -> Bool {
        dataClass.requiresAudit
    }
}
