//
//  MoneyRequestCardView.swift
//  FeatureChat
//
//  Carte d'une demande d'argent — tâche 6.8.
//
//  Aucune ligne de `BubbleView` n'est touchée : la carte s'enregistre auprès
//  de `FinancialCardRegistry` — §17, le fil ne change pas par type.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

// MARK: - Demande d'argent

/// Une demande d'argent, reçue ou émise.
///
/// **Ne ressemble pas à un paiement.** Même cadre que les autres cartes, mais
/// un titre, une légende de montant et des actions propres à la demande : qui
/// la reçoit voit « Payer » et « Refuser » ; qui l'a envoyée voit où elle en
/// est, et « Relancer ».
///
/// **Les boutons viennent du serveur.** Ils suivent `nextSafeActions` de la
/// `RequestView` (§4), relue à l'affichage : une demande payée, expirée ou
/// annulée ne liste plus `PAY`, et le bouton disparaît sans règle locale. Le
/// montant affiché au payeur est **sa** part restante (`parties[].remainingMinor`).
///
/// Aucun bouton ne débite : « Payer » ouvre un devis à confirmer (§6 du Bloc 1).
struct MoneyRequestCardView: View {

    let payload: FinancialCardPayload

    @Environment(\.financeCardDirection) private var direction
    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeRequestActions) private var actions
    @State private var overlay: MoneyRequestOverlay?
    /// Relecture demandée par une action de cet appareil — voir
    /// `Notification.Name.financeRequestDidChange`.
    @State private var reloadToken = 0

    private var isReceived: Bool { direction == .received }

    var body: some View {
        FinancialCardChrome(payload: payload, title: title) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(amountCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(displayedAmount)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }

                if let note = payload.note, !note.isEmpty {
                    Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                }

                if let share = overlay?.myShare {
                    shareLine(share)
                }

                // `WAIT` du serveur : l'état, dit **avec** les gestes, pas à
                // leur place. Avant la première lecture serveur, la demande
                // envoyée encore en cours garde la même ligne.
                if showsWaiting {
                    waitingLine
                }

                if let overlay, let actions, hasActions(overlay) {
                    FinanceHairline().padding(.vertical, 2)
                    actionRow(overlay, actions)
                }
            }
        }
        // Relue à chaque nouvelle révision de la carte : un refus, un paiement
        // ou une expiration changent les actions que le serveur propose.
        .task(id: "\(payload.reference.id)|\(payload.reference.version)|\(payload.status.rawValue)|\(reloadToken)") {
            await loadOverlay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .financeRequestDidChange)) { note in
            if (note.object as? String) == payload.reference.id { reloadToken += 1 }
        }
    }

    // MARK: - Contenu

    private var title: String {
        isReceived ? FinanceStrings.requestCardReceivedTitle
                   : (direction == .sent ? FinanceStrings.requestCardSentTitle
                                         : FinanceStrings.requestCardReceivedTitle)
    }

    /// « À payer » tant que ma part attend ; ensuite, le montant demandé — une
    /// part réglée afficherait « À payer 0 BIF ».
    private var showsMyRemaining: Bool {
        overlay?.myShare == nil && overlay?.myRemaining != nil
    }

    private var amountCaption: String {
        showsMyRemaining ? FinanceStrings.requestCardYouOwe : FinanceStrings.requestCardAmountAsked
    }

    /// La part restante du payeur quand le serveur la donne ; sinon le montant
    /// de la carte.
    private var displayedAmount: String {
        guard showsMyRemaining, let overlay, let remaining = overlay.myRemaining else {
            return payload.formattedAmount
        }
        return AmountEntry.format(remaining, overlay.currency.isEmpty ? payload.currency : overlay.currency)
    }

    /// Ce qu'est devenue ma part — à la place des boutons, qui disparaissent.
    @ViewBuilder
    private func shareLine(_ share: MoneyRequestOverlay.MyShare) -> some View {
        switch share {
        case .paymentSent:
            Label(FinanceStrings.requestCardPaymentSent, systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        case .paid:
            Label(FinanceStrings.requestCardPaid, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primary)
        case .declined:
            Label(FinanceStrings.requestCardDeclined, systemImage: "xmark.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Lu au serveur : `WAIT` décide. Sans lecture encore, une demande envoyée
    /// en cours attend forcément son paiement.
    private var showsWaiting: Bool {
        if let overlay { return overlay.isWaiting }
        return !isReceived && payload.status == .pending
    }

    private var waitingLine: some View {
        HStack(spacing: 6) {
            FinanceStatusAnimation(.waiting)
                .frame(width: 16, height: 16)
            Text(FinanceStrings.requestCardAwaiting)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func hasActions(_ overlay: MoneyRequestOverlay) -> Bool {
        RequestActionRow.hasActions(overlay)
    }

    @ViewBuilder
    private func actionRow(_ overlay: MoneyRequestOverlay, _ actions: FinanceRequestActions) -> some View {
        RequestActionRow(overlay: overlay, actions: actions, onSentBubble: direction == .sent)
    }

    private func loadOverlay() async {
        overlay = await Self.overlay(of: payload, surface: surface)
    }

    /// L'état serveur de cet objet, ou `nil`.
    ///
    /// Lecture refusée ou réseau absent : **aucun bouton**, plutôt qu'un bouton
    /// que le serveur n'a pas proposé.
    static func overlay(of payload: FinancialCardPayload,
                        surface: ChatFinanceSurface?) async -> MoneyRequestOverlay? {
        guard let responder = surface?.requestResponder,
              case .success(let fresh) = await responder.overlay(for: payload.reference)
        else { return nil }
        return fresh
    }
}
