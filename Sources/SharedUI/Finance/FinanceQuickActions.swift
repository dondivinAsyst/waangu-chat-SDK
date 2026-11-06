//
//  FinanceQuickActions.swift
//  SharedUI
//
//  Rangée d'actions rapides — géométrie reprise du kit Telegram Wallet.
//

import SwiftUI

/// Les quatre gestes les plus fréquents, en tête du hub financier.
///
/// **Géométrie reprise, palette non.** Le kit de référence pose des pastilles de
/// 48 pt espacées de 86 pt, avec un libellé gras de 14 pt à 6 pt sous l'icône ;
/// ces mesures sont reprises telles quelles parce qu'elles sont éprouvées. Sa
/// couleur de lien (`#007aff`) ne l'est pas : c'est la teinte d'un autre
/// produit. Tout passe par ``AppColors/primary``.
///
/// Les glyphes sont des SF Symbols et non les vecteurs exportés du kit, pour la
/// même raison — un pictogramme dessiné pour une autre marque reste sa marque.
public struct FinanceQuickActions: View {

    public struct Action: Identifiable {
        public let id: String
        public let symbol: String
        public let label: String
        public let isEnabled: Bool
        public let handler: () -> Void

        public init(id: String, symbol: String, label: String,
                    isEnabled: Bool, handler: @escaping () -> Void) {
            self.id = id
            self.symbol = symbol
            self.label = label
            self.isEnabled = isEnabled
            self.handler = handler
        }
    }

    public let actions: [Action]

    public init(actions: [Action]) { self.actions = actions }

    /// Pastille de 48 pt, libellé à 6 pt en dessous — mesures du kit.
    private enum Metrics {
        static let circle: CGFloat = 48
        /// Largeur **maximale** d'une pastille, plus une largeur fixe.
        ///
        /// Fixe, une cinquième entrée déborderait : 5 × 86 + 4 × 6 dépassent la
        /// largeur d'un téléphone. Chaque entrée prend une part égale de la
        /// rangée sans jamais excéder cette largeur — à quatre, l'aspect ne
        /// change pas ; au-delà, elles se resserrent au lieu de sortir de l'écran.
        static let itemWidth: CGFloat = 86
        static let interItem: CGFloat = 6
        static let labelGap: CGFloat = 6
        static let glyph: CGFloat = 20
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Metrics.interItem) {
            ForEach(actions) { action in
                Button(action: action.handler) {
                    VStack(spacing: Metrics.labelGap) {
                        ZStack {
                            Circle()
                                .fill(action.isEnabled
                                      ? AppColors.primary
                                      : AppColors.subtitleGray.opacity(0.35))
                                .frame(width: Metrics.circle, height: Metrics.circle)

                            Image(systemName: action.symbol)
                                .font(.system(size: Metrics.glyph, weight: .semibold))
                                // Le glyphe reste blanc sur les deux thèmes : la
                                // pastille est toujours pleine et colorée, donc
                                // le contraste ne dépend pas du fond de l'écran.
                                .foregroundStyle(Color.white)
                        }

                        Text(action.label)
                            .font(.system(size: 14, weight: .bold))
                            .tracking(-0.2)
                            .foregroundStyle(action.isEnabled
                                             ? AppColors.primary
                                             : AppColors.subtitleGray)
                            // Corps **fixe**, et deux lignes autorisées.
                            //
                            // `minimumScaleFactor` donnait quatre tailles
                            // différentes sur une même rangée, chacune réduite
                            // selon la longueur de son mot : l'effet est aussitôt
                            // visible et désordonné. Mieux vaut passer à la ligne
                            // que changer de corps.
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: Metrics.itemWidth, alignment: .top)
//                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
                .accessibilityLabel(action.label)
                .accessibilityAddTraits(action.isEnabled ? .isButton : [])
            }
        }
//        .frame(maxWidth: .infinity)
    }
}
