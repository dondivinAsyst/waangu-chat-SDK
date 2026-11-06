//
//  CashInView.swift
//  FeatureChat
//
//  Parcours « déposer de l'argent » — Bloc 3, chapitre 19.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Demande une instruction de dépôt et l'affiche.
///
/// **La référence de dépôt n'est pas un secret**, contrairement au code de
/// retrait : elle identifie un versement attendu, elle n'autorise aucun débit.
/// Elle peut donc s'afficher en entier, se sélectionner et se partager — c'est
/// même nécessaire pour la dicter à un agent.
struct CashInView: View {

    let initiating: any CashInInitiating
    let conversationID: String
    let currency: String
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loadingChannels
    @State private var channels: [CashInChannel] = []
    @State private var selectedChannel: CashInChannel?
    @State private var amountText: String = ""
    /// Identifiant de l'agent chez qui le dépôt se fait — `MoneyOpBody.agentId`,
    /// puis `verify-agent`. Rien ne le collectait : les deux routes du terrain
    /// ne pouvaient donc jamais partir.
    @State private var agentIDText: String = ""
    /// Les services de confirmation — ceux de Send Money, réutilisés.
    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeObjectReader) private var objectReader

    private enum Phase: Equatable {
        case loadingChannels
        case noChannel
        case composing
        case reviewing
        case requesting
        /// Devis rendu par `/cash-in/prepare` : frais, total, à confirmer.
        /// Déposer ne commence qu'après cette acceptation (§6).
        case confirmingQuote(TransferQuote)
        case instructed(CashInInstruction)
        /// Soumis au serveur. **Pas encore un crédit** : l'argent arrive quand
        /// le rail le dit, et c'est la carte qui l'annoncera.
        case submitted(FinancialReference)
        /// Dépôt chez un agent : le vérifier, puis constater la remise des
        /// espèces — deux gestes de terrain, aucun n'étant un crédit (§6).
        case agent(FinancialReference, CashInAgentOverlay?)
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .requesting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .reviewing: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing: return { phase = .composing }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loadingChannels:   progress(FinanceStrings.hubLoading)
                case .noChannel:         message("building.columns", FinanceStrings.cashInNoChannel)
                case .composing:         composer
                case .reviewing: review
                case .requesting:        progress(FinanceStrings.sendSubmitting)
                case .confirmingQuote(let quote): quoteReview(quote)
                case .instructed(let i): instruction(i)
                case .agent(let reference, let overlay): agentPanel(reference, overlay)
                case .submitted(let reference):
                    // « Soumis », jamais « reçu » : le crédit appartient au
                    // rail, et la carte de l'opération l'annoncera (§6, CF_038).
                    FinanceSubmissionView(reference: reference,
                                          detail: FinanceStrings.cashInPendingWarning,
                                          onDismiss: onDismiss)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference, onCheckAgain: nil,
                                                onDismiss: onDismiss)
                case .failed(let m):     message("exclamationmark.triangle", m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.cashInTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
        }
        .financeLoadOnce { await loadChannels() }
    }

    private func loadChannels() async {
        switch await initiating.availableChannels() {
        case .success(let list):
            channels = list
            selectedChannel = list.first
            phase = list.isEmpty ? .noChannel : .composing
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func request() async {
        guard case .reviewing = phase, let channel = selectedChannel else { return }
        phase = .requesting

        let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
        let agent = agentIDText.trimmingCharacters(in: .whitespaces)
        let req = CashInRequest(
            channel: channel, amount: amount, currency: currency,
            conversationID: conversationID,
            agentID: agent.isEmpty ? nil : agent
        )

        let submissionKey105 = await operationKeys.key(for: FinanceOperationKeys.scope("cashin.instruction", String(describing: req)), deviceID: deviceID)

        // Contrat §6 : prepare → devis → confirmation humaine → execute. Un
        // service sans devis garde l'instruction directe.
        if initiating.providesQuotes {
            switch await initiating.quote(req, idempotency: submissionKey105) {
            case .success(let quote): phase = .confirmingQuote(quote)
            case .failure(let e):     phase = .failed(FinanceStrings.errorMessage(e))
            }
            return
        }

        switch await initiating.createInstruction(
            req, idempotency: submissionKey105
        ) {
        case .success(let i): phase = .instructed(i)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    /// La confirmation humaine, puis l'execute — la soumission partagée de
    /// Send Money : clé enregistrée, inscription avant l'envoi, relecture après.
    private func confirm(_ quote: TransferQuote) async {
        guard case .confirmingQuote = phase, let surface else { return }
        phase = .requesting
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: selectedChannel?.rawValue ?? "",
            counterpartyName: nil,
            attestation: nil,
            sendMoney: surface.sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )
        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            // **Soumis, pas crédité.** Le dépôt suit son rail ; annoncer
            // « reçu » ici serait l'erreur que le §6 nomme `CF_038`.
            //
            // Chez un agent, le parcours continue sur le terrain : le vérifier,
            // puis constater la remise. Les deux routes du §6 n'ont jamais pu
            // partir tant que cet écran s'arrêtait à la soumission.
            phase = selectedChannel == .agent ? .agent(reference, nil) : .submitted(reference)
        case .needsNewAgreement:
            if case .needsNewAgreement(_, let fresh) = outcome { phase = .confirmingQuote(fresh) }
        case .verifying(let reference):
            phase = .uncertain(reference)
        case .failed(.expired):
            phase = .reviewing
            await request()
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func progress(_ label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dépôt chez un agent

    /// Les deux gestes de terrain, et **l'attente du crédit** entre les deux.
    ///
    /// Trois états séparés, jamais fondus : l'agent est vérifié, l'agent a pris
    /// les espèces, l'argent est au compte. Le contrat nomme la fusion des deux
    /// derniers `CF_038` ; ici elle est impossible, `awaitsCredit` étant un état
    /// à part entière avec ses propres mots.
    @ViewBuilder
    private func agentPanel(_ reference: FinancialReference,
                            _ overlay: CashInAgentOverlay?) -> some View {
        FinancePage {
            CashJourneyCard(
                title: FinanceStrings.cashInTitle,
                amount: amountText.isEmpty ? "" : AmountEntry.format(
                    Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                    currency),
                caption: agentCaption(overlay),
                symbol: "person.2.fill",
                steps: agentSteps(overlay),
                animation: overlay?.awaitsCredit == true ? .pending : nil
            ) {
                // La saisie n'apparaît que tant qu'elle sert : une fois l'agent
                // vérifié, son identifiant est acquis et la page respire.
                if overlay?.agentVerified != true {
                    CustomTextField(
                        label: FinanceStrings.cashInAgentID,
                        placeholder: "",
                        errorMessage: nil,
                        autocapitalization: .never,
                        errorTint: AppColors.primary,
                        text: $agentIDText
                    )
                    .autocorrectionDisabled()
                }
            }
        } actions: {
            if overlay?.isCredited == true || overlay?.awaitsCredit == true {
                CustomButton(title: FinanceStrings.close, style: .ghost, action: onDismiss)
            } else if overlay?.agentVerified == true {
                CustomButton(title: FinanceStrings.cashInConfirmPhysical) {
                    Task { await confirmPhysical(reference) }
                }
            } else {
                CustomButton(title: FinanceStrings.cashInVerifyAgent) {
                    Task { await verifyAgent(reference) }
                }
                .disabled(agentIDText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Le canal et l'agent, sous le montant.
    private func agentCaption(_ overlay: CashInAgentOverlay?) -> String {
        let channel = selectedChannel.map { FinanceStrings.cashInChannel($0.rawValue) } ?? ""
        guard let agent = overlay?.agentID ?? nonEmptyAgentID else { return channel }
        return channel.isEmpty ? agent : "\(channel) · \(agent)"
    }

    private var nonEmptyAgentID: String? {
        let trimmed = agentIDText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Les trois temps du dépôt — et le troisième reste **visiblement à venir**
    /// tant que le serveur n'a pas crédité. C'est `CF_038`, montré plutôt que dit.
    private func agentSteps(_ overlay: CashInAgentOverlay?) -> [CashJourneyStep] {
        let verified = overlay?.agentVerified == true
        let received = overlay?.physicalReceivedAt != nil
        let credited = overlay?.isCredited == true
        return [
            .init(id: 1, title: FinanceStrings.cashInStepVerify,
                  state: verified ? .done : .current),
            .init(id: 2, title: FinanceStrings.cashInStepHandOver,
                  state: received ? .done : (verified ? .current : .upcoming)),
            .init(id: 3, title: FinanceStrings.cashInStepCredit,
                  detail: credited ? "" : FinanceStrings.cashInAwaitingCredit,
                  state: credited ? .done : (received ? .current : .upcoming))
        ]
    }

    /// `POST /cash-in/verify-agent` — `CF_037` si le serveur ne le reconnaît pas.
    private func verifyAgent(_ reference: FinancialReference) async {
        let agent = agentIDText.trimmingCharacters(in: .whitespaces)
        guard !agent.isEmpty else { return }
        phase = .requesting
        switch await initiating.verifyAgent(reference, conversationID: conversationID,
                                            agentID: agent) {
        case .success(let overlay): phase = .agent(reference, overlay)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// `POST /cash-in/confirm-physical` — l'agent a les espèces. **Pas un crédit** :
    /// le serveur peut laisser `creditState` à `PENDING`, et l'écran le dit.
    private func confirmPhysical(_ reference: FinancialReference) async {
        phase = .requesting
        switch await initiating.confirmPhysical(reference, conversationID: conversationID) {
        case .success(let overlay): phase = .agent(reference, overlay)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Le devis du dépôt, à accepter.
    private func quoteReview(_ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) {
                    phase = .reviewing
                    Task { await request() }
                }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReviewTitle,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: selectedChannel.map { FinanceStrings.cashInChannel($0.rawValue) } ?? "",
                    rows: Self.quoteRows(quote)
                ) {
                    Text(FinanceStrings.cashInPendingWarning)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.sendConfirm,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirm(quote) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private static func quoteRows(_ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = [
            .init(FinanceStrings.amount, AmountEntry.format(quote.amount, quote.currency))
        ]
        if let fee = quote.feeAmount {
            rows.append(.init(FinanceStrings.fees,
                              AmountEntry.format(fee, quote.feeCurrency ?? quote.currency)))
        }
        if let total = quote.totalAmount {
            rows.append(.init(FinanceStrings.total,
                              AmountEntry.format(total, quote.totalCurrency ?? quote.currency),
                              isProminent: true))
        }
        return rows
    }

    private var composer: some View {
        CashAmountComposer(
            title: FinanceStrings.cashInTitle,
            channels: channels,
            selected: $selectedChannel,
            currency: currency,
            describe: { FinanceStrings.cashInChannel($0.rawValue) },
            symbol: Self.symbol(for:),
            amountText: $amountText,
            footnote: FinanceStrings.cashInPendingWarning,
            onContinue: { phase = .reviewing }
        )
    }

    private static func symbol(for channel: CashInChannel) -> String {
        switch channel {
        case .agent:        return "person.2.fill"
        case .bank:         return "building.columns.fill"
        case .card:         return "creditcard.fill"
        case .mobileMoney:  return "iphone"
        case .openBanking:  return "arrow.left.arrow.right"
        }
    }

    /// Le récapitulatif du dépôt.
    ///
    /// L'avertissement de double dépôt est repris ici, avant de confirmer : un
    /// second versement physique produit deux dépôts réels, et aucune
    /// idempotence côté client ne rattrape ce geste.
    private var review: some View {
        VStack(spacing: 0) {
            FinanceReviewSummary(
                title: FinanceStrings.flowCashInReview,
                amount: AmountEntry.format(amountText, currency),
                amountCaption: selectedChannel.map { FinanceStrings.cashInChannel($0.rawValue) },
                rows: reviewRows
            ) {
                Text(FinanceStrings.cashInPendingWarning)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
            }

            CustomButton(title: FinanceStrings.sendContinue) {
                Task { await request() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
    }

    private var reviewRows: [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = []
        if let channel = selectedChannel {
            rows.append(.init(FinanceStrings.cashChannel,
                              FinanceStrings.cashInChannel(channel.rawValue)))
        }
        rows.append(.init(FinanceStrings.amount,
                          AmountEntry.format(amountText, currency), isProminent: true))
        return rows
    }

    /// Formatage partagé avec l'écran de saisie — voir `AmountDisplay`.

    private func instruction(_ i: CashInInstruction) -> some View {
        Form {
            // **L'avertissement passe avant l'instruction.** Un dépôt déjà en
            // vol et un second versement physique produisent deux dépôts réels :
            // aucune idempotence côté client ne rattrape ce geste.
            if i.wouldRiskDoubleDeposit {
                Section {
                    Label(FinanceStrings.cashInPendingWarning,
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.statusWarning)
                }
            }

            Section(FinanceStrings.cashInReference) {
                // En entier et sélectionnable : il faut pouvoir la dicter.
                Text(i.depositReference)
                    .font(.system(.title3, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel(i.depositReference.map(String.init).joined(separator: " "))
            }

            if !i.instructionKeys.isEmpty {
                Section(FinanceStrings.cashInSteps) {
                    ForEach(Array(i.instructionKeys.enumerated()), id: \.offset) { index, key in
                        Label {
                            Text(localized(key))
                        } icon: {
                            Text("\(index + 1)").font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !i.isActionable() {
                Section {
                    Label(FinanceStrings.cashInExpired, systemImage: "clock.badge.xmark")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }
        }
    }

    /// Les étapes sont des clés rendues par le backend : elles varient par
    /// canal, partenaire et pays, et les composer ici les figerait.
    private func localized(_ key: String) -> String {
        // Résolution par TranslationKit ; le repli n'est plus qu'un
        // dernier recours. Sans cela, une clé de protocole s'affichait
        // telle quelle à l'utilisateur.
        FinanceLocalization.string(key, fallback: key.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " "))
    }
}
