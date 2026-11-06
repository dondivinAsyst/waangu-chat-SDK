//
//  FinanceUncertainOutcomeView.swift
//  FeatureChat
//
//  Une opération dont l'issue est inconnue — Bloc 10, §80 et §21.E.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Ce qu'on montre quand on ne sait pas si l'argent est parti.
///
/// **Ni « réussi », ni « échoué ».** Les deux seraient une affirmation que le
/// client ne peut pas faire. Les écrans affichaient jusqu'ici un échec, ce qui
/// invitait à repayer une opération peut-être déjà exécutée.
///
/// Deux cas, selon ce que l'on possède :
///
/// - **Une référence serveur.** L'objet est inscrit comme ambigu et la
///   réconciliation le reprend ; l'écran est celui de la soumission, qui sait
///   relire l'état.
/// - **Aucune référence.** Rien à relire. En revanche la clé d'idempotence est
///   conservée — voir `FinanceOperationKeys` — donc **soumettre de nouveau ne
///   peut pas exécuter une seconde fois** : le serveur rend l'issue de la
///   première tentative. C'est ce qui rend honnête le libellé « vérifier de
///   nouveau » sur un geste qui renvoie la requête.
struct FinanceUncertainOutcomeView: View {

    let reference: FinancialReference?

    /// Renvoie la même opération, sous la même clé. `nil` ⇒ bouton absent.
    let onCheckAgain: (() -> Void)?

    let onDismiss: () -> Void

    var body: some View {
        if let reference {
            FinanceSubmissionView(reference: reference,
                                  title: FinanceStrings.flowVerifyingTitle,
                                  detail: FinanceStrings.errorMessage(.timeoutUnknown),
                                  animation: .verifying,
                                  onDismiss: onDismiss)
        } else {
            FinancePage {
                VStack(spacing: 14) {
                    FinanceStatusAnimation(.verifying)
                        .frame(width: 112, height: 112)

                    Text(FinanceStrings.flowVerifyingTitle)
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(FinanceStrings.errorMessage(.timeoutUnknown))
                        .font(.body)
                        .foregroundStyle(AppColors.subtitleGray)
                        .multilineTextAlignment(.center)

                    if onCheckAgain != nil {
                        // Dit explicitement pourquoi le geste est sans risque :
                        // sans cette phrase, « vérifier de nouveau » après une
                        // consigne de ne pas relancer se lirait comme une
                        // contradiction, et l'utilisateur hésiterait à juste titre.
                        Label(FinanceStrings.flowCheckAgainSafe, systemImage: "checkmark.shield")
                            .font(.footnote)
                            .foregroundStyle(AppColors.subtitleGray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .accessibilityElement(children: .combine)
            } actions: {
                if let onCheckAgain {
                    CustomButton(title: FinanceStrings.flowCheckAgain,
                                 icon: "arrow.clockwise", action: onCheckAgain)
                }
                Button(FinanceStrings.flowReturn, action: onDismiss)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.vertical, 8)
            }
        }
    }
}
