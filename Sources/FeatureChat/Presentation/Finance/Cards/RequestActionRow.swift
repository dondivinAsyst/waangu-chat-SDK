//
//  RequestActionRow.swift
//  FeatureChat
//
//  Les gestes d'une demande, partagés par la carte de demande et celle de partage.
//
//  Aucune ligne de `BubbleView` n'est touchée : la carte s'enregistre auprès
//  de `FinancialCardRegistry` — §17, le fil ne change pas par type.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Les gestes que le serveur propose sur une demande — ou sur une part de
/// partage, qui est la même chose vue autrement.
///
/// Partagé par la carte de demande et celle de partage : le second exemplaire
/// aurait fini par oublier un bouton. C'est déjà ce qui est arrivé — la carte
/// de partage n'en affichait aucun, et `PAY_SHARE` n'ouvrait rien.
struct RequestActionRow: View {

    let overlay: MoneyRequestOverlay
    let actions: FinanceRequestActions
    var onSentBubble = false

    /// `true` si le serveur propose au moins un geste.
    static func hasActions(_ overlay: MoneyRequestOverlay) -> Bool {
        overlay.canPay || overlay.canDecline || overlay.canRemind || overlay.canCancel
            || overlay.canIssueLink
    }

    var body: some View {
        HStack(spacing: 8) {
            if overlay.canPay {
                Button { actions.pay(overlay) } label: {
                    Text(FinanceStrings.requestActionPay).frame(maxWidth: .infinity)
                }
                .buttonStyle(RequestCardButtonStyle(prominent: true, onSentBubble: onSentBubble))
            }
            if overlay.canDecline {
                Button { actions.decline(overlay) } label: {
                    Text(FinanceStrings.requestActionDecline).frame(maxWidth: .infinity)
                }
                .buttonStyle(RequestCardButtonStyle(prominent: false, onSentBubble: onSentBubble))
            }
            if overlay.canRemind {
                Button { actions.remind(overlay) } label: {
                    Text(FinanceStrings.requestActionRemind).frame(maxWidth: .infinity)
                }
                .buttonStyle(RequestCardButtonStyle(prominent: false, onSentBubble: onSentBubble))
            }
            if overlay.canCancel {
                Button { actions.cancel(overlay) } label: {
                    Text(FinanceStrings.requestActionCancel).frame(maxWidth: .infinity)
                }
                .buttonStyle(RequestCardButtonStyle(prominent: false, onSentBubble: onSentBubble))
            }
            if overlay.canIssueLink {
                // Icône seule : trois libellés ne tiennent pas dans la bulle.
                Button { actions.issueLink(overlay) } label: {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 20)
                }
                .buttonStyle(RequestCardButtonStyle(prominent: false, onSentBubble: onSentBubble))
                .fixedSize()
                .accessibilityLabel(FinanceStrings.requestActionLink)
            }
        }
    }
}

/// Boutons de la carte de demande — couleur principale seulement, pleine pour
/// l'action attendue, au trait pour les autres.
private struct RequestCardButtonStyle: ButtonStyle {
    let prominent: Bool
    /// La carte est posée sur la bulle **envoyée**, qui garde la couleur des
    /// autres bulles envoyées. Le contour doit suivre le thème de cette bulle :
    /// en couleur principale sur la bulle claire du mode clair, en blanc sur la
    /// bulle sombre du mode sombre — un seul choix disparaissait dans l'autre.
    var onSentBubble = false

    func makeBody(configuration: Configuration) -> some View {
        RequestCardButton(configuration: configuration, prominent: prominent, onSentBubble: onSentBubble)
    }
}

private struct RequestCardButton: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let onSentBubble: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Blanc seulement sur la bulle envoyée **sombre** ; partout ailleurs, la
    /// couleur principale — comme « Refuser » sur une demande reçue.
    private var outline: Color {
        onSentBubble && colorScheme == .dark ? .white : AppColors.primary
    }

    var body: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : outline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background {
                if prominent {
                    Capsule().fill(AppColors.primary)
                } else {
                    Capsule().fill(onSentBubble ? outline.opacity(0.12) : Color.clear)
                        .overlay(Capsule().strokeBorder(outline, lineWidth: onSentBubble ? 1.5 : 1))
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
