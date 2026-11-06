//
//  StepUpRequirement.swift
//  CoreKit
//
//  Combinaison de l'exigence backend et du risque local — tâche 11.6b.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §1.4b.

import Foundation

/// Détermine le niveau de step-up réellement exigé pour une opération.
///
/// **Le risque local ne peut qu'élever, jamais abaisser.** C'est la seule
/// propriété qui rend acceptable de faire tourner une évaluation de risque sur
/// l'appareil qu'elle surveille : un client compromis qui renverrait « risque
/// nul » n'obtient rien, puisque le plancher backend tient. Au pire il renonce à
/// sa propre prudence supplémentaire.
///
/// L'inverse — laisser le client abaisser l'exigence — transformerait chaque
/// appareil jailbreaké en autorisation de paiement.
public enum StepUpRequirement {

    /// Niveau effectif : le plus élevé des deux.
    ///
    /// - Parameters:
    ///   - backendRequired: exigence décidée par le backend. Fait plancher.
    ///   - localAssessment: recommandation issue des signaux de l'appareil.
    ///     `nil` quand aucune évaluation n'est disponible — auquel cas le
    ///     plancher backend s'applique tel quel, jamais un défaut permissif.
    public static func effectiveLevel(
        backendRequired: StepUpLevel,
        localAssessment: SessionRiskAssessment?
    ) -> StepUpLevel {
        guard let localAssessment else { return backendRequired }
        return max(backendRequired, localAssessment.requiredStepUp)
    }

    /// `true` si le risque local a élevé l'exigence au-delà du plancher backend.
    ///
    /// À journaliser (`finance.security.step_up`) : c'est le signal qui permet de
    /// mesurer combien d'opérations sont durcies par des signaux locaux, et de
    /// détecter un seuil mal calibré qui durcirait tout.
    public static func wasRaisedLocally(
        backendRequired: StepUpLevel,
        localAssessment: SessionRiskAssessment?
    ) -> Bool {
        effectiveLevel(backendRequired: backendRequired, localAssessment: localAssessment)
            > backendRequired
    }
}
