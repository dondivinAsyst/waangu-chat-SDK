//
//  BillCardView.swift
//  FeatureChat
//
//  Carte d'une facture ou d'une recharge.
//
//  Aucune ligne de `BubbleView` n'est touchée : la carte s'enregistre auprès
//  de `FinancialCardRegistry` — §17, le fil ne change pas par type.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

// MARK: - Facture et recharge

struct BillCardView: View {

    let payload: FinancialCardPayload

    var body: some View {
        FinancialCardChrome(payload: payload, title: title) {
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.formattedAmount).font(.title3.weight(.semibold))
                if let name = payload.counterpartyName {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var title: String {
        switch payload.reference.type {
        case .airtime:    return "Recharge"
        case .dataBundle: return "Forfait data"
        default:          return "Facture"
        }
    }
}
