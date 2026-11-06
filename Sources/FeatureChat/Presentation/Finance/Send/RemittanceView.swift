//
//  RemittanceView.swift
//  FeatureChat
//
//  Envoi international — Bloc 5, chapitres 34 et 36.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Compose et suit un transfert international.
///
/// **Le corridor décide de tout** : devises acceptées, modes de réception,
/// délai, fenêtre d'annulation. Rien de cela n'est déduit ici, et l'ouverture
/// d'un sens n'ouvre jamais l'autre (§34).
struct RemittanceView: View {

    let sending: any RemittanceSending
    let recipientResolver: any RecipientResolving
    /// Satisfait le niveau exigé pour engager les fonds.
    let stepUp: any StepUpAuthenticating
    /// Bénéficiaire pré-rempli depuis la conversation. `nil` en groupe, ou
    /// quand l'utilisateur envoie ailleurs qu'à son interlocuteur.
    let recipientInput: RecipientInput?
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loadingCorridors
    /// Envoi dont le financement ou la transmission est d'issue inconnue.
    @State private var uncertainRemittance: Remittance?
    @State private var corridors: [RemittanceCorridor] = []
    @State private var selectedCorridor: RemittanceCorridor?
    @State private var selectedMethod: RemittanceDeliveryMethod?
    @State private var amountText = ""
    @State private var idempotency: IdempotencyContext?
    @State private var selectedFunding: RemittanceFundingMethod = .wallet
    /// L'envoi tel qu'il est suivi. Distinct de la phase : le suivi le
    /// remplace à chaque rafraîchissement sans refaire tout le parcours.
    @State private var tracked: Remittance?
    @State private var isConfirmingCancel = false
    @State private var trackingError: String?
    /// Le bénéficiaire retenu — celui de la conversation, ou celui saisi.
    @State private var chosenRecipient: RecipientInput?
    @State private var isChoosingRecipient = false

    private enum Phase: Equatable {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loadingCorridors
        case noCorridor
        case composing
        case quoting
        case reviewing(FinancialQuote, ResolvedRecipient)
        /// Créé mais **pas financé** : c'est ici que l'argent est engagé, et
        /// pas avant. Séparer les deux laisse la conformité intervenir sur un
        /// envoi qui n'a encore rien débité (§36).
        case funding(Remittance)
        /// Financement décidé, authentification à satisfaire.
        case awaitingStepUp(Remittance)
        case submitting
        case done(Remittance)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .quoting, .submitting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .reviewing, .awaitingStepUp: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing: return { phase = .composing; idempotency = nil }
        case .awaitingStepUp(let remittance): return { phase = .funding(remittance) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loadingCorridors:      FinanceProgress(label: FinanceStrings.hubLoading)
                case .noCorridor:            FinanceMessage(icon: "globe", text: FinanceStrings.remittanceNoCorridor)
                case .composing:             composer
                case .quoting:               FinanceProgress(label: FinanceStrings.sendQuoting)
                case .reviewing(let q, let r): review(q, r)
                case .funding(let r):        funding(r)
                case .awaitingStepUp(let r): gate(r)
                case .submitting:            FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .done(let r):           tracking(r)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: uncertainRemittance.map { remittance in { Task { await recheck(remittance) } } },
                                                onDismiss: onDismiss)
                case .failed(let m):         FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.remittanceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
        }
        .financeLoadOnce { await loadCorridors() }
    }

    private func loadCorridors() async {
        switch await sending.corridors() {
        case .success(let list):
            // Un corridor indisponible reste **visible avec son motif** : le
            // masquer laisserait l'utilisateur chercher un pays qui existe.
            corridors = list
            selectedCorridor = list.first(where: \.isAvailable)
            selectedMethod = selectedCorridor?.deliveryMethods.first
            phase = list.isEmpty ? .noCorridor : .composing
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func requestQuote() async {
        guard let corridor = selectedCorridor, let method = selectedMethod,
              let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0, let currency = corridor.targetCurrencies.first else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }
        phase = .quoting
        if idempotency == nil { idempotency = IdempotencyContext.new(deviceID: deviceID) }

        let request = RemittanceQuoteRequest(
            corridorID: corridor.id, deliveryMethod: method,
            sourceAmount: amount, targetAmount: nil, targetCurrency: currency
        )
        guard request.isWellFormed else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }

        // Sans bénéficiaire, on n'appelle même pas le devis : c'est la seule
        // chose qui manque, et la demander après coup ferait perdre la saisie.
        guard let target = chosenRecipient ?? recipientInput else {
            phase = .composing
            isChoosingRecipient = true
            return
        }

        switch await sending.quote(request) {
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        case .success(let quote):
            // Le bénéficiaire est résolu **après** le devis : un devis ne dépend
            // que du corridor et du montant, et le résoudre plus tôt ferait
            // partir une requête pour un envoi que l'utilisateur peut abandonner.
            switch await recipientResolver.resolve(target) {
            case .success(let recipient) where recipient.allowsPayment():
                phase = .reviewing(quote, recipient)
            case .success:
                phase = .failed(FinanceStrings.recipientUnavailable)
            case .failure(let e):
                phase = .failed(FinanceStrings.errorMessage(e))
            }
        }
    }

    private func submit(_ quote: FinancialQuote, _ recipient: ResolvedRecipient) async {
        guard let idempotency else { phase = .failed(FinanceStrings.sendOperationLost); return }
        phase = .submitting

        switch await sending.create(quote: quote, recipientID: recipient.recipientID,
                                    idempotency: idempotency) {
        // Créé ≠ envoyé. On s'arrête au financement : c'est l'étape qui engage
        // les fonds, et elle mérite un choix explicite.
        case .success(let remittance): phase = .funding(remittance)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    /// Finance puis transmet.
    ///
    /// Les deux appels restent distincts côté backend, mais l'échec du second
    /// ne rejoue **jamais** le premier : la même clé d'idempotence couvre le
    /// financement, et un envoi financé deux fois débiterait deux fois.
    private func fundAndSubmit(_ remittance: Remittance,
                               attestation: StepUpAttestation?) async {
        guard let idempotency else { phase = .failed(FinanceStrings.sendOperationLost); return }
        phase = .submitting

        let funded = await sending.fund(
            remittance.id, method: selectedFunding, idempotency: idempotency,
            stepUp: attestation
        )
        switch funded {
        case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
            uncertainRemittance = remittance
            phase = .uncertain(nil)
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        case .success(let remittance):
            switch await sending.submit(remittance.id, idempotency: idempotency) {
            case .success(let submitted): phase = .done(submitted)
            // Financé mais non transmis : on ne prétend pas que c'est parti.
            // L'utilisateur revient sur l'écran de financement, où l'envoi
            // existe déjà et où réessayer ne redébite pas.
            case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
                // Financé, transmission d'issue inconnue. L'envoi existe : son
                // suivi dira s'il est parti. Réessayer ne redébite pas.
                uncertainRemittance = remittance
                phase = .uncertain(nil)
            case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
            }
        }
    }

    /// Relit l'envoi et n'affiche son état **que s'il a été lu**.
    private func recheck(_ remittance: Remittance) async {
        await refresh(remittance)
        if trackingError == nil, let fresh = tracked {
            phase = .done(fresh)
        }
    }

    /// Le mode de financement, restreint à ce que le corridor accepte.
    private func funding(_ remittance: Remittance) -> some View {
        Form {
            Section(FinanceStrings.remittanceFundingMethod) {
                Picker(FinanceStrings.remittanceFundingMethod, selection: $selectedFunding) {
                    ForEach(RemittanceFundingMethod.allCases, id: \.self) { method in
                        Text(label(for: method)).tag(method)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.total) {
                    Text(AmountEntry.format(remittance.quote.totalDebit, remittance.quote.sourceCurrency))
                        .font(.body.weight(.semibold))
                }
                LabeledContent(FinanceStrings.remittanceReceives,
                               value: AmountEntry.format(remittance.quote.targetAmount, remittance.quote.targetCurrency))
            }

            Section {
                CustomButton(title: FinanceStrings.remittanceFunding) { phase = .awaitingStepUp(remittance) }
            } footer: {
                Text(FinanceStrings.remittanceFundingNote).font(.caption)
            }
        }
    }

    private func gate(_ remittance: Remittance) -> some View {
        StepUpGate(
            authenticator: stepUp,
            // Plancher pour un envoi transfrontalier.
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonRemittance,
            correlationID: idempotency?.correlationID ?? CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await fundAndSubmit(remittance, attestation: attestation) }
            },
            // Retour au choix du mode de financement : l'envoi existe déjà,
            // rien n'a été débité.
            onCancel: { phase = .funding(remittance) }
        )
    }

    /// Ce qui identifie le bénéficiaire, en une ligne.
    ///
    /// Un numéro de compte n'est jamais affiché en entier : l'écran peut être
    /// vu par-dessus l'épaule, et les quatre derniers chiffres suffisent à
    /// reconnaître le sien.
    private func summary(of input: RecipientInput) -> String {
        switch input {
        case .phoneNumber(let value):        return value
        case .walletHandle(let value):       return value
        case .merchantCode(let value):       return value
        case .qrPayload:                     return FinanceStrings.recipientFromQR
        case .mobileMoney(let op, let msisdn): return "\(op) · \(msisdn)"
        case .cashPickup(let network):       return network
        case .bankAccount(let account):
            let tail = account.accountNumber.suffix(4)
            return "\(account.accountHolderName) · ••••\(tail)"
        }
    }

    private func label(for method: RemittanceFundingMethod) -> String {
        switch method {
        case .wallet:        return FinanceStrings.remittanceFundingWallet
        case .bankAccount:   return FinanceStrings.remittanceFundingBank
        case .tokenizedCard: return FinanceStrings.remittanceFundingCard
        }
    }

    // MARK: - Vues

    private var composer: some View {
        Form {
            Section(FinanceStrings.remittanceCorridor) {
                Picker(FinanceStrings.remittanceCorridor, selection: $selectedCorridor) {
                    ForEach(corridors.filter(\.isAvailable), id: \.id) { corridor in
                        Text(corridor.id).tag(Optional(corridor))
                    }
                }
                ForEach(corridors.filter { !$0.isAvailable }, id: \.id) { closed in
                    Label(closed.id, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let corridor = selectedCorridor, corridor.deliveryMethods.count > 1 {
                Section(FinanceStrings.remittanceDelivery) {
                    Picker(FinanceStrings.remittanceDelivery, selection: $selectedMethod) {
                        ForEach(corridor.deliveryMethods, id: \.self) { method in
                            Text(method.rawValue).tag(Optional(method))
                        }
                    }
                }
            }

            Section(FinanceStrings.recipientTitle) {
                if let target = chosenRecipient ?? recipientInput {
                    LabeledContent(FinanceStrings.recipientTitle, value: summary(of: target))
                    Button(FinanceStrings.recipientChange) { isChoosingRecipient = true }
                        .font(.caption)
                } else {
                    Button(FinanceStrings.recipientChoose) { isChoosingRecipient = true }
                }
            }

            Section(FinanceStrings.amount) {
                HStack {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(selectedCorridor?.sourceCurrency ?? "").foregroundStyle(.secondary)
                }
            }

            Section {
                CustomButton(title: FinanceStrings.sendContinue) { Task { await requestQuote() } }
                .disabled(selectedCorridor == nil)
            }
            .financeActionRow()
        }
    }

    /// Réévaluée chaque seconde — voir `QuoteValidityReader`.
    private func review(_ quote: FinancialQuote, _ recipient: ResolvedRecipient) -> some View {
        QuoteValidityReader(expiresAt: quote.validUntil) { validity in
            FinancePage {
                Text(FinanceStrings.flowReview).font(.largeTitle.bold())
                QuoteValidityBanner(validity: validity) { Task { await requestQuote() } }
                FinanceRecipientRow(recipient: recipient).padding(DesignTokens.spacingM).cardStyle()
                FinanceQuoteSummary(quote: quote)
            } actions: {
                CustomButton(title: FinanceStrings.sendConfirm) { Task { await submit(quote, recipient) } }
                    .disabled(!validity.allowsConfirmation || !quote.isExecutable() || !quote.isIntact)
            }
        }
    }

    // MARK: - Suivi

    /// Redemande l'état au serveur.
    ///
    /// Un échec **ne vide pas** l'écran : perdre le suivi d'un envoi parce que
    /// le réseau a hoqueté ferait croire que l'envoi lui-même a disparu.
    private func refresh(_ remittance: Remittance) async {
        switch await sending.track(remittance.id) {
        case .success(let fresh):
            tracked = fresh
            trackingError = nil
        case .failure(let error):
            trackingError = FinanceStrings.errorMessage(error)
        }
    }

    /// Annule pendant la fenêtre ouverte par le corridor.
    ///
    /// La même clé d'idempotence que le reste du parcours : deux annulations
    /// pour un envoi ne doivent produire qu'un remboursement.
    private func cancel(_ remittance: Remittance) async {
        isConfirmingCancel = false
        guard let idempotency else { trackingError = FinanceStrings.sendOperationLost; return }

        switch await sending.cancel(remittance.id, idempotency: idempotency) {
        case .success(let cancelled):
            tracked = cancelled
            trackingError = nil
        case .failure(let error):
            trackingError = FinanceStrings.errorMessage(error)
        }
    }

    /// Suivi. **L'état vient du serveur** : la vue ne conclut rien.
    private func tracking(_ remittance: Remittance) -> some View {
        // `tracked` prime dès qu'un rafraîchissement a eu lieu.
        let current = tracked ?? remittance

        return Form {
            Section {
                LabeledContent(FinanceStrings.remittanceState) {
                    RemittanceStateBadge(state: current.state)
                }
                if let pickup = current.pickupReference {
                    // Référence de retrait : **non secrète**, elle identifie un
                    // envoi attendu et n'autorise aucun retrait à elle seule.
                    LabeledContent(FinanceStrings.remittancePickup, value: pickup)
                        .textSelection(.enabled)
                }
                LabeledContent(FinanceStrings.remittanceUpdatedAt,
                               value: current.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
            }

            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.remittanceReceives,
                               value: AmountEntry.format(current.quote.targetAmount, current.quote.targetCurrency))
                LabeledContent(FinanceStrings.total,
                               value: AmountEntry.format(current.quote.totalDebit, current.quote.sourceCurrency))
            }

            // Une preuve de remise existe ou n'existe pas ; on ne la déduit pas
            // de l'état « livré », que le partenaire peut poser avant de la
            // fournir.
            if let proof = current.deliveryProofID {
                Section(FinanceStrings.remittanceProof) {
                    Text(proof).font(.caption.monospaced()).textSelection(.enabled)
                }
            }

            if current.awaitsRefund {
                Section {
                    Label(FinanceStrings.remittanceRefundPending,
                          systemImage: "arrow.uturn.backward.circle")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            if let trackingError {
                Section {
                    Label(trackingError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section {
                Button { Task { await refresh(current) } } label: {
                    Label(FinanceStrings.remittanceRefresh, systemImage: "arrow.clockwise")
                }
                // Un envoi terminé ne bouge plus : redemander son état en
                // boucle interroge le partenaire pour rien.
                .disabled(current.state.isTerminal)

                if current.isCancellable() {
                    Button(FinanceStrings.remittanceCancel, role: .destructive) {
                        isConfirmingCancel = true
                    }
                }
            } footer: {
                if current.isCancellable(), let until = current.cancellableUntil {
                    Text(String(format: FinanceStrings.remittanceCancellableUntil,
                                until.formatted(date: .omitted, time: .shortened)))
                        .font(.caption)
                } else if !current.state.isTerminal {
                    Text(FinanceStrings.remittanceNotCancellable).font(.caption)
                }
            }
        }
        .confirmationDialog(
            FinanceStrings.remittanceCancelConfirmTitle,
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button(FinanceStrings.remittanceCancel, role: .destructive) {
                Task { await cancel(current) }
            }
            Button(FinanceStrings.cancel, role: .cancel) { isConfirmingCancel = false }
        } message: {
            Text(FinanceStrings.remittanceCancelConfirmDetail)
        }
        // Un état non terminal se rafraîchit à l'ouverture : l'utilisateur qui
        // revient sur l'écran veut savoir où en est son argent.
        .task(id: current.id) {
            if !current.state.isTerminal { await refresh(current) }
        }
    }
}

// MARK: - État d'un envoi

/// L'état d'un envoi, avec ce qu'il signifie pour l'argent.
///
/// Le libellé brut du backend ne dit rien à personne : `PARTNER_PROCESSING` et
/// `READY_FOR_PICKUP` demandent des gestes opposés du bénéficiaire.
struct RemittanceStateBadge: View {
    let state: RemittanceState

    var body: some View {
        Label(label, systemImage: icon).font(.caption).foregroundStyle(tint)
    }

    private var label: String {
        switch state {
        case .draft:             return FinanceStrings.remittanceStateDraft
        case .quoted:            return FinanceStrings.remittanceStateQuoted
        case .quoteExpired:      return FinanceStrings.remittanceStateQuoteExpired
        case .funded:            return FinanceStrings.remittanceStateFunded
        case .complianceReview:  return FinanceStrings.remittanceStateCompliance
        case .submitted:         return FinanceStrings.remittanceStateSubmitted
        case .partnerProcessing: return FinanceStrings.remittanceStateProcessing
        case .readyForPickup:    return FinanceStrings.remittanceStateReadyForPickup
        case .delivered:         return FinanceStrings.remittanceStateDelivered
        case .failed:            return FinanceStrings.remittanceStateFailed
        case .returned:          return FinanceStrings.remittanceStateReturned
        case .refundPending:     return FinanceStrings.remittanceStateRefundPending
        case .refunded:          return FinanceStrings.remittanceStateRefunded
        case .blocked:           return FinanceStrings.remittanceStateBlocked
        case .cancelled:         return FinanceStrings.remittanceStateCancelled
        }
    }

    private var icon: String {
        switch state {
        case .draft, .quoted:                 return "doc.text"
        case .quoteExpired:                   return "clock.badge.xmark"
        case .funded:                         return "creditcard"
        case .complianceReview, .blocked:     return "shield"
        case .submitted, .partnerProcessing:  return "paperplane"
        case .readyForPickup:                 return "hand.raised"
        case .delivered:                      return "checkmark.seal"
        case .failed, .returned:              return "xmark.circle"
        case .refundPending, .refunded:       return "arrow.uturn.backward.circle"
        case .cancelled:                      return "xmark.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .delivered:                                    return AppColors.statusSuccess
        case .failed, .returned, .blocked, .cancelled:      return .secondary
        case .complianceReview, .refundPending, .refunded,
             .quoteExpired:                                 return AppColors.statusWarning
        default:                                            return .primary
        }
    }
}

// MARK: - Composants partagés

/// Indicateur de progression, réutilisé par les écrans du Bloc 5.
struct FinanceProgress: View {
    let label: String
    /// `nil` ⇒ l'indicateur système.
    var animation: FinanceStatusAnimationKind?
    var body: some View {
        VStack(spacing: DesignTokens.spacingM) {
            if let animation {
                FinanceStatusAnimation(animation).frame(width: 96, height: 96)
            } else {
                ProgressView().tint(AppColors.primary).controlSize(.large)
            }
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct FinanceMessage: View {
    let icon: String
    let text: String
    var body: some View {
        // Sans pastille teintée derrière l'icône : l'aplat coloré attirait l'œil
        // sur la décoration plutôt que sur la phrase, et donnait aux écrans
        // d'état un air de gabarit. Le message porte l'information, l'icône
        // ne fait que l'annoncer.
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColors.subtitleGray)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.subtitleGray)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Bénéficiaire avec badge et avertissements.
struct FinanceRecipientRow: View {
    let recipient: ResolvedRecipient

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .font(.title2).foregroundStyle(AppColors.primary)
                .frame(width: 48, height: 48)
                .background(AppColors.primary.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    // « À » devant le nom : la ligne répond à « à qui ? », et
                    // sans le mot elle se lit comme un simple en-tête.
                    Text(FinanceStrings.recipientTo)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.subtitleGray)
                    Text(recipient.actor.displayName).font(.body.weight(.semibold))
                    if recipient.actor.verification.showsTrustBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.blue)
                    }
                }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([recipient.actor.displayName, warning].compactMap { $0 }.joined(separator: ", "))
    }

    private var warning: String? {
        if recipient.actor.verification == .revoked { return FinanceStrings.recipientRevoked }
        if recipient.actor.verification.warrantsWarning { return FinanceStrings.recipientUnverified }
        if recipient.isNewToSender { return FinanceStrings.recipientFirstTime }
        if recipient.riskSignal != .none { return FinanceStrings.recipientToCheck }
        return nil
    }
}
