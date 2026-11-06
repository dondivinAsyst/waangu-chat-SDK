//
//  FallbackFinancialCards.swift
//  FeatureChat
//
//  Cartes de repli — tâches 6.3 et 6.4.
//
//  Ces deux vues existent pour une seule raison : `BubbleView` ne doit plus
//  jamais rendre `EmptyView()` sur un message financier. Un message présent en
//  base, visible dans l'aperçu de conversation et dans la recherche, mais absent
//  du fil, est le défaut que le Bloc 1 corrige.

import SwiftUI
import WaanguCoreKit

// MARK: - Objet non encore réconcilié

/// Message marqué financier dont la carte n'est pas encore reconstructible.
///
/// Deux causes : un message écrit avant le Bloc 1 — les colonnes de révision
/// n'existaient pas — ou un objet reçu dont la lecture serveur n'a pas encore
/// abouti. Dans les deux cas l'utilisateur doit voir qu'il se passe quelque
/// chose, pas un blanc.
struct PendingFinancialCard: View {

    let transactionId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                FinanceStatusAnimation(.pending)
                    .frame(width: 20, height: 20)
                Text(FinanceStrings.cardFinancialOperation)
                    .font(.subheadline.weight(.semibold))
            }

            Text(FinanceStrings.cardLoadingDetails)
                .font(.caption)
                .foregroundStyle(.secondary)

            // L'identifiant n'est pas affiché : il n'apprend rien à l'utilisateur
            // et se retrouverait dans les captures d'écran partagées au support.
        }
        .padding(4)
        // Sans fond propre : la bulle porte la couleur, comme pour les autres cartes.
        .frame(maxWidth: 280, alignment: .leading)
        .accessibilityLabel(FinanceStrings.cardLoadingAccessibility)
    }
}

// MARK: - Type inconnu

/// Objet financier d'un type que cette version ne sait pas rendre.
///
/// Arrive quand Android ou le Web émettent un type plus récent. La carte reste
/// exacte — elle ne prétend pas être un paiement — et renvoie vers le Wallet,
/// qui fait autorité.
struct UnknownFinancialCard: View {

    let payload: FinancialCardPayload

    var body: some View {
        FinancialCardChrome(payload: payload, title: "Opération financière") {
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.formattedAmount)
                    .font(.title3.weight(.semibold))

                Text(FinanceStrings.cardOpenInWallet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
