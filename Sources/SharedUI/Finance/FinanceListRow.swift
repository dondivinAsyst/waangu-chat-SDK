//
//  FinanceListRow.swift
//  SharedUI
//
//  Ligne de liste financière — géométrie reprise du kit Telegram Wallet.
//

import SwiftUI

/// Une ligne de liste financière : icône, deux lignes de texte, accessoire.
///
/// Mesures reprises du kit de référence, qui les a éprouvées : marge de tête de
/// 16 pt, gouttière d'icône de 50 pt, pastille de 40 pt, 10 pt de marge
/// verticale, filet de 0,33 pt **encastré** après la gouttière. Les styles de
/// texte viennent du même kit — corps 17/22 à −0,43 de crénage, sous-titre
/// 14/18 à −0,154.
///
/// Le filet encastré n'est pas une coquetterie : il aligne la coupure sur le
/// texte plutôt que sur le bord de l'écran, ce qui fait lire la liste comme des
/// entrées groupées et non comme des bandes.
/// Mesures du kit de référence.
///
/// Hors du type : Swift interdit les propriétés statiques stockées dans un type
/// générique, et `FinanceListRow` l'est par son accessoire.
private enum Metrics {
    static let leadingInset: CGFloat = 16
    static let iconGutter: CGFloat = 50
    static let iconSize: CGFloat = 40
    static let verticalPadding: CGFloat = 10
    static let trailingInset: CGFloat = 16
    static let separatorHeight: CGFloat = 0.33
}

public struct FinanceListRow<Accessory: View>: View {

    public let symbol: String
    public let title: String
    public let subtitle: String?
    public let isEnabled: Bool
    public let showsSeparator: Bool
    @ViewBuilder let accessory: () -> Accessory
    public let action: () -> Void

    public init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        isEnabled: Bool = true,
        showsSeparator: Bool = true,
        @ViewBuilder accessory: @escaping () -> Accessory,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.isEnabled = isEnabled
        self.showsSeparator = showsSeparator
        self.accessory = accessory
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                icon
                    .frame(width: Metrics.iconGutter, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        labels
                        Spacer(minLength: 8)
                        accessory()
                    }
                    .padding(.vertical, Metrics.verticalPadding)
                    .padding(.trailing, Metrics.trailingInset)

                    if showsSeparator {
                        // Encastré : il commence là où commence le texte, pas au
                        // bord de l'écran.
                        AppColors.separator
                            .frame(height: Metrics.separatorHeight)
                    }
                }
            }
            .padding(.leading, Metrics.leadingInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isEnabled ? .isButton : [])
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(AppColors.primary.opacity(isEnabled ? 0.12 : 0.06))
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)

            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isEnabled ? AppColors.primary : AppColors.subtitleGray)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                // Corps 17/22, crénage −0,43 : les valeurs du kit.
                .font(.system(size: 17))
                .tracking(-0.43)
                .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.subtitleGray)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .tracking(-0.154)
                    .foregroundStyle(AppColors.subtitleGray)
                    .lineLimit(2)
            }
        }
    }
}

extension FinanceListRow where Accessory == EmptyView {

    /// Ligne sans accessoire.
    public init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        isEnabled: Bool = true,
        showsSeparator: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(
            symbol: symbol,
            title: title,
            subtitle: subtitle,
            isEnabled: isEnabled,
            showsSeparator: showsSeparator,
            accessory: { EmptyView() },
            action: action
        )
    }
}

// MARK: - En-tête de section

/// Intitulé de groupe, 28 pt de haut dans le kit.
public struct FinanceSectionHeader: View {

    public let title: String

    public init(title: String) { self.title = title }

    public var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13))
            .tracking(-0.08)
            .foregroundStyle(AppColors.subtitleGray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}
