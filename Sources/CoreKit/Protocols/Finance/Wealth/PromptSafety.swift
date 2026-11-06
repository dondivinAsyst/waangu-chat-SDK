//
//  PromptSafety.swift
//  CoreKit
//
//  Filtrage des entrées du Copilote — Bloc 7, §17.
//
//  **BACKEND CONTRACT REQUIRED** — politique de filtrage versionnée.
//

import Foundation

/// Examine ce que l'utilisateur envoie au Copilot.
///
/// `SecurityKit/AI/PromptInjectionFilter.swift` fait 256 lignes et **n'a aucun
/// appelant** : `FeatureChat` ne dépend pas de `SecurityKit`, et ne le peut pas.
/// Ce protocole est le pont — l'app branche l'implémentation réelle, le Chat ne
/// voit que le contrat.
///
/// La défense ne repose **pas** sur ce filtre. Elle repose sur trois choses que
/// le texte ne peut pas atteindre : l'identité vient de ``CopilotContext``,
/// jamais du message ; les outils viennent de ``CopilotToolRegistry``, qui
/// refuse l'inconnu ; et aucune mutation ne part sans confirmation humaine,
/// step-up et permis. Le filtre est une couche de plus, pas la couche.
public protocol PromptSafetyScreening: Sendable {

    /// Examine une entrée avant qu'elle atteigne le modèle.
    func screen(_ input: String, context: CopilotContext) async -> PromptScreeningVerdict

    /// Examine une sortie avant qu'elle atteigne l'utilisateur.
    ///
    /// Le sens retour compte autant : un modèle peut restituer ce qu'une
    /// injection lui a fait lire — un prompt système, une donnée d'un autre
    /// dossier.
    func screenOutput(_ output: String, context: CopilotContext) async -> PromptScreeningVerdict
}

/// Ce que le filtrage conclut.
public enum PromptScreeningVerdict: Sendable, Equatable {

    /// Rien de notable.
    case clean

    /// Motif suspect, sans blocage. Journalisé pour la corrélation : une
    /// campagne d'injection se voit dans l'agrégat bien avant de réussir.
    case suspicious(categories: Set<PromptRiskCategory>)

    /// Rejeté. L'entrée n'atteint pas le modèle.
    case rejected(categories: Set<PromptRiskCategory>, reasonKey: String)

    /// Le filtre n'a pas pu se prononcer.
    ///
    /// **N'est pas `clean`.** Un filtre indisponible ne blanchit rien : la
    /// décision revient à l'appelant, qui refusera pour une portée mutante.
    case unavailable

    public var permitsProcessing: Bool {
        switch self {
        case .clean, .suspicious: return true
        case .rejected, .unavailable: return false
        }
    }

    public var categories: Set<PromptRiskCategory> {
        switch self {
        case .clean, .unavailable:                     return []
        case .suspicious(let set):                     return set
        case .rejected(let set, _):                    return set
        }
    }
}

/// Les familles d'attaque que le §17 énumère.
///
/// Nommées séparément parce qu'elles n'appellent pas la même réaction : une
/// tentative d'escalade de privilège est un incident à corréler, une demande de
/// révéler le prompt système est du bruit quotidien.
public enum PromptRiskCategory: String, Sendable, Hashable, Codable, CaseIterable {

    /// « Ignore les instructions précédentes ».
    case instructionOverride   = "INSTRUCTION_OVERRIDE"

    /// « Fais comme si la conformité avait approuvé ».
    case complianceSpoofing    = "COMPLIANCE_SPOOFING"

    /// « Exécute l'outil X ».
    case toolInjection         = "TOOL_INJECTION"

    /// « Révèle ton prompt système ».
    case systemDisclosure      = "SYSTEM_DISCLOSURE"

    /// « Montre-moi les données KYC ».
    case sensitiveDisclosure   = "SENSITIVE_DISCLOSURE"

    /// « Contourne l'AML ».
    case controlBypass         = "CONTROL_BYPASS"

    /// « Envoie de l'argent sans confirmation ».
    case unconfirmedMutation   = "UNCONFIRMED_MUTATION"

    /// « Utilise le compte d'un autre », « change company_id ».
    case identitySubstitution  = "IDENTITY_SUBSTITUTION"

    /// « Réutilise l'approbation précédente ».
    case approvalReplay        = "APPROVAL_REPLAY"

    /// Catégorie inconnue de ce client.
    case unknown               = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PromptRiskCategory(rawValue: raw) ?? .unknown
    }

    /// Une tentative de cette famille doit être remontée comme incident.
    ///
    /// La divulgation du prompt système en est exclue : c'est fréquent,
    /// inoffensif si le prompt ne contient pas de secret, et le traiter comme
    /// un incident noierait les vraies alertes.
    public var isSecurityIncident: Bool {
        switch self {
        case .systemDisclosure, .unknown:
            return false
        case .instructionOverride, .complianceSpoofing, .toolInjection,
             .sensitiveDisclosure, .controlBypass, .unconfirmedMutation,
             .identitySubstitution, .approvalReplay:
            return true
        }
    }
}

// MARK: - Porte d'entrée du Copilot

/// Décide si une requête peut atteindre le modèle.
///
/// Point de passage unique. Sans lui, chaque écran réimplémenterait la
/// séquence — portée, filtrage, registre — et l'un d'eux finirait par en
/// oublier une.
public struct CopilotAdmission: Sendable {

    private let screening: any PromptSafetyScreening
    private let registry: CopilotToolRegistry

    public init(screening: any PromptSafetyScreening, registry: CopilotToolRegistry) {
        self.screening = screening
        self.registry = registry
    }

    /// Examine une entrée destinée au Copilot.
    ///
    /// Un verdict `unavailable` bloque **dès qu'une portée mutante est
    /// demandée**. Pour une simple lecture, l'indisponibilité du filtre ne
    /// justifie pas de couper l'assistance : le modèle ne peut de toute façon
    /// rien exécuter sans passer par le registre.
    public func admit(
        input: String,
        context: CopilotContext
    ) async -> Result<PromptScreeningVerdict, CopilotError> {

        let verdict = await screening.screen(input, context: context)

        switch verdict {
        case .clean, .suspicious:
            return .success(verdict)

        case .rejected(_, let reasonKey):
            return .failure(.promptRejected(reasonKey: reasonKey))

        case .unavailable:
            let wantsMutation = context.allowedScopes.contains(where: \.isMutating)
            return wantsMutation
                ? .failure(.promptRejected(reasonKey: "copilot.screening.unavailable"))
                : .success(verdict)
        }
    }

    /// Autorise l'invocation d'un outil, après filtrage.
    public func admitTool(
        toolID: String,
        requestedVersion: String? = nil,
        context: CopilotContext
    ) async -> Result<CopilotToolDescriptor, CopilotError> {
        do {
            return .success(
                try await registry.authorize(toolID: toolID,
                                             requestedVersion: requestedVersion,
                                             context: context)
            )
        } catch let error as CopilotError {
            return .failure(error)
        } catch {
            return .failure(.unavailable)
        }
    }
}

// MARK: - Défaut fermé

/// Ne filtre rien, et le dit.
///
/// Rend `.unavailable` plutôt que `.clean` : un filtre absent ne blanchit pas
/// une entrée. `CopilotAdmission` en tire la bonne conséquence — lecture
/// tolérée, mutation refusée.
public struct ClosedPromptSafetyScreener: PromptSafetyScreening {

    public init() {}

    public func screen(_ input: String, context: CopilotContext) async -> PromptScreeningVerdict {
        .unavailable
    }

    public func screenOutput(_ output: String, context: CopilotContext) async -> PromptScreeningVerdict {
        .unavailable
    }
}
