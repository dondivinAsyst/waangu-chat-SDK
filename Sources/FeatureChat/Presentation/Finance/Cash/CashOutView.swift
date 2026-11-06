//
//  CashOutView.swift
//  FeatureChat
//
//  Parcours « retirer de l'argent » — Bloc 3, chapitre 20.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Émet une autorisation de retrait et l'affiche.
///
/// **Le code affiché ici est un porteur de valeur.** Trois conséquences dans
/// cette vue, et aucune n'est cosmétique :
///
/// 1. Le code n'apparaît **que** sur l'écran d'autorisation, jamais dans un
///    récapitulatif ni une liste — ailleurs, `maskedCode`.
/// 2. Il n'est jamais placé dans le presse-papiers automatiquement : une copie
///    silencieuse le rend lisible par toute application au premier plan.
/// 3. La révocation est atteignable en un geste, tant que le code est vivant.
struct CashOutView: View {

    let issuing: any CashOutIssuing
    let stepUp: any StepUpAuthenticating
    let conversationID: String
    let currency: String
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loadingChannels
    /// Demande dont l'issue est inconnue, pour la renvoyer sous la même clé.
    @State private var uncertainRequest: CashOutRequest?
    @State private var channels: [CashOutChannel] = []
    @State private var selectedChannel: CashOutChannel?
    @State private var amountText: String = ""
    /// Clé de l'émission en cours, relevée pour la corrélation du step-up.
    /// La soumission, elle, relit toujours `operationKeys` : c'est le registre
    /// persistant qui fait foi, pas cet état qui meurt avec l'écran.
    @State private var idempotency: IdempotencyContext?
    /// Identifiant de l'agent chez qui le retrait se fait — `AgentBody`.
    @State private var agentIDText: String = ""
    /// L'attestation obtenue avant le devis, présentée à l'exécution : une
    /// attestation vaut pour **une** tentative.
    @State private var stepUpAttestation: StepUpAttestation?
    @Environment(\.financeOperationKeys) private var operationKeys
    /// Les services de confirmation — ceux de Send Money, réutilisés.
    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeObjectReader) private var objectReader

    private enum Phase: Equatable {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loadingChannels
        case noChannel
        case composing
        /// Le backend exige une authentification renforcée pour ce geste : un
        /// code de retrait est un porteur de valeur.
        case reviewing(CashOutRequest)
        case steppingUp(CashOutRequest)
        /// Devis rendu par `/cash-out/prepare`, à confirmer avant tout retrait.
        case confirmingQuote(CashOutRequest, TransferQuote)
        case issuing
        /// Exécuté. Le code de retrait s'obtient ensuite auprès de **Finance**
        /// (`/cash-out/token`) — Chat n'en fabrique aucun.
        case tokenStep(FinancialReference, CashOutToken?)
        /// Après révocation, remise ou incident : l'état que le serveur rend.
        case settled(CashOutTokenOverlay)
        case revoked
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .issuing: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .reviewing, .steppingUp: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing: return { phase = .composing }
        case .steppingUp(let request): return { phase = .reviewing(request) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loadingChannels:      progress(FinanceStrings.hubLoading)
                case .noChannel:            message("building.2", FinanceStrings.cashOutNoChannel)
                case .composing:            composer
                case .reviewing(let request): review(request)
                case .steppingUp(let r):    stepUpGate(for: r)
                case .issuing:              progress(FinanceStrings.sendSubmitting)
                case .confirmingQuote(let request, let quote): quoteReview(request, quote)
                case .tokenStep(let reference, let token): tokenPanel(reference, token)
                case .settled(let overlay): settledPanel(overlay)
                case .revoked:              message("checkmark.shield", FinanceStrings.cashOutRevoked)
                case .failed(let m):        message("exclamationmark.triangle", m)
                case .uncertain(let reference):
                    // Retour par l'authentification : une attestation est liée à une
                    // tentative, la réutiliser serait la présenter pour une autre.
                    FinanceUncertainOutcomeView(
                        reference: reference,
                        onCheckAgain: uncertainRequest.map { request in { phase = .steppingUp(request) } },
                        onDismiss: onDismiss)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.cashOutTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
        }
        .financeLoadOnce { await loadChannels() }
    }

    // MARK: - Étapes

    private func loadChannels() async {
        switch await issuing.availableChannels() {
        case .success(let list):
            channels = list
            selectedChannel = list.first
            phase = list.isEmpty ? .noChannel : .composing
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Prépare la demande, puis exige le step-up **avant** d'émettre.
    private func prepareIssue() {
        guard let channel = selectedChannel,
              let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }
        let request = CashOutRequest(
            channel: channel, amount: amount, currency: currency,
            conversationID: conversationID
        )
        phase = .reviewing(request)
        Task { idempotency = await operationKeys.key(for: Self.issueScope(request), deviceID: deviceID) }
    }

    /// Portée de l'émission : ce qui est demandé. Après un kill, la même demande
    /// refaite retrouve la même clé, et le serveur rend le code déjà émis au lieu
    /// d'en émettre un second. Libérée dès l'émission confirmée : un second
    /// retrait identique, plus tard, est une opération nouvelle.
    private static func issueScope(_ request: CashOutRequest) -> String {
        FinanceOperationKeys.scope("cashout.issue", request.channel.rawValue,
                                   request.amount, request.currency, request.conversationID ?? "")
    }

    /// `POST /cash-out/prepare` — un devis, jamais un retrait.
    ///
    /// L'ancienne version appelait `issue`, qui rendait un code d'un seul
    /// appel. Le contrat ne le permet plus : le retrait se prépare, se
    /// confirme, s'exécute, et **Finance** émet ensuite le code (§6).
    private func issue(_ request: CashOutRequest, attestation: StepUpAttestation?) async {
        guard case .steppingUp = phase else { return }
        phase = .issuing
        let scope = Self.issueScope(request)
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)

        switch await issuing.quote(request, idempotency: idempotency) {
        case .success(let quote):
            stepUpAttestation = attestation
            phase = .confirmingQuote(request, quote)
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            uncertainRequest = request
            phase = .uncertain(nil)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Confirmation humaine, puis execute — la soumission partagée.
    private func confirm(_ request: CashOutRequest, _ quote: TransferQuote) async {
        guard case .confirmingQuote = phase, let surface else { return }
        phase = .issuing
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: request.channel.rawValue,
            counterpartyName: nil,
            attestation: stepUpAttestation,
            sendMoney: surface.sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )
        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            await operationKeys.release(Self.issueScope(request))
            phase = .tokenStep(reference, nil)
        case .needsNewAgreement:
            if case .needsNewAgreement(_, let fresh) = outcome {
                phase = .confirmingQuote(request, fresh)
            }
        case .verifying(let reference):
            uncertainRequest = request
            phase = .uncertain(reference)
        case .failed(.expired):
            phase = .steppingUp(request)
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Le code de retrait

    /// `POST /cash-out/token` — **émis par Finance**, rendu une seule fois.
    private func issueToken(_ reference: FinancialReference) async {
        let agent = agentIDText.trimmingCharacters(in: .whitespaces)
        phase = .issuing
        switch await issuing.issueToken(reference, conversationID: conversationID, agentID: agent) {
        case .success(let token): phase = .tokenStep(reference, token)
        // `CF_051` : Finance non câblé — aucun code, et surtout pas un local.
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func revokeToken(_ reference: FinancialReference) async {
        phase = .issuing
        switch await issuing.revokeToken(reference, conversationID: conversationID) {
        case .success(let overlay): phase = .settled(overlay)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func confirmRemittance(_ reference: FinancialReference) async {
        phase = .issuing
        switch await issuing.confirmRemittance(reference, conversationID: conversationID) {
        case .success(let overlay): phase = .settled(overlay)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func reportIncident(_ reference: FinancialReference) async {
        phase = .issuing
        switch await issuing.reportIncident(reference, conversationID: conversationID) {
        case .success(let overlay): phase = .settled(overlay)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Le récapitulatif du retrait.
    ///
    /// Le canal portait son nom seul, à gauche, sans valeur en face : posé
    /// ainsi il se lisait comme un titre et non comme le lieu où l'on doit se
    /// rendre. Le montant, lui, s'écrivait sans séparateur — « 20000 » là où
    /// l'écran de saisie affichait « 20 000 ».
    private func review(_ request: CashOutRequest) -> some View {
        VStack(spacing: 0) {
            FinanceReviewSummary(
                title: FinanceStrings.flowCashOutReview,
                amount: AmountEntry.format(request.amount, request.currency),
                amountCaption: FinanceStrings.cashOutChannel(request.channel.rawValue),
                rows: [
                    .init(FinanceStrings.cashChannel,
                          FinanceStrings.cashOutChannel(request.channel.rawValue)),
                    .init(FinanceStrings.amount,
                          AmountEntry.format(request.amount, request.currency), isProminent: true)
                ]
            ) {
                Text(FinanceStrings.cashOutSecrecy)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
            }

            CustomButton(title: FinanceStrings.sendContinue) {
                phase = .steppingUp(request)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
    }

    /// Formatage partagé avec l'écran de saisie — voir `AmountDisplay`.

    private func stepUpGate(for request: CashOutRequest) -> some View {
        StepUpGate(
            authenticator: stepUp,
            // Plancher pour un code de retrait. Le backend peut exiger plus ;
            // il ne peut pas exiger moins par l'absence de réponse.
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonCashOut,
            correlationID: idempotency?.correlationID ?? CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await issue(request, attestation: attestation) }
            },
            onCancel: { phase = .reviewing(request) }
        )
    }

    /// Révocation de l'ancien parcours — conservée pour l'écran
    /// `authorization`, qui n'est plus atteint depuis que le code vient de
    /// Finance. La révocation en service passe par ``revokeToken``.
    private func revoke(_ auth: CashOutAuthorization) async {
        phase = .issuing
        // Clé **propre** à la révocation. Elle réutilisait celle de l'émission :
        // le serveur pouvait y reconnaître un rejeu de l'émission et en rendre
        // la réussite — « code révoqué » affiché pour un code toujours valide.
        let scope = FinanceOperationKeys.scope("cashout.revoke", auth.reference.id)
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)

        switch await issuing.revoke(auth.reference, idempotency: idempotency) {
        case .success:
            await operationKeys.release(scope)
            phase = .revoked
        case .failure:
            // **L'échec de révocation ne se tait pas.** Un utilisateur qui croit
            // avoir révoqué un code compromis et ne l'a pas fait est dans une
            // situation pire que s'il le savait.
            phase = .failed(FinanceStrings.cashOutRevokeFailed)
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

    private var composer: some View {
        CashAmountComposer(
            title: FinanceStrings.cashOutTitle,
            channels: channels,
            selected: $selectedChannel,
            currency: currency,
            describe: { FinanceStrings.cashOutChannel($0.rawValue) },
            symbol: Self.symbol(for:),
            amountText: $amountText,
            footnote: FinanceStrings.cashOutSecrecy,
            onContinue: prepareIssue
        )
    }

    private static func symbol(for channel: CashOutChannel) -> String {
        switch channel {
        case .agent:    return "person.2.fill"
        case .atm:      return "banknote.fill"
        case .bank:     return "building.columns.fill"
        case .merchant: return "storefront.fill"
        }
    }

    /// L'écran d'autorisation — **le seul endroit où le code entier s'affiche**.
    /// Le devis du retrait, à confirmer.
    private func quoteReview(_ request: CashOutRequest, _ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) { phase = .steppingUp(request) }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReviewTitle,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: FinanceStrings.cashOutChannel(request.channel.rawValue),
                    rows: []
                ) {
                    Text(FinanceStrings.cashOutTokenLater)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.sendConfirm,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirm(request, quote) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    /// Le code de retrait — demandé à Finance, **montré une seule fois**.
    ///
    /// Il n'est ni journalisé, ni enregistré, ni notifié : `CashOutToken` n'est
    /// même pas encodable. Le message d'avertissement est celui du serveur.
    @ViewBuilder
    private func tokenPanel(_ reference: FinancialReference, _ token: CashOutToken?) -> some View {
        FinancePage {
            CashJourneyCard(
                title: FinanceStrings.cashOutTitle,
                amount: amountText.isEmpty ? "" : AmountEntry.format(
                    Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                    currency),
                caption: tokenCaption,
                symbol: "banknote",
                steps: tokenSteps(token),
                animation: nil
            ) {
                if let token {
                    CashOutCodeCard(token: token)
                } else {
                    CustomTextField(
                        label: FinanceStrings.cashOutAgentID, placeholder: "",
                        errorMessage: nil, autocapitalization: .never,
                        errorTint: AppColors.primary, text: $agentIDText
                    )
                    .autocorrectionDisabled()
                }
            }
        } actions: {
            if token == nil {
                CustomButton(title: FinanceStrings.cashOutIssueToken) {
                    Task { await issueToken(reference) }
                }
            } else {
                CustomButton(title: FinanceStrings.cashOutConfirmRemittance) {
                    Task { await confirmRemittance(reference) }
                }
                CustomButton(title: FinanceStrings.cashOutRevoke, style: .ghost) {
                    Task { await revokeToken(reference) }
                }
                CustomButton(title: FinanceStrings.cashOutReportIncident, style: .ghost) {
                    Task { await reportIncident(reference) }
                }
            }
        }
    }

    private var tokenCaption: String {
        let channel = selectedChannel.map { FinanceStrings.cashOutChannel($0.rawValue) } ?? ""
        let agent = agentIDText.trimmingCharacters(in: .whitespaces)
        guard !agent.isEmpty else { return channel }
        return channel.isEmpty ? agent : "\(channel) · \(agent)"
    }

    /// Les trois temps du retrait. Le dernier — les espèces en main — reste à
    /// venir tant que la remise n'est pas constatée, et même alors le ledger
    /// appartient à Finance.
    private func tokenSteps(_ token: CashOutToken?) -> [CashJourneyStep] {
        [
            .init(id: 1, title: FinanceStrings.cashOutStepIssue,
                  state: token == nil ? .current : .done),
            .init(id: 2, title: FinanceStrings.cashOutStepShow,
                  detail: token == nil ? "" : FinanceStrings.cashOutStepShowDetail,
                  state: token == nil ? .upcoming : .current),
            .init(id: 3, title: FinanceStrings.cashOutStepCash, state: .upcoming)
        ]
    }

    /// Ce que le serveur dit du retrait après révocation, remise ou incident.
    ///
    /// Aucun de ces trois gestes n'est une finalité financière : le ledger est
    /// écrit par Finance, et se lit sur la carte de l'opération.
    private func settledPanel(_ overlay: CashOutTokenOverlay) -> some View {
        FinancePage {
            CashJourneyCard(
                title: FinanceStrings.cashOutTitle,
                caption: settledCaption(overlay),
                symbol: settledSymbol(overlay),
                steps: settledSteps(overlay),
                animation: overlay.awaitsSettlement ? .pending : nil
            ) { EmptyView() }
        } actions: {
            CustomButton(title: FinanceStrings.close, style: .ghost, action: onDismiss)
        }
    }

    private func settledSymbol(_ overlay: CashOutTokenOverlay) -> String {
        if overlay.incidentOpened { return "exclamationmark.bubble" }
        if overlay.revoked { return "checkmark.shield" }
        return overlay.remittedAt != nil ? "hand.thumbsup" : "banknote"
    }

    private func settledCaption(_ overlay: CashOutTokenOverlay) -> String {
        if overlay.incidentOpened { return FinanceStrings.cashOutIncidentOpened }
        if overlay.revoked { return FinanceStrings.cashOutRevoked }
        if overlay.remittedAt != nil { return FinanceStrings.cashOutRemitted }
        if overlay.awaitsSettlement { return FinanceStrings.cashOutAwaitingSettlement }
        return ""
    }

    /// Un code révoqué n'a pas de suite : le parcours s'arrête, et l'afficher
    /// en trois temps laisserait croire qu'il continue.
    private func settledSteps(_ overlay: CashOutTokenOverlay) -> [CashJourneyStep] {
        guard !overlay.revoked, !overlay.incidentOpened else { return [] }
        let remitted = overlay.remittedAt != nil
        return [
            .init(id: 1, title: FinanceStrings.cashOutStepIssue, state: .done),
            .init(id: 2, title: FinanceStrings.cashOutStepShow,
                  state: overlay.consumedAt != nil ? .done : .current),
            .init(id: 3, title: FinanceStrings.cashOutStepCash,
                  detail: remitted ? "" : FinanceStrings.cashOutAwaitingSettlement,
                  state: remitted ? .done : .current)
        ]
    }

    private func authorization(_ auth: CashOutAuthorization, isRevoking: Bool) -> some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Text(FinanceStrings.cashOutCodeLabel)
                        .font(.caption).foregroundStyle(.secondary)

                    // Le code entier, en clair, sur cet écran seulement.
                    // `.textSelection` est délibérément **absent** : une copie
                    // silencieuse le rendrait lisible par toute application au
                    // premier plan.
                    Text(auth.isPresentable() ? auth.code : auth.maskedCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(auth.isPresentable() ? Color.primary : Color.secondary)
                        .accessibilityLabel(codeAccessibilityLabel(auth))

                    if auth.isPresentable() {
                        Text(FinanceStrings.cashOutSecrecy)
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Label(FinanceStrings.cashOutExpired, systemImage: "clock.badge.xmark")
                            .font(.caption).foregroundStyle(AppColors.statusWarning)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.amount) {
                    Text(AmountEntry.format(auth.amount, auth.currency))
                }
            }

            if auth.isPresentable() {
                Section {
                    Button(role: .destructive) {
                        Task { await revoke(auth) }
                    } label: {
                        if isRevoking {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(FinanceStrings.cashOutRevoke).frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isRevoking)
                }
            }
        }
    }

    /// VoiceOver épelle le code chiffre par chiffre.
    ///
    /// Lu d'un bloc, « 483920 » devient « quatre cent quatre-vingt-trois mille
    /// neuf cent vingt » — inutilisable pour le recopier à un agent.
    private func codeAccessibilityLabel(_ auth: CashOutAuthorization) -> String {
        guard auth.isPresentable() else { return FinanceStrings.cashOutExpired }
        return auth.code.map(String.init).joined(separator: " ")
    }
}

/// Le code de retrait émis par Finance — l'écran de retrait et Waangu Copilot.
struct CashOutCodeCard: View {
    let token: CashOutToken

    /// Le code lui-même, dans un bloc qui se lit à voix haute sans se tromper :
    /// chiffres monospacés, sélectionnables, jamais tronqués.
    var body: some View {
        VStack(spacing: 8) {
            Text(FinanceStrings.cashOutCodeLabel)
                .font(.caption)
                .foregroundStyle(AppColors.subtitleGray)
            Text(token.code)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(AppColors.primary)
            if let expiry = token.expiresAt {
                Text(FinanceStrings.cashOutCodeExpires(
                    expiry.formatted(date: .omitted, time: .shortened)))
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
            }
            // Le mot du serveur, tel quel : « Shown once — hashed at rest.
            // Token consume ≠ financial finality. »
            if let message = token.message, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppColors.primary.opacity(0.25), lineWidth: 1))
    }
}
