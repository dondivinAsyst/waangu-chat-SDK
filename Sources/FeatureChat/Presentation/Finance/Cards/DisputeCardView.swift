//
//  DisputeCardView.swift
//  FeatureChat
//
//  Carte d'un litige.
//
//  Aucune ligne de `BubbleView` n'est touchée : la carte s'enregistre auprès
//  de `FinancialCardRegistry` — §17, le fil ne change pas par type.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

// MARK: - Litige

struct DisputeCardView: View {

    let payload: FinancialCardPayload

    var body: some View {
        FinancialCardChrome(payload: payload, title: "Litige") {
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.formattedAmount).font(.title3.weight(.semibold))
                Text(FinanceStrings.cardTrackInWallet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
