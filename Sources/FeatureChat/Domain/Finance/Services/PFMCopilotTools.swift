//
//  PFMCopilotTools.swift
//  FeatureChat
//
//  Outils bornés du Copilot — Bloc 5, chapitre 42 (§15, §30).
//

import Foundation
import WaanguCoreKit

/// Explique une anomalie détectée par le backend.
///
/// Premier outil concret de `PFMBoundedTool`. Trois propriétés portent tout :
///
/// - **Il ne fait que lire.** `isReadOnly` est `true`, et rien dans cette
///   implémentation n'appelle une méthode de mutation. Un outil de lecture ne
///   peut pas débiter, et la distinction est déclarée, pas devinée.
/// - **Il ne rédige rien.** Le texte rendu est la clé d'explication produite par
///   le backend. Composer une phrase ici ferait du client l'auteur d'une
///   affirmation financière.
/// - **Il ne répond pas sans source.** Une anomalie sans opération rattachée ne
///   produit aucune réponse : `CopilotAnswer` refuse de se construire, et
///   l'outil rend `nil` plutôt qu'une explication en l'air.
public struct PFMAnomalyExplanationTool: PFMBoundedTool {

    public let toolID = "pfm.anomaly.explain"
    public let isReadOnly = true

    private let pfm: any PersonalFinanceProviding

    public init(pfm: any PersonalFinanceProviding) {
        self.pfm = pfm
    }

    public struct Input: Sendable {
        public let period: PFMPeriod
        public init(period: PFMPeriod) { self.period = period }
    }

    /// Exécute l'outil.
    ///
    /// L'autorisation est vérifiée **avant** toute lecture : un outil qui lit
    /// d'abord et vérifie ensuite a déjà touché aux données de l'utilisateur.
    public func execute(
        input: Input, authorization: ToolAuthorization
    ) async throws -> [CopilotAnswer] {
        guard authorization.permitsExecution else { throw CopilotToolError.notAuthorized }
        guard authorization.toolID == toolID else { throw CopilotToolError.wrongTool }

        let anomalies: [PFMAnomaly]
        switch await pfm.anomalies(period: input.period) {
        case .success(let list): anomalies = list
        case .failure(let error): throw error
        }

        // `compactMap` n'est pas une commodité ici : c'est le filtre qui écarte
        // les anomalies sans opération citable. Elles sont perdues plutôt que
        // racontées sans preuve.
        return anomalies.compactMap { anomaly in
            guard let operationID = anomaly.operationID else { return nil }
            return CopilotAnswer(
                textKey: anomaly.explanationKey,
                sourceOperationIDs: [operationID],
                toolID: toolID,
                correlationID: authorization.correlationID
            )
        }
    }
}

/// Résume la consommation des budgets.
///
/// Ne calcule aucun total : `PFMBudget` porte déjà `spentMinorUnits` et
/// `limitMinorUnits`, rendus par le serveur. L'outil sélectionne, il n'agrège
/// pas — agréger ici produirait un second chiffre pour la même dépense.
public struct PFMBudgetStatusTool: PFMBoundedTool {

    public let toolID = "pfm.budget.status"
    public let isReadOnly = true

    private let pfm: any PersonalFinanceProviding

    public init(pfm: any PersonalFinanceProviding) {
        self.pfm = pfm
    }

    public struct Input: Sendable {
        /// Ne rendre que les budgets dépassés. Le cas courant d'une question
        /// posée au Copilot.
        public let exceededOnly: Bool
        public init(exceededOnly: Bool = true) { self.exceededOnly = exceededOnly }
    }

    public func execute(
        input: Input, authorization: ToolAuthorization
    ) async throws -> [PFMBudget] {
        guard authorization.permitsExecution else { throw CopilotToolError.notAuthorized }
        guard authorization.toolID == toolID else { throw CopilotToolError.wrongTool }

        switch await pfm.budgets() {
        case .success(let budgets):
            return input.exceededOnly ? budgets.filter(\.isExceeded) : budgets
        case .failure(let error):
            throw error
        }
    }
}

/// Ce qui empêche un outil de s'exécuter.
public enum CopilotToolError: Error, Sendable, Equatable {

    /// Aucun accord explicite de l'utilisateur.
    case notAuthorized

    /// L'autorisation vise un autre outil.
    ///
    /// Sans ce contrôle, une autorisation accordée pour lire un budget servirait
    /// à exécuter un tout autre outil — ce qui viderait `ToolAuthorization` de
    /// son sens.
    case wrongTool
}
