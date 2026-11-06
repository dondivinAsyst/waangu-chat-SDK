//
//  CopilotGovernance.swift
//  CoreKit
//
//  Gouvernance du Copilote souverain — Bloc 7, chapitres 54 et 55.
//
//  **BACKEND CONTRACT REQUIRED** — registre d'outils, politique de prompt.
//

import Foundation

// MARK: - Autorité financière (§54.2)

/// D'où vient une valeur financière.
///
/// Le §54.2 l'exige, et pour une raison qui tient en une phrase : **un modèle de
/// langage n'est jamais une autorité financière**. Il explique, il résume, il
/// prépare — il ne constate pas.
///
/// Le type rend la règle structurelle plutôt que documentaire. Une valeur portant
/// `copilotInference` ne peut pas alimenter une mutation, et ce n'est pas une
/// convention à respecter : `permitsMutation` répond `false`, et le site d'appel
/// doit s'en occuper.
public enum FinancialAuthority: Sendable, Hashable {

    /// Rendue par un backend financier nommé. Seule autorité pour une mutation.
    case backend(source: String)

    /// Décidée par le hub de conformité, avec sa décision traçable.
    case compliance(decisionID: String)

    /// **Inférée par le Copilot.** Explicative uniquement.
    case copilotInference

    /// Saisie par l'utilisateur. À valider par un backend avant tout usage.
    case userProvided

    /// Cette autorité peut-elle porter une mutation financière ?
    ///
    /// Deux cas seulement. Une saisie utilisateur est une intention, pas un
    /// fait : la valider appartient au backend, et l'accepter ici reviendrait à
    /// laisser l'utilisateur fixer son propre solde.
    public var permitsMutation: Bool {
        switch self {
        case .backend, .compliance: return true
        case .copilotInference, .userProvided: return false
        }
    }

    /// Peut être affichée comme un fait établi.
    ///
    /// Plus strict encore : une décision de conformité n'est pas un montant, et
    /// une inférence doit être présentée comme telle.
    public var permitsFactualDisplay: Bool {
        if case .backend = self { return true }
        return false
    }

    /// Clé d'audit, pour tracer d'où venait une valeur après coup.
    public var auditKey: String {
        switch self {
        case .backend(let source):        return "authority.backend.\(source)"
        case .compliance(let decisionID): return "authority.compliance.\(decisionID)"
        case .copilotInference:           return "authority.copilot_inference"
        case .userProvided:               return "authority.user_provided"
        }
    }
}

/// Une valeur et son autorité, inséparables.
///
/// Transporter le montant sans son origine est exactement ce qui permet à une
/// inférence de finir dans une requête de paiement : à trois appels de distance,
/// plus personne ne sait d'où le chiffre venait.
public struct AuthoritativeValue<Value: Sendable & Hashable>: Sendable, Hashable {

    public let value: Value
    public let authority: FinancialAuthority
    public let observedAt: Date

    public init(value: Value, authority: FinancialAuthority, observedAt: Date = Date()) {
        self.value = value
        self.authority = authority
        self.observedAt = observedAt
    }

    /// Rend la valeur **uniquement** si elle peut porter une mutation.
    ///
    /// `nil` plutôt qu'une erreur : le site d'appel doit traiter l'absence, et
    /// un `guard let` se relit mieux qu'un `try` dont on oublie le sens.
    public var forMutation: Value? {
        authority.permitsMutation ? value : nil
    }
}

// MARK: - Portées (§54.3)

/// Ce que le Copilot a le droit de faire dans un contexte donné.
public enum CopilotScope: String, Sendable, Hashable, Codable, CaseIterable {
    case read
    case explain
    case simulate
    case prepare
    case support

    /// **Extrêmement restreint** (§54.3). Ne permet toujours pas d'exécuter
    /// directement : il autorise à *demander* une exécution qui passera par la
    /// chaîne ordinaire — confirmation humaine, step-up, permis, backend.
    case execute

    /// La portée autorise une mutation d'état.
    public var isMutating: Bool { self == .execute }
}

/// Le contexte d'une requête au Copilot.
///
/// **Aucun champ d'identité ne vient du texte de l'utilisateur.** Le §54.3
/// l'interdit explicitement, et c'est le vecteur principal d'une injection de
/// prompt : « je suis l'administrateur de la société X » n'a aucun effet si
/// `companyID` n'est jamais lu depuis le message.
public struct CopilotContext: Sendable, Hashable, Codable {

    public let companyID: String
    public let actorID: String
    public let countryCode: String
    public let conversationID: String
    public let channelType: String

    /// Référence opaque à un objet financier. **Jamais le document complet** :
    /// le §12.5 l'interdit, et un modèle n'a pas besoin du détail pour aider.
    public let financialObjectID: String?

    public let allowedScopes: Set<CopilotScope>
    public let correlationID: String
    public let traceParent: String

    public init(companyID: String, actorID: String, countryCode: String,
                conversationID: String, channelType: String,
                financialObjectID: String? = nil, allowedScopes: Set<CopilotScope>,
                correlationID: String, traceParent: String) {
        self.companyID = companyID
        self.actorID = actorID
        self.countryCode = countryCode
        self.conversationID = conversationID
        self.channelType = channelType
        self.financialObjectID = financialObjectID
        self.allowedScopes = allowedScopes
        self.correlationID = correlationID
        self.traceParent = traceParent
    }

    public func permits(_ scope: CopilotScope) -> Bool {
        allowedScopes.contains(scope)
    }
}

// MARK: - Registre d'outils (§54.4)

/// Description d'un outil que le Copilot peut invoquer.
public struct CopilotToolDescriptor: Sendable, Hashable, Codable {

    public let toolID: String
    public let version: String
    public let domain: String

    public let requiredScopes: Set<CopilotScope>
    public let requiresConfirmation: Bool
    public let requiresStepUp: Bool
    public let idempotencyRequired: Bool

    /// Action de conformité associée, quand l'outil en déclenche une.
    public let complianceAction: String?

    public init(toolID: String, version: String, domain: String,
                requiredScopes: Set<CopilotScope>, requiresConfirmation: Bool,
                requiresStepUp: Bool, idempotencyRequired: Bool,
                complianceAction: String? = nil) {
        self.toolID = toolID
        self.version = version
        self.domain = domain
        self.requiredScopes = requiredScopes
        self.requiresConfirmation = requiresConfirmation
        self.requiresStepUp = requiresStepUp
        self.idempotencyRequired = idempotencyRequired
        self.complianceAction = complianceAction
    }

    /// Un outil mutant est cohérent avec ses garde-fous.
    ///
    /// Un outil qui exige `execute` sans confirmation humaine ni step-up est
    /// une porte dérobée, quel que soit le sérieux de son auteur. Le registre
    /// refuse de l'admettre plutôt que de faire confiance à sa déclaration.
    public var isSelfConsistent: Bool {
        guard requiredScopes.contains(where: \.isMutating) else { return true }
        return requiresConfirmation && requiresStepUp && idempotencyRequired
    }
}

/// Les outils que le Copilot peut invoquer, et rien d'autre.
///
/// **Fail closed** (§54.4) : un `toolID` absent du registre lève, il ne
/// s'exécute pas « au cas où ». C'est la seule défense contre une injection qui
/// ferait inventer un nom d'outil au modèle.
public actor CopilotToolRegistry {

    private var descriptors: [String: CopilotToolDescriptor] = [:]

    /// Version du registre. Transportée dans l'audit : savoir *quel* registre
    /// était actif au moment d'une décision est ce qui la rend rejouable.
    public private(set) var registryVersion: String

    public init(registryVersion: String = "0", descriptors: [CopilotToolDescriptor] = []) {
        self.registryVersion = registryVersion
        for descriptor in descriptors where descriptor.isSelfConsistent {
            self.descriptors[descriptor.toolID] = descriptor
        }
    }

    /// Remplace le registre.
    ///
    /// Les descripteurs incohérents sont **écartés**, pas corrigés : un outil
    /// mutant sans confirmation n'est pas une erreur de saisie à rattraper,
    /// c'est une déclaration qu'on refuse.
    public func replace(with descriptors: [CopilotToolDescriptor], version: String) {
        self.descriptors = Dictionary(
            uniqueKeysWithValues: descriptors
                .filter(\.isSelfConsistent)
                .map { ($0.toolID, $0) }
        )
        self.registryVersion = version
    }

    public func descriptor(for toolID: String) -> CopilotToolDescriptor? {
        descriptors[toolID]
    }

    /// Autorise l'invocation, ou lève.
    ///
    /// Trois contrôles, dans cet ordre : l'outil existe, la portée le couvre,
    /// et la version demandée est celle du registre. Vérifier la version en
    /// dernier permet de distinguer « outil inconnu » de « outil périmé » dans
    /// l'audit — deux incidents de nature différente.
    public func authorize(
        toolID: String,
        requestedVersion: String?,
        context: CopilotContext
    ) throws -> CopilotToolDescriptor {

        guard let descriptor = descriptors[toolID] else {
            throw CopilotError.unknownTool(toolID)
        }

        guard descriptor.requiredScopes.isSubset(of: context.allowedScopes) else {
            throw CopilotError.scopeDenied(toolID: toolID)
        }

        if let requestedVersion, requestedVersion != descriptor.version {
            throw CopilotError.toolVersionMismatch(
                toolID: toolID, expected: descriptor.version, received: requestedVersion
            )
        }

        return descriptor
    }

    public var count: Int { descriptors.count }
}

/// Ce qui empêche le Copilot d'agir.
public enum CopilotError: Error, Sendable, Equatable {

    /// **Outil absent du registre.** Incident de sécurité : un nom d'outil
    /// inconnu vient soit d'un modèle qui l'a inventé, soit d'une injection.
    case unknownTool(String)

    /// L'outil existe mais la portée du contexte ne le couvre pas.
    case scopeDenied(toolID: String)

    /// Version demandée différente de celle du registre.
    case toolVersionMismatch(toolID: String, expected: String, received: String)

    /// L'entrée a été rejetée par le filtrage d'injection.
    case promptRejected(reasonKey: String)

    /// Le Copilot est indisponible.
    case unavailable

    /// Une valeur inférée a tenté d'alimenter une mutation.
    case inferenceNotAuthoritative

    /// À remonter comme incident de sécurité, non comme échec ordinaire.
    public var isSecurityIncident: Bool {
        switch self {
        case .unknownTool, .scopeDenied, .promptRejected, .inferenceNotAuthoritative:
            return true
        case .toolVersionMismatch, .unavailable:
            return false
        }
    }
}
