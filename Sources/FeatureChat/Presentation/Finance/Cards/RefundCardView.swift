//
//  RefundCardView.swift
//  FeatureChat
//
//  Carte d'un remboursement.
//
//  Aucune ligne de `BubbleView` n'est touchée : la carte s'enregistre auprès
//  de `FinancialCardRegistry` — §17, le fil ne change pas par type.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

// MARK: - Remboursement

/// Un remboursement, total ou partiel.
///
/// Le montant affiché est celui **remboursé**, pas celui de l'opération d'origine.
/// Les confondre ferait lire un remboursement partiel comme un remboursement
/// complet — la différence porte sur de l'argent que l'utilisateur croit avoir
/// récupéré.
struct RefundCardView: View {

    let payload: FinancialCardPayload

    var body: some View {
        FinancialCardChrome(payload: payload, title: title) {
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.formattedAmount).font(.title3.weight(.semibold))

                if payload.status == .partiallyRefunded {
                    Text(FinanceStrings.cardPartialRefund)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var title: String {
        payload.status == .reversed ? "Annulation opérateur" : "Remboursement"
    }
}
