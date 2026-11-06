//
//  FinanceFailureView.swift
//  FeatureChat
//
//  Écran d'échec d'une opération financière.
//

import SwiftUI
import UIKit
import Lottie
import WaanguSharedUI

/// Une opération refusée ou impossible — et ce qu'on peut faire ensuite.
///
/// Remplace une icône grise et une phrase seule, qui ne disaient ni si de
/// l'argent avait bougé, ni quoi faire. Dans l'ordre : ce qui s'est passé
/// (titre), pourquoi (le message du serveur, tel quel), si rien n'a été débité,
/// puis les deux gestes possibles — réessayer, ou revenir à la conversation.
///
/// **À n'utiliser que pour une issue tranchée.** Une issue inconnue (délai
/// dépassé après envoi) passe par l'écran de vérification, jamais par celui-ci :
/// « rien n'a été débité » y serait une promesse sans preuve.
///
/// Sans aplat teinté : l'animation porte l'attention, la typographie la
/// hiérarchie. Couleur principale seulement.
struct FinanceFailureView: View {

    let title: String
    /// Raison — celle que le serveur a rédigée, dans la langue de l'app.
    let message: String
    /// Vrai quand l'échec prouve qu'aucun argent n'a bougé.
    var nothingCharged = true
    /// Référence de l'opération, pour le support. `nil` ⇒ pas de ligne.
    var reference: String?
    /// Vrai quand la session de paiement est verrouillée : le cadenas
    /// remplace l'avertissement.
    var locked = false
    /// `nil` ⇒ pas de bouton « Réessayer » : rien à retenter.
    var onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Group {
                    if locked {
                        FinanceStatusAnimation(.locked)
                    } else {
                        FinanceWarningAnimation()
                    }
                }
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.subtitleGray)
                        .fixedSize(horizontal: false, vertical: true)

                    if nothingCharged {
                        Label(FinanceStrings.failureNothingCharged, systemImage: "checkmark.shield")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppColors.primary)
                            .padding(.top, 4)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                if let reference {
                    VStack(spacing: 0) {
                        FinanceHairline()
                        FinanceReferenceRow(reference: reference)
                        FinanceHairline()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                if let onRetry {
                    CustomButton(title: FinanceStrings.failureRetry, icon: "arrow.clockwise", action: onRetry)
                    CustomButton(title: FinanceStrings.flowReturn, style: .ghost, action: onDismiss)
                } else {
                    CustomButton(title: FinanceStrings.flowReturn, action: onDismiss)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.walletCanvas)
    }
}

// MARK: - Animation

/// L'icône « Warning Status » : un cercle qui se dessine, puis le point
/// d'exclamation qui oscille — une fois, sans boucle : un échec ne clignote pas.
///
/// Le fichier est livré tel quel et recoloré à l'exécution, comme le chargeur :
/// ses bleus deviennent la couleur principale, en clair comme en sombre. Le
/// point d'exclamation garde sa teinte claire, lisible sur le disque plein.
struct FinanceWarningAnimation: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let animation = FinanceWarningAsset.animation {
            let view = FinanceWarningAsset.recolored(LottieView(animation: animation).resizable(),
                                                     for: colorScheme)
            // Mouvement réduit : l'image finale, sans la séquence.
            if reduceMotion {
                view.currentProgress(1)
            } else {
                view.playing(loopMode: .playOnce)
            }
        } else {
            // Ressource absente du bundle : l'icône système, jamais un vide.
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColors.primary)
                .padding(20)
        }
    }
}

enum FinanceWarningAsset {

    static let animation: LottieAnimation? =
        LottieAnimation.named("finance_warning", bundle: .module)
        ?? LottieAnimation.named("finance_warning", bundle: .module, subdirectory: "Finance")

    /// Disque plein et contours foncés : la couleur principale.
    static let primaryKeypaths = [
        "Yellow-Circle.**.Color",
        "DarkYellow-CircleStroke.**.Color",
        "DarkYellow-CircleExclamationMark.**.Color",
        "DarkYellow-BodyExclamationMark.**.Color",
    ]

    /// Contours clairs, dessinés juste avant : la couleur principale éclaircie.
    static let lightKeypaths = [
        "LightYellow-CircleStroke.**.Color",
        "LightYellow-CircleExclamationMark.**.Color",
        "LightYellow-BodyExclamationMark.**.Color",
    ]

    static func recolored(_ view: LottieView<EmptyView>, for scheme: ColorScheme) -> LottieView<EmptyView> {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let primary = UIColor(AppColors.primary).resolvedColor(with: traits)
        let light = FinanceLoaderAsset.lightened(primary, by: 0.45)

        var result = view
        for keypath in primaryKeypaths {
            result = result.valueProvider(ColorValueProvider(primary.lottieColorValue),
                                          for: AnimationKeypath(keypath: keypath))
        }
        for keypath in lightKeypaths {
            result = result.valueProvider(ColorValueProvider(light.lottieColorValue),
                                          for: AnimationKeypath(keypath: keypath))
        }
        return result
    }
}

#Preview("Échec") {
    FinanceFailureView(title: "Paiement non effectué",
                       message: "Confirmation fingerprint does not match context",
                       onRetry: {}, onDismiss: {})
}
