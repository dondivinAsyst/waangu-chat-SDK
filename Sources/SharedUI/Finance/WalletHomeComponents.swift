//
//  WalletHomeComponents.swift
//  SharedUI
//
//  Les pièces de l'écran « Mon portefeuille ».
//

import SwiftUI

// MARK: - Montant

/// Un montant en devise, symbole grisé et chiffres pleins.
///
/// Le symbole passe en gris parce qu'il ne porte pas d'information une fois la
/// devise connue : ce qu'on lit sur cet écran, c'est le nombre. Le griser met
/// les chiffres en avant sans changer leur corps.
///
/// La position du symbole n'est **pas** forcée en tête : elle est celle que la
/// locale impose. « 0,00 € » en français et « $0.00 » en anglais sont la même
/// vue ; imposer le préfixe afficherait « €0,00 », qui ne s'écrit nulle part.
public struct WalletAmountText: View {

    public let amount: Decimal
    public let currencyCode: String
    public let size: CGFloat
    public let weight: Font.Weight

    public init(amount: Decimal, currencyCode: String,
                size: CGFloat, weight: Font.Weight = .bold) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        let parts = Self.split(amount, currencyCode)
        return HStack(spacing: 0) {
            if !parts.prefix.isEmpty { symbol(parts.prefix) }
            Text(parts.digits)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(AppColors.textPrimary)
            if !parts.suffix.isEmpty { symbol(parts.suffix) }
        }
        .accessibilityElement()
        .accessibilityLabel(parts.prefix + parts.digits + parts.suffix)
    }

    private func symbol(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(AppColors.subtitleGray)
    }

    /// Découpe la chaîne formatée en symbole / chiffres / symbole.
    ///
    /// Le découpage part de la chaîne que la locale produit, puis y localise le
    /// symbole — plutôt que de recomposer symbole et nombre à la main, ce qui
    /// perdrait l'espace insécable que certaines locales placent entre les deux.
    public static func split(_ amount: Decimal,
                             _ code: String) -> (prefix: String, digits: String, suffix: String) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = .current

        guard let full = formatter.string(from: amount as NSDecimalNumber) else {
            return ("", "—", "")
        }
        let symbol = formatter.currencySymbol ?? ""
        guard !symbol.isEmpty, let range = full.range(of: symbol) else {
            return ("", full, "")
        }

        let firstDigit = full.rangeOfCharacter(from: .decimalDigits)
        let symbolLeads = firstDigit.map { range.lowerBound < $0.lowerBound } ?? true

        if symbolLeads {
            return (String(full[..<range.upperBound]),
                    String(full[range.upperBound...]).trimmingCharacters(in: .whitespaces),
                    "")
        }
        return ("",
                String(full[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                String(full[range.lowerBound...]))
    }
}

// MARK: - Bloc de solde

/// Le solde total, en tête du portefeuille.
///
/// Trois états, et le troisième compte : un solde qu'on n'a pas pu lire affiche
/// un tiret, jamais zéro. Zéro est une information — « votre compte est vide » —
/// et l'afficher quand on ne sait pas est un mensonge que l'utilisateur croira.
public struct WalletBalanceBlock: View {

    public enum State {
        case loading
        case amount(Decimal, currencyCode: String)
        /// Lecture impossible. `retry` est proposé plutôt qu'un rechargement
        /// automatique : une boucle de reprise silencieuse sur un solde donne un
        /// écran qui clignote sans jamais dire ce qui ne va pas.
        case unavailable(message: String, retry: () -> Void)
    }

    public let title: String
    public let state: State

    public init(title: String, state: State) {
        self.title = title
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textPrimary)

            switch state {
            case .loading:
                // Même hauteur que le montant : sans cela, la rangée d'actions
                // remonte puis redescend à l'arrivée du solde.
                ProgressView()
                    .frame(height: 48)

            case .amount(let value, let code):
                WalletAmountText(amount: value, currencyCode: code, size: 40)
                    .frame(height: 48)

            case .unavailable(let message, let retry):
                Button(action: retry) {
                    HStack(spacing: 8) {
                        Text("—")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(AppColors.subtitleGray)
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                    }
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(message)
                .accessibilityHint(Text(verbatim: message))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }
}

// MARK: - Carte d'incitation

/// Bandeau bleu proposant une action de mise en conformité.
///
/// Il disparaît une fois l'action faite. Une incitation qui reste après coup
/// apprend à l'utilisateur à ne plus la lire — et c'est celle-ci qu'on veut
/// qu'il lise.
public struct WalletPromoCard: View {

    public let title: String
    public let actionTitle: String
    public let symbol: String
    public let action: () -> Void

    public init(title: String, actionTitle: String,
                symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.actionTitle = actionTitle
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 4) {
                        Text(actionTitle)
                            .font(.system(size: 15))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.9))
                }

                Spacer(minLength: 8)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.walletPromoBadge)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.white)
                    )
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Ligne en carte

/// Une ligne du portefeuille, posée sur sa propre carte.
///
/// Cartes séparées et non liste groupée : chaque ligne mène ailleurs et ne
/// partage rien avec la suivante. Les grouper sous un filet commun suggérerait
/// une famille — « vos comptes » — que ces trois lignes ne forment pas.
public struct WalletCardRow: View {

    /// Ce que porte la droite de la ligne.
    public enum Trailing {
        /// Un montant et sa contre-valeur. Réservé aux lignes qui **portent** de
        /// l'argent : une ligne de réglage avec un chiffre à droite se lit comme
        /// un solde.
        case value(primary: String, secondary: String?)
        case chevron
        case none
    }

    /// Forme de la pastille : ronde pour un compte, carrée pour un outil.
    public enum IconShape { case circle, rounded }

    public let symbol: String
    public let iconColor: Color
    public let iconShape: IconShape
    public let title: String

    /// Seconde ligne sous le titre — la contre-valeur d'un compte, son numéro
    /// tronqué. `nil` ⇒ la ligne reste sur une seule ligne et se centre.
    public let subtitle: String?

    public let trailing: Trailing
    public let action: () -> Void

    public init(symbol: String, iconColor: Color, iconShape: IconShape = .circle,
                title: String, subtitle: String? = nil,
                trailing: Trailing, action: @escaping () -> Void) {
        self.symbol = symbol
        self.iconColor = iconColor
        self.iconShape = iconShape
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.subtitleGray)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                trailingView
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AppColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var icon: some View {
        let glyph = Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.white)

        switch iconShape {
        case .circle:
            Circle().fill(iconColor).frame(width: 44, height: 44).overlay(glyph)
        case .rounded:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconColor).frame(width: 44, height: 44).overlay(glyph)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .value(let primary, let secondary):
            VStack(alignment: .trailing, spacing: 2) {
                Text(primary)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                if let secondary {
                    Text(secondary)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.subtitleGray)
                }
            }
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.subtitleGray.opacity(0.6))
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Barre de navigation

/// Barre de titre pleine, aux couleurs de la marque.
///
/// Écrite plutôt qu'obtenue par `toolbarBackground` : la barre doit couvrir la
/// zone d'état d'un même bleu, et le modificateur de barre système laisse cette
/// zone au fond de la page. Le raccord se voyait comme une bande claire.
public struct WalletNavigationBar<Trailing: View>: View {

    public let title: String
    public let onBack: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    public init(title: String, onBack: @escaping () -> Void,
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white)
                    // Cible de 44 pt : le glyphe seul en fait 20, sous le
                    // minimum tactile.
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(AppColors.primary)
    }
}

// MARK: - En-tête de section du portefeuille

/// Intitulé de groupe avec action facultative à droite.
///
/// Distinct de ``FinanceSectionHeader`` par cette action : « tout voir » doit
/// être atteignable depuis le titre, sinon la section ne mène nulle part.
public struct WalletSectionHeader: View {

    public let title: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 13))
                .tracking(-0.08)
                .foregroundStyle(AppColors.subtitleGray)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}
