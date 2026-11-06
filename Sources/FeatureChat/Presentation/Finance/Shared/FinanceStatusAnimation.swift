//
//  FinanceStatusAnimation.swift
//  FeatureChat
//
//  Les icônes animées des états d'une opération.
//

import SwiftUI
import UIKit
import Lottie
import WaanguSharedUI

/// Une icône animée par état — jamais deux visuels pour le même état.
///
/// Les fichiers sont livrés tels quels et recolorés à l'exécution : leurs
/// bleus, verts et noirs deviennent la couleur principale, en clair comme en
/// sombre. Seule exception : le sable du sablier est un calque plein, que Lottie
/// ne sait pas recolorer — la couleur principale est inscrite dans le fichier.
enum FinanceStatusAnimationKind {
    /// Transmis, pas encore réglé.
    case submitted
    /// Issue inconnue : on vérifie.
    case verifying
    /// Carte en attente de sa lecture serveur.
    case pending
    /// Demande en attente du payeur.
    case waiting
    /// Recherche du destinataire.
    case searching
    /// Session de paiement verrouillée.
    case locked
    /// Réglé **et** vérifié — jamais avant.
    case settled

    fileprivate var resource: String {
        switch self {
        case .submitted:    return "finance_submitted"
        case .verifying:    return "finance_verifying"
        case .pending:      return "finance_pending"
        case .waiting:      return "finance_waiting"
        case .searching:    return "finance_searching"
        case .locked:       return "finance_locked"
        case .settled:      return "finance_settled"
        }
    }

    /// Seuls les chargeurs bouclent — la recherche du destinataire et la carte
    /// dont on attend la lecture. Une icône d'état se joue une fois et reste
    /// sur sa dernière image.
    fileprivate var isLoader: Bool { self == .searching || self == .pending }

    fileprivate var playback: LottiePlaybackMode.PlaybackMode {
        switch self {
        case .searching, .pending:
            return .fromProgress(0, toProgress: 1, loopMode: .loop)
        case .locked:
            // Le cadenas se ferme vers l'image 50 et se rouvre à 105 : on
            // s'arrête fermé.
            return .fromFrame(0, toFrame: 95, loopMode: .playOnce)
        default:
            return .fromProgress(0, toProgress: 1, loopMode: .playOnce)
        }
    }

    /// Image fixe quand le mouvement est réduit : la dernière image d'une
    /// icône d'état, une image lisible d'un chargeur.
    fileprivate var stillProgress: AnimationProgressTime {
        switch self {
        case .locked:  return 0.7
        default:       return isLoader ? 0.5 : 1
        }
    }

    /// Le cadenas occupe un huitième de sa toile : on l'agrandit dans le cadre.
    fileprivate var zoom: CGFloat { self == .locked ? 4.5 : 1 }

    /// Icône système si la ressource manque — jamais un vide.
    fileprivate var fallbackSymbol: String {
        switch self {
        case .submitted, .pending, .waiting: return "clock"
        case .verifying:    return "hourglass"
        case .searching:    return "magnifyingglass"
        case .locked:       return "lock.fill"
        case .settled:      return "checkmark.circle.fill"
        }
    }

    fileprivate var animation: LottieAnimation? {
        FinanceStatusAnimationCache.animation(named: resource)
    }
}

struct FinanceStatusAnimation: View {

    let kind: FinanceStatusAnimationKind

    init(_ kind: FinanceStatusAnimationKind) { self.kind = kind }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let animation = kind.animation {
            GeometryReader { proxy in
                let view = Self.recolored(LottieView(animation: animation).resizable(),
                                          kind: kind, scheme: colorScheme)
                Group {
                    if reduceMotion {
                        view.currentProgress(kind.stillProgress)
                    } else {
                        view.playing(kind.playback)
                    }
                }
                .frame(width: proxy.size.width * kind.zoom, height: proxy.size.height * kind.zoom)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .accessibilityHidden(true)
        } else {
            Image(systemName: kind.fallbackSymbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppColors.primary)
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Couleurs

    private static func recolored(_ view: LottieView<EmptyView>,
                                  kind: FinanceStatusAnimationKind,
                                  scheme: ColorScheme) -> LottieView<EmptyView> {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let primary = UIColor(AppColors.primary).resolvedColor(with: traits)
        let light = FinanceLoaderAsset.lightened(primary, by: 0.45)
        let text = UIColor(AppColors.textPrimary).resolvedColor(with: traits)

        var colors: [(UIColor, [String])] = []
        var result = view

        switch kind {
        case .submitted:
            // Anneau et aiguilles, plus un remplissage vert caché sur les aiguilles.
            colors = [(primary, ["**.Stroke 1.Color", "**.Fill 1.Color"])]
            // Trait d'origine à 70 sur une toile de 800 : trop épais à la
            // taille d'une icône. Moitié moins.
            result = result.valueProvider(FloatValueProvider(35),
                                          for: AnimationKeypath(keypath: "**.Stroke 1.Stroke Width"))

        case .verifying:
            // Couvercles du sablier ; le verre reste clair, le sable est dans le fichier.
            colors = [
                (primary, ["Jam Pasir.Layer 5 Outlines.**.Color", "Jam Pasir.Layer 4 Outlines.**.Color"]),
                (light, ["Jam Pasir.Layer 3 Outlines.**.Color", "Jam Pasir.Layer 2 Outlines.**.Color"]),
            ]

        case .pending:
            colors = [
                (primary, ["cho Outlines.**.Color", "Shape Layer 1.**.Color"]),
                (.white, ["line cho 1 Outlines.**.Color", "line cho 2 Outlines.**.Color"]),
            ]

        case .waiting:
            // Fond vert d'origine ; les aiguilles restent blanches.
            colors = [(primary, ["BG.**.Color"])]

        case .searching:
            colors = [
                (primary, ["Text zoomed.**.Color"]),
                (text, ["Loupe.**.Color"]),
            ]

        case .locked:
            colors = [(primary, ["**.Color"])]

        case .settled:
            // Les particules d'origine passent par le vert menthe : toutes en
            // couleur principale claire.
            colors = [
                (light, ["Effects.**.Fill 1.Color",
                         "Card Icon.Path Motion .**.Color"]),
                (primary, ["Card Icon.Card Icon .chip.Fill 1.Color",
                           "Card Icon.Card Icon .stripe.Fill 1.Color",
                           "Card Icon.Card Icon .card.Stroke 1.Color",
                           "Card Icon.Card Shadow.**.Color",
                           "Card Icon.Check Icon.circle.Fill 1.Color"]),
            ]
            let gradient = [FinanceLoaderAsset.lightened(primary, by: 0.85),
                            FinanceLoaderAsset.lightened(primary, by: 0.45),
                            primary].map(\.lottieColorValue)
            result = result.valueProvider(GradientValueProvider(gradient, locations: [0, 0.5, 1]),
                                          for: AnimationKeypath(keypath: "Circle Gradient.**.Colors"))
        }

        for (color, keypaths) in colors {
            let provider = ColorValueProvider(color.lottieColorValue)
            for keypath in keypaths {
                result = result.valueProvider(provider, for: AnimationKeypath(keypath: keypath))
            }
        }
        return result
    }
}

/// Chaque fichier est décodé une fois : une liste de cartes en attente ne
/// relit pas le même JSON à chaque cellule.
private enum FinanceStatusAnimationCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var store: [String: LottieAnimation] = [:]

    static func animation(named name: String) -> LottieAnimation? {
        lock.lock(); defer { lock.unlock() }
        if let cached = store[name] { return cached }
        let loaded = LottieAnimation.named(name, bundle: .module)
            ?? LottieAnimation.named(name, bundle: .module, subdirectory: "Finance")
        store[name] = loaded
        return loaded
    }
}

#Preview("États") {
    let kinds: [FinanceStatusAnimationKind] = [.submitted, .verifying, .pending, .waiting,
                                               .searching, .locked, .settled]
    return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 16) {
        ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
            FinanceStatusAnimation(kind).frame(width: 96, height: 96)
        }
    }
    .padding()
}
