//
//  FinanceInfoCard.swift
//  SharedUI
//
//  Ce qui va se passer, dit avant que ça se passe.
//

import SwiftUI

/// Carte explicative : un titre, puis ce qui découle du choix fait.
///
/// **Prend la place de ce qu'elle remplace.** Quand une bascule retire un champ
/// de l'écran, laisser le vide oblige à deviner ce que le mode fait — et sur une
/// demande d'argent, « pas de montant » se lit aussi bien comme « montant zéro »
/// que comme « le payeur décide ». La carte occupe la place libérée et répond.
///
/// Des points et non un paragraphe : chaque ligne est une conséquence distincte,
/// et un bloc de texte sur un écran de paiement ne se lit pas.
public struct FinanceInfoCard: View {

    public let symbol: String
    public let title: String
    public let points: [String]

    public init(symbol: String = "info.circle.fill", title: String, points: [String]) {
        self.symbol = symbol
        self.title = title
        self.points = points
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.primary)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 8) {
                        // Puce dessinée plutôt qu'un « • » textuel : alignée sur
                        // la première ligne quelle que soit la taille de police.
                        Circle()
                            .fill(AppColors.primary.opacity(0.45))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(point)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.subtitleGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.primary.opacity(0.18), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([title] + points).joined(separator: ". "))
    }
}
