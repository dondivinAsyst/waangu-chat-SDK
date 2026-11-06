//
//  FinanceReviewSummary.swift
//  SharedUI
//
//  Le récapitulatif avant confirmation.
//

import SwiftUI

/// Ce qui va se passer, relu une dernière fois.
///
/// **Le montant domine, le reste l'explique.** Un récapitulatif fait de lignes
/// de même poids oblige à chercher le chiffre qui engage ; ici il est en tête,
/// en grand, et les lignes en dessous disent à qui et pour quoi.
///
/// Chaque ligne porte un libellé **et** une valeur. Une ligne sans valeur —
/// l'écran précédent en avait deux, « Lumitel » et « Airtime 1 000 », posées
/// seules à gauche — ne se lit pas comme une donnée mais comme un titre, et
/// laisse deviner ce qu'elle décrit.
public struct FinanceReviewSummary<Footer: View>: View {

    /// Une ligne du récapitulatif.
    public struct Row: Identifiable {
        public let id = UUID()
        public let label: String
        public let value: String

        /// Mis en avant : c'est la ligne qui engage, quand il y en a une.
        public let isProminent: Bool

        public init(_ label: String, _ value: String, isProminent: Bool = false) {
            self.label = label
            self.value = value
            self.isProminent = isProminent
        }
    }

    public let title: String

    /// Montant en tête. `nil` ⇒ pas de bloc de montant : tous les
    /// récapitulatifs n'en ont pas un seul et unique.
    public let amount: String?

    /// Légende sous le montant — le bénéficiaire, la ligne rechargée.
    public let amountCaption: String?

    public let rows: [Row]
    @ViewBuilder let footer: () -> Footer

    public init(title: String,
                amount: String? = nil,
                amountCaption: String? = nil,
                rows: [Row],
                @ViewBuilder footer: @escaping () -> Footer) {
        self.title = title
        self.amount = amount
        self.amountCaption = amountCaption
        self.rows = rows
        self.footer = footer
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if !rows.isEmpty { card }

                footer()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 18)
        }
        .background(AppColors.walletCanvas)
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.subtitleGray)

            if let amount {
                Text(amount)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if let amountCaption {
                Text(amountCaption)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.subtitleGray)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.subtitleGray)

                    Spacer(minLength: 8)

                    Text(row.value)
                        .font(.system(size: row.isProminent ? 17 : 15,
                                      weight: row.isProminent ? .bold : .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .accessibilityElement(children: .combine)

                if index < rows.count - 1 {
                    AppColors.separator
                        .frame(height: 0.33)
                        .padding(.leading, 14)
                }
            }
        }
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

public extension FinanceReviewSummary where Footer == EmptyView {

    init(title: String,
         amount: String? = nil,
         amountCaption: String? = nil,
         rows: [Row]) {
        self.init(title: title, amount: amount, amountCaption: amountCaption,
                  rows: rows, footer: { EmptyView() })
    }
}
