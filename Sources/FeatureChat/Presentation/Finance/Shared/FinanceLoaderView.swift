//
//  FinanceLoaderView.swift
//  FeatureChat
//
//  L'attente de l'accueil Paiements.
//

import SwiftUI
import UIKit
import Lottie
import WaanguSharedUI

/// Le chargeur de l'accueil Paiements : une animation Lottie, recolorée à la
/// couleur de marque.
///
/// Un seul visuel pour toutes les attentes de l'accueil — premier chargement et
/// nouvelle tentative après une indisponibilité. Deux styles d'attente sur le
/// même écran se liraient comme deux états différents.
struct FinanceLoaderView: View {

    /// Retard avant apparition. Un Hub en cache répond presque aussitôt, et un
    /// chargeur qui clignote une fraction de seconde fait plus désordre que
    /// pas de chargeur du tout.
    var appearanceDelay: Duration = .milliseconds(300)

    @State private var isVisible = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            animation
                .frame(width: 400, height: 400)
                .accessibilityHidden(true)

//            Text(FinanceStrings.walletLoading)
//                .font(.system(size: 14))
//                .foregroundStyle(AppColors.subtitleGray)
//                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.walletCanvas)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: isVisible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(FinanceStrings.walletLoading)
        .task {
            try? await Task.sleep(for: appearanceDelay)
            isVisible = true
        }
    }

    // MARK: - Animation

    @ViewBuilder
    private var animation: some View {
        if let loaded = FinanceLoaderAsset.animation {
            let view = FinanceLoaderAsset.recolored(LottieView(animation: loaded).resizable(),
                                                    for: colorScheme)
            // Mouvement réduit : une image fixe, lisible, au lieu d'une boucle.
            if reduceMotion {
                view.currentProgress(0.35)
            } else {
                view.playing(loopMode: .loop)
            }
        } else {
            // Ressource absente du bundle : jamais un vide, l'indicateur système.
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColors.primary)
        }
    }
}

// MARK: - Ressource

/// L'animation livrée par le design (« Wallet Move »), et son passage aux
/// couleurs Waangu.
///
/// Un portefeuille dont deux billets basculent, en boucle de 1,4 s. Le fichier
/// d'origine est laissé intact — bleus `#2180DE` / `#5CADFF` et fermoir gris
/// `#333C45` — et recoloré à l'exécution : le prochain export du design
/// remplace le fichier sans perdre la charte, et les couleurs suivent le mode
/// sombre.
enum FinanceLoaderAsset {

    static let animation: LottieAnimation? =
        LottieAnimation.named("finance_loader", bundle: .module)
        ?? LottieAnimation.named("finance_loader", bundle: .module, subdirectory: "Finance")

    /// Corps du portefeuille `#2180DE` : couleur de marque pleine.
    static let bodyKeypaths = ["Wallet Outlines 4.Group 2.Fill 1.Color"]

    /// Les deux billets `#5CADFF` : teinte claire de la couleur de marque.
    static let notesKeypaths = [
        "Wallet Outlines 3.Group 3.Fill 1.Color",
        "Wallet Outlines 2.Group 4.Fill 1.Color",
    ]

    /// Fermoir `#333C45`. Il suit la couleur de texte : sombre sur fond clair,
    /// clair sur fond sombre — le gris d'origine disparaîtrait en mode sombre.
    static let claspKeypaths = ["Wallet Outlines 4.Group 1.Fill 1.Color"]

    static func recolored(_ view: LottieView<EmptyView>, for scheme: ColorScheme) -> LottieView<EmptyView> {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let primary = UIColor(AppColors.primary).resolvedColor(with: traits)
        let clasp = UIColor(AppColors.textPrimary).resolvedColor(with: traits)

        let providers: [(ColorValueProvider, [String])] = [
            (ColorValueProvider(primary.lottieColorValue), bodyKeypaths),
            (ColorValueProvider(lightened(primary, by: 0.45).lottieColorValue), notesKeypaths),
            (ColorValueProvider(clasp.lottieColorValue), claspKeypaths),
        ]

        var result = view
        for (provider, keypaths) in providers {
            for keypath in keypaths {
                result = result.valueProvider(provider, for: AnimationKeypath(keypath: keypath))
            }
        }
        return result
    }

    /// Mélange opaque avec le blanc, pas une transparence : les deux billets se
    /// chevauchent, et une couleur translucide foncerait leur recouvrement.
    static func lightened(_ color: UIColor, by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * amount,
                       green: g + (1 - g) * amount,
                       blue: b + (1 - b) * amount,
                       alpha: a)
    }
}

#Preview("Chargeur") {
    FinanceLoaderView(appearanceDelay: .zero)
}
