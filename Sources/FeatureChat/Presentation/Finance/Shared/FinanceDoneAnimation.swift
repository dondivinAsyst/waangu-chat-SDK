//
//  FinanceDoneAnimation.swift
//  FeatureChat
//

import SwiftUI
import UIKit
import Lottie
import WaanguSharedUI

/// L'animation « Done » : un disque qui apparaît, puis la coche qui se trace.
///
/// **Réservée à un succès prouvé** — une carte `settled`, c'est-à-dire terminée
/// **et** vérifiée (`visualSuccessFinal` côté serveur). Jamais sur « transmis »,
/// « en cours » ou « vérification » : une coche avant la preuve est le faux
/// succès que le Bloc 1 interdit. Voir `FinancialCardPresentation.announcesSuccess`.
///
/// Jouée une fois. Le disque vert d'origine est recoloré à la couleur
/// principale — jamais de vert dans l'app ; la coche reste blanche.
struct FinanceDoneAnimation: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let animation = FinanceDoneAsset.animation {
            let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
            let primary = UIColor(AppColors.primary).resolvedColor(with: traits)
            let view = LottieView(animation: animation)
                .resizable()
                .valueProvider(ColorValueProvider(primary.lottieColorValue),
                               for: AnimationKeypath(keypath: FinanceDoneAsset.discKeypath))
            // Mouvement réduit : la coche finale, sans la séquence.
            if reduceMotion {
                view.currentProgress(1)
            } else {
                view.playing(loopMode: .playOnce)
            }
        } else {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColors.primary)
        }
    }
}

enum FinanceDoneAsset {

    static let animation: LottieAnimation? =
        LottieAnimation.named("finance_done", bundle: .module)
        ?? LottieAnimation.named("finance_done", bundle: .module, subdirectory: "Finance")

    /// Le disque (vert `#00C233` dans le fichier).
    static let discKeypath = "Shape Layer 1.Ellipse 1.Fill 1.Color"
}

#Preview("Succès") {
    FinanceDoneAnimation().frame(width: 96, height: 96)
}
