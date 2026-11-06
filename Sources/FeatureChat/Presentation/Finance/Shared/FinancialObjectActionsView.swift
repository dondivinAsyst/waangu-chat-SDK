//
//  FinancialObjectActionsView.swift
//  FeatureChat
//
//  Ce qu'on peut faire après un paiement — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Les suites d'une transaction : reçu, litige, support.
///
/// Ces trois écrans existaient sans porte d'entrée. Une carte de paiement qui
/// ne s'ouvre pas laisse l'utilisateur sans recours au moment précis où il en
/// a besoin — c'est-à-dire quand quelque chose s'est mal passé.
///
/// Chaque action est proposée **selon ce que la transaction permet**, pas selon
/// ce que l'écran sait afficher : proposer un litige sur un paiement jamais
/// débité produit un dossier vide que quelqu'un devra fermer à la main.
struct FinancialObjectActionsView: View {

    let payload: FinancialCardPayload
    let surface: ChatFinanceSurface
    let conversationID: String?
    let onDismiss: () -> Void

    @State private var route: Route?
    @State private var deliveryCheck: DeliveryCheck = .idle
    @State private var cancelState: CancelState = .idle
    @State private var confirmsCancel = false
    @State private var noteTranslation: NoteTranslation = .idle

    /// Traduction de la note (§58) — machine, jamais à la place de l'original.
    private enum NoteTranslation: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    /// Annulation demandée au serveur (§10) — jamais présumée faite.
    private enum CancelState: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    /// Relecture de la livraison (`REQUERY_BILLER`) — jamais un nouveau paiement.
    private enum DeliveryCheck: Equatable {
        case idle
        case checking
        case delivered
        case pending
        case failed(String)
    }

    private enum Route: Identifiable, Equatable {
        case receipt
        case dispute
        case support

        var id: String {
            switch self {
            case .receipt: return "receipt"
            case .dispute: return "dispute"
            case .support: return "support"
            }
        }
    }

    var body: some View {
        FinanceNavigationScope {
            FinancePage {
                header
                details
                if canCheckDelivery { deliverySection }
                if canTranslateNote { translationSection }
                if canCancel { cancelSection }
                if !actionItems.isEmpty { actions }
            } actions: {
                CustomButton(title: FinanceStrings.flowReturn, icon: "bubble.left", action: onDismiss)
            }
            .navigationTitle(FinanceStrings.actionsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FinanceStrings.close, action: onDismiss)
                }
            }
            .financeDestination(item: $route) { destination($0) }
        }
    }

    // MARK: - En-tête

    /// Ce qui est vrai de l'opération, dit d'abord.
    ///
    /// L'ancien en-tête posait un gros montant, le nom du bénéficiaire et
    /// « Vérification… » au centre de l'écran : on lisait un reçu. Pour une
    /// issue incertaine, le titre dit maintenant « pas encore confirmé » et
    /// l'explication rappelle de ne pas renvoyer — le montant descend dans les
    /// détails, où il n'a plus l'air d'une preuve.
    private var header: some View {
        VStack(spacing: 0) {
            // Attente ou succès prouvé : animés. Le reste garde son symbole.
            Group {
                if let animation = payload.presentation.statusAnimation {
                    FinanceStatusAnimation(animation).frame(width: 112, height: 112)
                } else {
                    Image(systemName: payload.presentation.symbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(payload.presentation.toneColor)
                }
            }
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)

            if let explanation {
                Text(explanation)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.subtitleGray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        payload.presentation == .verifying ? FinanceStrings.objectUnconfirmedTitle : payload.presentation.label
    }

    /// Une explication seulement quand l'issue n'est pas acquise : c'est là que
    /// l'utilisateur est tenté de renvoyer.
    private var explanation: String? {
        switch payload.presentation {
        case .verifying:
            return FinanceStrings.objectUnconfirmedDetail
        case .inFlight, .atProvider, .settling, .reconciling:
            return FinanceStrings.objectInProgressDetail
        default:
            return nil
        }
    }

    // MARK: - Détails

    private var details: some View {
        VStack(spacing: 0) {
            FinanceHairline()
            if payload.isRepudiated {
                Text(FinanceStrings.cardUnauthenticated)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.subtitleGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                FinanceHairline()
            } else {
                FinanceDetailRow(label: FinanceStrings.amount, value: payload.formattedAmount)
                FinanceHairline()
                if let name = payload.counterpartyName, !name.isEmpty {
                    FinanceDetailRow(label: FinanceStrings.recipientTo, value: name)
                    FinanceHairline()
                }
                if let fee = payload.feeAmount {
                    FinanceDetailRow(label: FinanceStrings.fees,
                                     value: AmountEntry.format(fee, payload.feeCurrency ?? payload.currency))
                    FinanceHairline()
                }
                if let note = payload.note, !note.isEmpty {
                    FinanceDetailRow(label: FinanceStrings.objectNote, value: note)
                    FinanceHairline()
                }
            }
            FinanceReferenceRow(reference: payload.reference.id)
            FinanceHairline()

            if let freshness = payload.freshnessLabel {
                Text(freshness)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Livraison

    /// Payée, pas encore livrée : seule une facture ou une recharge a un
    /// fournisseur à relire (§5.1, §5.3). Le payload est figé à l'ouverture ;
    /// la carte du fil, elle, se met à jour par la relecture de l'objet.
    private var canCheckDelivery: Bool {
        payload.status == .pendingReconciliation
            && [.bill, .airtime, .dataBundle].contains(payload.reference.type)
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if deliveryCheck == .checking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(FinanceStrings.actionsCheckingDelivery)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.subtitleGray)
                }
                .padding(.vertical, 12)
            } else {
                FinanceLinkRow(icon: "shippingbox", title: FinanceStrings.actionsCheckDelivery) {
                    Task { await checkDelivery() }
                }
            }
            if let message = deliveryMessage {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    private var deliveryMessage: String? {
        switch deliveryCheck {
        case .idle, .checking:     return nil
        case .delivered:           return FinanceStrings.deliveryConfirmed
        case .pending:             return FinanceStrings.deliveryPending
        case .failed(let message): return message
        }
    }

    /// `/pay-bill/requery` ou `/top-up/requery` : relit le débit et la
    /// livraison. Puis la carte est relue, pour que le fil montre la même chose.
    private func checkDelivery() async {
        deliveryCheck = .checking
        let reference = payload.reference
        let result: Result<PaymentStatus, FinanceError>
        if reference.type == .bill {
            result = await surface.bills.requery(reference)
        } else {
            result = await surface.topUp.requery(reference)
                .map { $0.results.first?.status ?? .unknown }
        }
        switch result {
        case .success(.completed), .success(.confirmed): deliveryCheck = .delivered
        // Tout autre état n'est pas une livraison — et pas un échec à rejouer.
        case .success:                                   deliveryCheck = .pending
        case .failure(let error):                        deliveryCheck = .failed(FinanceStrings.errorMessage(error))
        }
        _ = await surface.objectReader?.refresh(reference)
    }

    // MARK: - Traduction de la note (§58)

    private var canTranslateNote: Bool {
        !payload.isRepudiated && !(payload.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch noteTranslation {
            case .working:
                HStack(spacing: 12) {
                    ProgressView()
                    Text(FinanceStrings.noteTranslating)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.subtitleGray)
                }
                .padding(.vertical, 12)
            case .done(let text):
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(FinanceStrings.noteMachineTranslation)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.subtitleGray)
                }
                .padding(.vertical, 8)
            case .idle, .failed:
                FinanceLinkRow(icon: "character.bubble", title: FinanceStrings.noteTranslate) {
                    Task { await translateNote() }
                }
                if case .failed(let message) = noteTranslation {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.subtitleGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 8)
    }

    /// Valeurs protégées par le serveur, puis vérifiées au retour : une
    /// traduction qui a perdu un montant n'est pas affichée.
    private func translateNote() async {
        guard let note = payload.note else { return }
        noteTranslation = .working
        let protected = ProtectedText.protect(note, segments: [])
        switch await surface.translator.translate(protected, to: CurrentSessionInfo.shared.languageCode,
                                                  glossaryVersion: nil) {
        case .success(let translated):
            noteTranslation = .done(protected.restore(into: translated.text))
        case .failure(.validation(field: "targetLang")):
            noteTranslation = .failed(FinanceStrings.noteAlreadyInLanguage)
        case .failure(.validation(field: "sourceLang")):
            noteTranslation = .failed(FinanceStrings.noteLanguageUncertain)
        case .failure(let error):
            noteTranslation = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Annulation (§10)

    /// Proposée seulement si **le serveur** la liste dans les actions permises,
    /// sur un objet qui n'est pas encore final.
    private var canCancel: Bool {
        guard !payload.status.isTerminal, let actions = payload.allowedActions else { return false }
        return actions.contains("CANCEL") || actions.contains("CANCEL_INTENT")
    }

    private var cancelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch cancelState {
            case .working:
                HStack(spacing: 12) {
                    ProgressView()
                    Text(FinanceStrings.actionsCancelling)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.subtitleGray)
                }
                .padding(.vertical, 12)
            case .done(let message):
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .failed:
                FinanceLinkRow(icon: "xmark.circle", title: FinanceStrings.actionsCancel) {
                    confirmsCancel = true
                }
                if case .failed(let message) = cancelState {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.subtitleGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 8)
        .confirmationDialog(FinanceStrings.actionsCancelConfirm, isPresented: $confirmsCancel,
                            titleVisibility: .visible) {
            Button(FinanceStrings.actionsCancel, role: .destructive) { Task { await cancel() } }
        }
    }

    /// `POST /intent/cancel-request`, puis la carte relue. Déjà soumis, la
    /// demande est **enregistrée, pas faite** : l'écran le dit.
    private func cancel() async {
        guard let reader = surface.objectReader else {
            cancelState = .failed(FinanceStrings.errorMessage(.capabilityUnavailable))
            return
        }
        cancelState = .working
        switch await reader.cancel(payload.reference, conversationID: conversationID) {
        case .success(.cancelled): cancelState = .done(FinanceStrings.cancelDone)
        case .success(.requested): cancelState = .done(FinanceStrings.cancelRequested)
        case .failure(let error):  cancelState = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Suites

    private var actions: some View {
        VStack(spacing: 0) {
            ForEach(Array(actionItems.enumerated()), id: \.offset) { index, item in
                if index > 0 { FinanceHairline().padding(.leading, 38) }
                FinanceLinkRow(icon: item.icon, title: item.title) { route = item.action }
            }
        }
        .padding(.top, 8)
    }

    private var actionItems: [MenuItem<Route>] {
        var items: [MenuItem<Route>] = []
        if payload.status.isSettledForReceipt {
            items.append(MenuItem(icon: "doc.text", title: FinanceStrings.actionsReceipt, action: .receipt))
        }
        // Le serveur décide ce qui se conteste : `OPEN_DISPUTE` dans les actions de la carte.
        if DisputeEligibility.allows(payload.allowedActions) {
            items.append(MenuItem(icon: "exclamationmark.bubble", title: FinanceStrings.actionsDispute, action: .dispute))
        }
        items.append(MenuItem(icon: "lifepreserver", title: FinanceStrings.actionsSupport, action: .support))
        return items
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .receipt:
            ReceiptView(
                access: surface.receipts,
                reference: payload.reference,
                observedStatus: payload.status,
                onDismiss: { self.route = nil }
            )
        case .dispute:
            DisputeView(
                filing: surface.disputes,
                reference: payload.reference,
                observedStatus: payload.status,
                conversationID: conversationID,
                deviceID: surface.deviceID,
                onDismiss: { self.route = nil }
            )
        case .support:
            SupportCaseView(
                reference: payload.reference,
                support: surface.support,
                deviceID: surface.deviceID,
                onDismiss: { self.route = nil }
            )
        }
    }
}

// MARK: - Ce que l'état autorise

extension PaymentStatus {

    /// Un reçu suppose que l'argent est parti. Avant, le document ne prouve
    /// rien et sa seule existence laisse croire que la transaction a abouti.
    var isSettledForReceipt: Bool {
        switch self {
        case .confirmed, .completed, .refundRequested, .refundApproved,
             .refundProcessing, .refunded, .partiallyRefunded, .reversed,
             .reconciling, .pendingReconciliation, .disputed:
            return true
        default:
            return false
        }
    }

}
