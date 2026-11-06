//
//  CopilotActionStateMachine.swift
//  CoreKit
//
//  Cycle de vie d'une action financière initiée par le Copilot — Bloc 7, §54.6.
//
//  S'adosse à ``FinancialObjectStateMachine`` (Bloc 2 §9.4) : même forme de
//  verdict, même refus de deviner. La différence est l'objet gardé — là où le
//  Bloc 2 garde l'état d'une opération côté backend, celui-ci garde le chemin
//  qui mène à son déclenchement.
//

import Foundation

/// Où en est une action proposée par le Copilot.
public enum CopilotActionState: String, Sendable, Hashable, Codable, CaseIterable {

    /// Le modèle a proposé quelque chose. **Rien n'est engagé.**
    case suggested            = "SUGGESTED"

    /// Il manque une donnée ; le Copilot la demande.
    case clarifying           = "CLARIFYING"

    /// Un aperçu chiffré a été construit à partir de valeurs autoritatives.
    case prepared             = "PREPARED"

    /// L'aperçu est devant l'utilisateur.
    case awaitingConfirmation = "AWAITING_CONFIRMATION"

    /// L'utilisateur a accepté cet aperçu précis.
    case confirmed            = "CONFIRMED"

    /// Une authentification renforcée est demandée.
    case awaitingStepUp       = "AWAITING_STEP_UP"

    /// Le step-up a été fourni et attesté.
    case stepUpSatisfied      = "STEP_UP_SATISFIED"

    /// Le permis lié a été émis.
    case permitIssued         = "PERMIT_ISSUED"

    /// L'ordre est parti.
    case executing            = "EXECUTING"

    case executed             = "EXECUTED"

    /// L'utilisateur a refusé.
    case declined             = "DECLINED"

    /// Abandonné sans décision — écran quitté, session close, aperçu périmé.
    case abandoned            = "ABANDONED"

    case failed               = "FAILED"

    case unknown              = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CopilotActionState(rawValue: raw) ?? .unknown
    }

    /// Plus rien ne part d'ici.
    public var isTerminal: Bool {
        switch self {
        case .executed, .declined, .abandoned, .failed: return true
        default:                                        return false
        }
    }

    /// L'argent a-t-il pu bouger à partir de cet état ?
    ///
    /// Sert à décider ce qu'on affiche après une coupure : sur `executing`, on
    /// n'affirme **ni** succès **ni** échec — on requête l'état, comme le veut
    /// `FinanceError.timeoutUnknown`.
    public var mayHaveMovedFunds: Bool {
        self == .executing || self == .executed
    }
}

/// Décide si une action du Copilot peut passer d'un état à l'autre.
///
/// L'intérêt n'est pas de décrire un joli graphe. C'est qu'**aucune arête ne
/// mène de `suggested` à `executing`**. Le §54.2 exige qu'une inférence ne
/// puisse pas déclencher une mutation ; ``FinancialAuthority`` l'impose sur les
/// valeurs, cette machine l'impose sur le chemin. Les deux sont nécessaires :
/// des valeurs autoritatives exécutées sans confirmation restent une exécution
/// non consentie.
public enum CopilotActionStateMachine {

    public enum Verdict: Equatable, Sendable {

        case allowed

        /// Transition refusée. L'action **garde son état**.
        case forbidden(reason: String)

        /// Transition qu'aucune règle de cette version ne décrit. Ni appliquée,
        /// ni rejetée — requêtée, comme au Bloc 2.
        case unknown
    }

    /// Le graphe, en entier.
    ///
    /// Écrit en toutes lettres plutôt que dérivé de règles : un graphe
    /// d'autorisation doit se relire, et une règle qui se calcule est une règle
    /// dont personne ne vérifie le résultat.
    private static let transitions: [CopilotActionState: Set<CopilotActionState>] = [

        .suggested:            [.clarifying, .prepared, .declined, .abandoned],
        .clarifying:           [.clarifying, .prepared, .declined, .abandoned],

        // Un aperçu peut être reconstruit — un taux bouge, l'utilisateur change
        // un montant — mais chaque reconstruction repart d'un aperçu neuf.
        .prepared:             [.awaitingConfirmation, .prepared, .declined, .abandoned],

        .awaitingConfirmation: [.confirmed, .declined, .abandoned,
                                // L'aperçu a expiré pendant que l'utilisateur
                                // lisait : on le refait, on ne l'exécute pas.
                                .prepared],

        .confirmed:            [.awaitingStepUp, .permitIssued, .abandoned, .failed],
        .awaitingStepUp:       [.stepUpSatisfied, .declined, .abandoned, .failed],
        .stepUpSatisfied:      [.permitIssued, .abandoned, .failed],
        .permitIssued:         [.executing, .abandoned, .failed],
        .executing:            [.executed, .failed],

        // États terminaux. Une nouvelle tentative est une nouvelle action, avec
        // sa propre clé d'idempotence — jamais une réouverture de celle-ci.
        .executed:             [],
        .declined:             [],
        .abandoned:            [],
        .failed:               []
    ]

    /// - Parameters:
    ///   - current: état connu.
    ///   - next: état visé.
    public static func verdict(
        from current: CopilotActionState,
        to next: CopilotActionState
    ) -> Verdict {

        // L'inconnu se teste avant le raccourci d'égalité : sans cela,
        // `unknown -> unknown` serait « autorisé », et un état que ce client ne
        // sait pas lire se figerait en se validant lui-même.
        guard current != .unknown, next != .unknown else { return .unknown }

        // Réappliquer le même état ne change rien — sauf pour les deux états
        // qui se répètent en portant un contenu neuf : une question de plus,
        // un aperçu recalculé.
        if current == next, current != .clarifying, current != .prepared {
            return .allowed
        }

        guard let allowed = transitions[current] else { return .unknown }

        if allowed.contains(next) { return .allowed }

        if current.isTerminal {
            return .forbidden(reason: "copilot.action.terminal_state")
        }

        return .forbidden(reason: "copilot.action.illegal_transition")
    }

    /// Les états depuis lesquels une exécution peut partir.
    ///
    /// Un seul. Exposé pour que le test du §54.6 puisse l'affirmer sans relire
    /// le graphe à la main.
    public static var statesPermittingExecution: Set<CopilotActionState> {
        Set(transitions.filter { $0.value.contains(.executing) }.map(\.key))
    }

    /// Vérifie la dernière porte avant l'ordre, quel que soit le chemin suivi.
    ///
    /// Le graphe seul ne suffit pas : il dit qu'on arrive à `executing` depuis
    /// `permitIssued`, pas que le permis est **celui de cette action**. Les
    /// trois preuves sont donc revérifiées ici, à l'instant du départ.
    ///
    /// - Parameters:
    ///   - state: état courant.
    ///   - hasConfirmation: l'utilisateur a accepté un aperçu.
    ///   - hasStepUpAttestation: le step-up exigé a été fourni, ou n'était pas
    ///     exigé.
    ///   - hasValidPermit: ``BoundExecutionPermit/validate(for:snapshot:consumedNonces:now:)``
    ///     n'a rien rejeté.
    public static func mayExecute(
        state: CopilotActionState,
        hasConfirmation: Bool,
        hasStepUpAttestation: Bool,
        hasValidPermit: Bool
    ) -> Bool {
        state == .permitIssued
            && hasConfirmation
            && hasStepUpAttestation
            && hasValidPermit
    }
}
