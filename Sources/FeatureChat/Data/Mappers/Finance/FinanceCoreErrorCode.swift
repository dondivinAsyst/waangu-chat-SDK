//
//  FinanceCoreErrorCode.swift
//  FeatureChat
//
//  Codes CF_001 … CF_073 — INTEGRATION_CHAT_FINANCE.md, « Erreurs CF — mapping UI ».
//

import Foundation
import WaanguCoreKit

/// Code métier Chat Core. L'interface se branche **sur le code**, jamais sur le texte.
///
/// Un code inconnu de cette version reste représentable : il ne devient ni un
/// succès ni un échec établi, et `clientAction` le traite comme une indisponibilité.
struct FinanceCoreErrorCode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    var description: String { rawValue }

    /// Ce que le client doit faire — colonne « UI » du contrat.
    enum ClientAction: Equatable, Sendable {
        /// Issue incertaine : `POST /intent/requery`, **jamais** rappeler execute.
        case requery
        /// Devis expiré ou invalidé : `POST …/quote/refresh`.
        case refreshQuote
        /// Empreinte ou permis consommé, expiré ou divergent : refaire le prepare.
        case prepareAgain
        /// Verrou d'écriture : `POST /financial/session/resume`.
        case resumeSession
        /// Époque de sécurité périmée : se reconnecter.
        case relogin
        /// Capacité périmée : `POST /capability/refresh`.
        case refreshCapability
        /// Époque d'appartenance périmée (CF_074) : relire la conversation,
        /// puis refaire l'appel avec l'époque courante.
        case resyncMembership
        /// Même clé d'idempotence, charge différente : nouvelle clé.
        case newIdempotencyKey
        /// Service ou capacité fermé : bannière, pas de nouvel essai.
        case showUnavailable
        /// Gel conformité : afficher le gel, **ne pas** ouvrir le clavier.
        case showComplianceHold
        /// Demandé, pas final (CF_046) : l'état se relit.
        case pendingNotFinal
        /// Donnée à corriger par l'utilisateur ou à redemander au serveur.
        case correctInput
        /// Refus établi, rien à relancer.
        case none
    }

    var clientAction: ClientAction {
        Self.actions[rawValue] ?? .showUnavailable
    }

    /// Traduction vers la taxonomie financière existante, consommée par les écrans.
    ///
    /// Le code reste disponible à côté : un parcours qui a besoin d'une nuance
    /// que `FinanceError` n'exprime pas — CF_046, CF_066 — lit `clientAction`.
    var financeError: FinanceError {
        switch rawValue {
        case "CF_017", "CF_024":                         return .timeoutUnknown
        case "CF_029", "CF_030", "CF_031",
             "CF_022", "CF_025", "CF_032", "CF_036",
             "CF_039", "CF_040":                         return .expired
        case "CF_015":                                   return .executionPermitConsumed
        case "CF_016":                                   return .executionPermitExpired
        case "CF_021", "CF_023":                         return .confirmationStale(fields: [])
        case "CF_010":                                   return .complianceBlocked(displayReason: nil)
        case "CF_071", "CF_043":                         return .duplicate
        case "CF_070":                                   return .unauthorized
        case "CF_028":                                   return .recipientUnresolved(reason: .notFound)
        case "CF_044":                                   return .recipientUnresolved(reason: .notFound)
        case "CF_003", "CF_004", "CF_005", "CF_006", "CF_012",
             "CF_026", "CF_053", "CF_057", "CF_069", "CF_072":
                                                         return .capabilityUnavailable
        case "CF_051", "CF_052", "CF_056", "CF_063", "CF_068":
                                                         return .providerUnavailable
        case "CF_013", "CF_014", "CF_019", "CF_033", "CF_034",
             "CF_035", "CF_038", "CF_045", "CF_046", "CF_047",
             "CF_058", "CF_064", "CF_073", "CF_074":     return .conflict
        case "CF_049", "CF_050", "CF_054", "CF_060", "CF_062",
             "CF_065", "CF_066", "CF_067":               return .forbidden
        case "CF_020":                                   return .validation(field: "amount")
        // « Financial intent not found » : distinct des autres validations, pour
        // que le magasin oublie un objet que le serveur ne connaît pas.
        case "CF_011":                                   return .financialObjectNotFound
        case "CF_001", "CF_002", "CF_007", "CF_008", "CF_009",
             "CF_018", "CF_027", "CF_037", "CF_041",
             "CF_042", "CF_048", "CF_055", "CF_059", "CF_061":
                                                         return .validation(field: nil)
        default:                                         return .providerUnavailable
        }
    }

    private static let actions: [String: ClientAction] = {
        var table: [String: ClientAction] = [:]
        func set(_ action: ClientAction, _ codes: String...) { codes.forEach { table[$0] = action } }

        set(.requery, "CF_017", "CF_024")
        set(.refreshQuote, "CF_029", "CF_030", "CF_031")
        set(.prepareAgain, "CF_015", "CF_016", "CF_021", "CF_022", "CF_023")
        set(.resumeSession, "CF_066")
        set(.relogin, "CF_070")
        set(.refreshCapability, "CF_006", "CF_012")
        set(.resyncMembership, "CF_074")
        set(.newIdempotencyKey, "CF_071")
        set(.showComplianceHold, "CF_010")
        set(.pendingNotFinal, "CF_046")
        set(.showUnavailable,
            "CF_003", "CF_004", "CF_005", "CF_026", "CF_051", "CF_052", "CF_053",
            "CF_056", "CF_057", "CF_063", "CF_067", "CF_068", "CF_069", "CF_072")
        set(.correctInput,
            "CF_007", "CF_018", "CF_020", "CF_025", "CF_027", "CF_028", "CF_032",
            "CF_036", "CF_037", "CF_039", "CF_040", "CF_041", "CF_042", "CF_044",
            "CF_048", "CF_055", "CF_059", "CF_065")
        set(.none,
            "CF_001", "CF_002", "CF_008", "CF_009", "CF_011", "CF_013", "CF_014",
            "CF_019", "CF_033", "CF_034", "CF_035", "CF_038", "CF_043", "CF_045",
            "CF_047", "CF_049", "CF_050", "CF_054", "CF_058", "CF_060", "CF_061",
            "CF_062", "CF_064", "CF_073")
        return table
    }()

    /// `true` si le code a une action décidée dans la table.
    static func isDeclared(_ raw: String) -> Bool { actions[raw] != nil }

    /// Tous les codes du contrat — CF_001 à CF_074.
    ///
    /// `CF_074` — « conversation membership epoch is stale » — a d'abord été
    /// rencontré en réponse avant d'être publié ; le contrat le documente
    /// désormais, et il rejoint les autres.
    static let contractCodes: [String] = (1...74).map { String(format: "CF_%03d", $0) }

    /// Codes **émis par le serveur** mais absents du contrat. Aucun aujourd'hui.
    static let undocumentedCodes: [String] = []
}
