// NavigationKit — NavigationTransition.swift
// Transitions de navigation standardisées pour une cohérence visuelle globale.

import SwiftUI

// MARK: - NavigationTransitionStyle

/// Styles de transition disponibles dans l'application.
/// Centralise les animations pour garantir la cohérence entre features.
public enum NavigationTransitionStyle: Sendable {
    /// Transition native SwiftUI (push/pop standard iOS).
    case `default`
    /// Slide horizontal — utilisé pour les flows séquentiels (onboarding, KYC).
    case slide
    /// Fade — utilisé pour les changements de contexte majeurs.
    case fade
    /// Cover vertical — utilisé pour les sheets complexes plein écran.
    case coverVertical
    /// Aucune animation — utilisé pour les redirections programmatiques (deep link).
    case none
}

// MARK: - View Modifier

public extension View {
    /// Applique le style de transition NavigationKit à cette vue.
    @ViewBuilder
    func navigationTransition(_ style: NavigationTransitionStyle) -> some View {
        switch style {
        case .default:
            self
        case .slide:
            self.transition(.slide)
        case .fade:
            self.transition(.opacity)
        case .coverVertical:
            self.transition(
                .asymmetric(
                    insertion: .move(edge: .bottom),
                    removal: .move(edge: .bottom)
                )
            )
        case .none:
            self.transaction { $0.animation = nil }
        }
    }
}
