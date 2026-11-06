//
//  FXQuoteCardView.swift
//  FeatureChat
//
//  Carte d'un devis de change.
//
//  Aucune ligne de `BubbleView` n'est touchée : la carte s'enregistre auprès
//  de `FinancialCardRegistry` — §17, le fil ne change pas par type.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

// MARK: - Devis de change

/// Un devis de change.
///
/// Un devis expiré le dit et ne propose rien : le taux qu'il porte n'est plus
/// celui qui sera appliqué.
struct FXQuoteCardView: View {

    let payload: FinancialCardPayload

    var body: some View {
        FinancialCardChrome(payload: payload, title: "Change") {
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.formattedAmount).font(.title3.weight(.semibold))

                if payload.status == .expired {
                    Text(FinanceStrings.cardQuoteExpired)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
