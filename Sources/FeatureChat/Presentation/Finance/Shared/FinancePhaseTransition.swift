//
//  FinancePhaseTransition.swift
//  FeatureChat
//
//  Le passage d'une étape à la suivante, animé.
//

import SwiftUI

/// Nom de cas d'une énumération, sans ses valeurs associées.
///
/// `String(describing:)` sérialiserait aussi les valeurs — un devis entier, un
/// bénéficiaire résolu — à chaque évaluation du corps. Le miroir d'une
/// énumération à valeurs associées expose un seul enfant, dont le **label est le
/// nom du cas** ; pour un cas sans valeur il n'y a pas d'enfant, et la
/// description est alors déjà le nom du cas.
///
/// Le nom seul est ce qu'il faut : l'identité doit changer quand on passe de la
/// saisie au récapitulatif, **pas** quand le devis se rafraîchit à l'intérieur
/// de la même étape — sinon l'écran se reconstruirait sous les doigts.
func financeStepKey<Phase>(_ phase: Phase) -> String {
    let mirror = Mirror(reflecting: phase)
    if let label = mirror.children.first?.label { return label }
    return String(describing: phase)
}

private struct FinancePhaseTransition: ViewModifier {

    let key: String

    /// Le mouvement latéral disparaît si le système demande moins d'animation ;
    /// le fondu, lui, reste : sans aucune transition l'écran change sans qu'on
    /// voie qu'il a changé.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Le conteneur **ne change jamais d'identité** ; le contenu, si.
        //
        // Première version : `.id(key)` puis `.animation(_:value: key)` sur la
        // même vue. Poser l'animation après l'identité ne suffit pas — quand la
        // clé change, SwiftUI détruit le sous-arbre et le reconstruit, et le
        // modificateur d'animation repart sans valeur précédente à comparer. La
        // transaction n'était donc jamais animée, et l'étape suivante
        // apparaissait d'un coup. C'est ce qui se voyait sur Dépôt et Retrait.
        //
        // Ici le `ZStack` survit au changement de clé : c'est lui qui porte
        // l'animation, et le retrait/insertion du contenu s'y inscrit.
        ZStack(alignment: .top) {
            // Ancre de dimension : sans elle, la pile se réduit au contenu
            // entrant pendant la transition et l'écran sursaute.
            Color.clear

            content
                .id(key)
                .transition(transition)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .snappy(duration: 0.3), value: key)
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

extension View {

    /// Anime le passage d'une étape de parcours à la suivante.
    ///
    /// Les parcours financiers avancent par `switch` sur une énumération
    /// d'étapes. SwiftUI y remplace bien une vue par une autre, mais sans
    /// transaction animée ni identité stable : le récapitulatif apparaissait
    /// instantanément à la place de la saisie, sans qu'aucun mouvement ne dise
    /// qu'on venait d'avancer — ni dans quel sens.
    ///
    /// Entrée par la droite, sortie par la gauche : le sens de lecture du
    /// parcours. Le retour, lui, joue la transition inverse tout seul.
    func financePhase<Phase>(_ phase: Phase) -> some View {
        modifier(FinancePhaseTransition(key: financeStepKey(phase)))
    }
}
