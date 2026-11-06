//
//  SplitBillCardView.swift
//  FeatureChat
//
//  Carte d'un partage d'addition.
//
//  Aucune ligne de `BubbleView` n'est touchée : la carte s'enregistre auprès
//  de `FinancialCardRegistry` — §17, le fil ne change pas par type.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

// MARK: - Partage de facture

/// Un partage d'addition, dans chacune des conversations où il a été envoyé.
///
/// Montre qui a payé, qui a refusé, qui n'a pas répondu — **d'après le partage
/// lu au serveur**, jamais d'après des événements comptés dans le fil : « 3 sur
/// 5 ont payé » dérivé du fil serait faux dès qu'un événement manque, et c'est
/// exactement le chiffre que les participants se citent entre eux.
///
/// La portée de confidentialité du partage s'applique : un participant qui n'a
/// pas le droit de voir la part des autres ne voit que la sienne. Le statut de
/// paiement reste celui du cadre commun, distinct de l'état de livraison.
struct SplitBillCardView: View {

    let payload: FinancialCardPayload

    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeCardDirection) private var direction
    @Environment(\.financeRequestActions) private var actions
    @StateObject private var model = SplitBillCardViewModel()
    /// L'état serveur de ce partage — c'est lui qui porte **les gestes**.
    ///
    /// Un partage est une demande à plusieurs parts nommées : la même lecture
    /// répond pour les deux, et c'est elle qui dit si `PAY_SHARE` est offert.
    /// Sans elle, la carte arrivait dans le fil du participant, montrait sa
    /// part, et ne lui donnait aucun moyen de la payer.
    @State private var overlay: MoneyRequestOverlay?
    @State private var reloadToken = 0

    var body: some View {
        FinancialCardChrome(payload: payload, title: FinanceStrings.splitCardTitle) {
            VStack(alignment: .leading, spacing: 6) {
                Text(payload.formattedAmount).font(.title3.weight(.semibold))

                switch model.phase {
                case .loaded(let snapshot):
                    progress(snapshot)
                case .loading:
                    ProgressView().controlSize(.small)
                case .idle, .unavailable:
                    Text(FinanceStrings.cardViewSharesInWallet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let overlay, let actions, RequestActionRow.hasActions(overlay) {
                    FinanceHairline().padding(.vertical, 2)
                    RequestActionRow(overlay: overlay, actions: actions,
                                     onSentBubble: direction == .sent)
                }
            }
        }
        // Relu à chaque version de l'objet : un versement ou un refus arrivé
        // par MQTT fait avancer la version, et la carte suit.
        .task(id: "\(payload.reference.id)#\(payload.reference.version)#\(reloadToken)") {
            guard let surface else { return }
            // Les deux lectures : la répartition, et ce que le serveur autorise.
            async let snapshot: Void = model.load(
                splitID: payload.reference.id,
                splits: surface.splitBills,
                viewerID: surface.currentUserID
            )
            async let actions = MoneyRequestCardView.overlay(of: payload, surface: surface)
            _ = await snapshot
            overlay = await actions
        }
        // Une part payée par cet appareil change les gestes offerts.
        .onReceive(NotificationCenter.default.publisher(for: .financeRequestDidChange)) { note in
            if (note.object as? String) == payload.reference.id { reloadToken += 1 }
        }
    }

    @ViewBuilder
    private func progress(_ snapshot: SplitBillCardSnapshot) -> some View {
        if let collected = snapshot.collected {
            Text("\(FinanceStrings.splitCollected) · \(money(collected)) / \(money(snapshot.total))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ForEach(snapshot.rows) { row in
            HStack(spacing: 6) {
                Image(systemName: icon(for: row.progress))
                    .font(.caption)
                    .foregroundStyle(tint(for: row.progress))
                Text(row.isViewer ? FinanceStrings.splitCardYou : row.displayName)
                    .font(.caption.weight(row.isViewer ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(label(for: row.progress))
                    .font(.caption2)
                    .foregroundStyle(tint(for: row.progress))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }

        if snapshot.hidesOthers {
            Text(FinanceStrings.splitCardPrivateShares)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }

    private func label(for progress: SplitParticipantProgress) -> String {
        switch progress {
        case .paid:             return FinanceStrings.splitProgressPaid
        case .awaitingPayment:  return FinanceStrings.splitProgressAwaitingPayment
        case .awaitingApproval: return FinanceStrings.splitConsentPending
        case .declined:         return FinanceStrings.splitConsentDeclined
        case .expired:          return FinanceStrings.splitConsentExpired
        case .excluded:         return FinanceStrings.splitProgressExcluded
        case .unknown:          return FinanceStrings.splitConsentUnknown
        }
    }

    private func icon(for progress: SplitParticipantProgress) -> String {
        switch progress {
        case .paid:             return "checkmark.circle.fill"
        case .awaitingPayment:  return "hourglass"
        case .awaitingApproval: return "clock"
        case .declined:         return "xmark.circle"
        case .expired:          return "calendar.badge.exclamationmark"
        case .excluded:         return "minus.circle"
        case .unknown:          return "questionmark.circle"
        }
    }

    /// Teintes du jeu de jetons uniquement : primaire pour l'acquis, rouge
    /// système pour le refus, secondaire pour tout ce qui attend.
    private func tint(for progress: SplitParticipantProgress) -> Color {
        switch progress {
        case .paid:     return AppColors.primary
        case .declined: return AppColors.statusDanger
        default:        return .secondary
        }
    }
}
