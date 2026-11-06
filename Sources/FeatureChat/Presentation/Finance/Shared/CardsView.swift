//
//  CardsView.swift
//  FeatureChat
//
//  Cartes — Bloc 6, chapitre 48.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Les cartes détenues.
///
/// **Rien de sensible ne peut s'afficher ici.** `SafeCardPresentation` n'a ni
/// PAN, ni CVV, ni PIN, ni cryptogramme : ces champs n'existent pas dans le
/// type. Une revue de code peut oublier une règle ; un type ne peut pas montrer
/// ce qu'il ne porte pas.
struct CardsView: View {

    let cards: any CardManaging
    let transactions: any CardTransactionProviding
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var selected: SafeCardPresentation?

    private enum Phase {
        case loading
        case empty
        case loaded([SafeCardPresentation])
        case failed(String)
    }

    private var flowIsBusy: Bool {
        false
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.cardsLoading)
                case .empty:   FinanceMessage(icon: "creditcard", text: FinanceStrings.cardsEmpty)
                case .loaded(let list): grid(list)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.cardsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: $selected) { card in
                CardDetailView(
                    cardID: card.id, cards: cards, transactions: transactions,
                    stepUp: stepUp, deviceID: deviceID,
                    onDismiss: { selected = nil; Task { await load() } }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await cards.cards() {
        case .success(let list):
            phase = list.isEmpty ? .empty : .loaded(list)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func grid(_ list: [SafeCardPresentation]) -> some View {
        List(list) { card in
            Button { selected = card } label: { row(card) }
                .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func row(_ card: SafeCardPresentation) -> some View {
        FinanceCardSummary(card: card)
    }

}

/// Le détail d'une carte, et ses contrôles.
struct CardDetailView: View {

    let cardID: String
    let cards: any CardManaging
    let transactions: any CardTransactionProviding
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var pendingAction: PendingAction?
    @State private var showsTransactions = false
    @State private var replacementReason: CardReplacementReason?

    private enum Phase {
        case loading
        case loaded(CardDetail)
        case working
        case failed(String)
    }

    /// Une action sensible en attente d'authentification.
    private struct PendingAction: Identifiable {
        let kind: Kind
        let detail: CardDetail
        var id: String { "\(kind)" }

        enum Kind: Hashable {
            case unfreeze
            case replace(CardReplacementReason)
            case controls(CardControls)
        }
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .working: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.cardsLoading)
                case .working: FinanceProgress(label: FinanceStrings.cardWorking)
                case .loaded(let detail): content(detail)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.cardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: $pendingAction) { pending in
                gate(pending)
            }
            .financeDestination(isPresented: $showsTransactions) {
                CardTransactionsView(
                    cardID: cardID, transactions: transactions,
                    stepUp: stepUp, deviceID: deviceID,
                    onDismiss: { showsTransactions = false }
                )
            }
            .confirmationDialog(
                FinanceStrings.cardReplaceTitle,
                isPresented: Binding(
                    get: { replacementReason == nil && showsReplacementChoice },
                    set: { if !$0 { showsReplacementChoice = false } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(CardReplacementReason.allCases, id: \.self) { reason in
                    Button(replacementLabel(reason), role: reason.requiresImmediateBlock ? .destructive : nil) {
                        showsReplacementChoice = false
                        if case .loaded(let detail) = phase {
                            pendingAction = PendingAction(kind: .replace(reason), detail: detail)
                        }
                    }
                }
                Button(FinanceStrings.cancel, role: .cancel) { showsReplacementChoice = false }
            } message: {
                Text(FinanceStrings.cardReplaceDetail)
            }
        }
        .financeLoadOnce { await load() }
    }

    @State private var showsReplacementChoice = false

    // MARK: - Actions

    private func load() async {
        phase = .loading
        switch await cards.card(id: cardID) {
        case .success(let detail): phase = .loaded(detail)
        case .failure(let error):  phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Gèle **sans friction**.
    ///
    /// C'est le geste qu'on fait en découvrant une fraude. Une confirmation de
    /// plus coûte les secondes pendant lesquelles la carte reste utilisable —
    /// et le gel est réversible, contrairement à un débit.
    private func freeze(_ detail: CardDetail) async {
        phase = .working
        let freezeScope = FinanceOperationKeys.scope("card.freeze", detail.id, true)
        let result = await cards.setFrozen(
            cardID: detail.id, isFrozen: true,
            idempotency: await operationKeys.key(for: freezeScope, deviceID: deviceID),
            stepUp: nil
        )
        switch result {
        case .success:
            // Libérée au succès : geler, dégeler puis geler de nouveau répète la
            // même portée, et sans libération le serveur écarterait le second
            // gel comme un doublon du premier — la carte resterait utilisable.
            await operationKeys.release(freezeScope)
            await load()
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Le dégel, lui, **exige une authentification** : c'est le geste qui
    /// remet la carte en circulation.
    private func perform(_ pending: PendingAction, attestation: StepUpAttestation?) async {
        pendingAction = nil
        phase = .working
        // Portée : la carte **et** l'action, charge utile comprise. Une clé par
        // appel faisait de chaque nouvelle tentative après erreur une seconde
        // opération — un second remplacement de carte, par exemple.
        let scope = FinanceOperationKeys.scope("card.perform", cardID, String(describing: pending.kind))
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)

        switch pending.kind {
        case .unfreeze:
            let result = await cards.setFrozen(cardID: cardID, isFrozen: false,
                                               idempotency: idempotency, stepUp: attestation)
            switch result {
            case .success: await operationKeys.release(scope); await load()
            case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
            }

        case .replace(let reason):
            let result = await cards.replace(cardID: cardID, reason: reason,
                                             idempotency: idempotency, stepUp: attestation)
            switch result {
            case .success: await operationKeys.release(scope); await load()
            case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
            }

        case .controls(let controls):
            let result = await cards.applyControls(cardID: cardID, controls: controls,
                                                   idempotency: idempotency, stepUp: attestation)
            switch result {
            case .success(let updated): await operationKeys.release(scope); phase = .loaded(updated)
            case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
            }
        }
    }

    // MARK: - Vues

    private func content(_ detail: CardDetail) -> some View {
        Form {
            Section {
                FinanceCardSummary(card: detail.presentation)
                    .listRowInsets(EdgeInsets())
            }

            // Le gel en premier, et sans confirmation.
            Section {
                if detail.presentation.status.isFreezable {
                    Button {
                        Task { await freeze(detail) }
                    } label: {
                        Label(FinanceStrings.cardFreeze, systemImage: "snowflake")
                    }
                }
                if detail.presentation.status.isUnfreezable {
                    Button {
                        pendingAction = PendingAction(kind: .unfreeze, detail: detail)
                    } label: {
                        Label(FinanceStrings.cardUnfreeze, systemImage: "sun.max")
                    }
                }
                // Une carte bloquée ne se dégèle pas : le blocage vient de
                // l'émetteur, et proposer le geste produirait un échec incompris.
                if detail.presentation.status == .blocked {
                    Label(FinanceStrings.cardBlockedNote, systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                if detail.presentation.status.isFreezable {
                    Text(FinanceStrings.cardFreezeNote).font(.caption)
                }
            }

            controlsSection(detail)

            if !detail.effectiveLimits.isEmpty {
                Section(FinanceStrings.cardLimits) {
                    ForEach(detail.effectiveLimits) { limit in
                        LabeledContent(limitLabel(limit)) {
                            Text(AmountEntry.format(limit.amount.majorUnitsForDisplay, limit.amount.currency.code))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                Button {
                    showsTransactions = true
                } label: {
                    Label(FinanceStrings.cardTransactions, systemImage: "list.bullet")
                }

                if detail.presentation.status.isReplaceable {
                    Button(role: .destructive) {
                        showsReplacementChoice = true
                    } label: {
                        Label(FinanceStrings.cardReplace, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func controlsSection(_ detail: CardDetail) -> some View {
        Section {
            // Chaque bascule est une commande, pas un réglage local : elle part
            // au backend, qui reste seul juge de ce qu'il applique.
            Toggle(FinanceStrings.cardAllowInternational, isOn: Binding(
                get: { detail.controls.allowsInternational },
                set: { newValue in
                    var updated = detail.controls
                    updated = CardControls(
                        allowedChannels: updated.allowedChannels,
                        blockedMerchantCategories: updated.blockedMerchantCategories,
                        allowsInternational: newValue,
                        allowsATM: updated.allowsATM,
                        requestedLimits: updated.requestedLimits
                    )
                    pendingAction = PendingAction(kind: .controls(updated), detail: detail)
                }
            ))
            .disabled(!detail.presentation.status.canTransact)

            Toggle(FinanceStrings.cardAllowATM, isOn: Binding(
                get: { detail.controls.allowsATM },
                set: { newValue in
                    let updated = CardControls(
                        allowedChannels: detail.controls.allowedChannels,
                        blockedMerchantCategories: detail.controls.blockedMerchantCategories,
                        allowsInternational: detail.controls.allowsInternational,
                        allowsATM: newValue,
                        requestedLimits: detail.controls.requestedLimits
                    )
                    pendingAction = PendingAction(kind: .controls(updated), detail: detail)
                }
            ))
            .disabled(!detail.presentation.status.canTransact)

            ForEach(CardChannel.allCases, id: \.self) { channel in
                HStack {
                    Text(channelLabel(channel)).font(.subheadline)
                    Spacer()
                    Image(systemName: detail.controls.allowedChannels.contains(channel)
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(detail.controls.allowedChannels.contains(channel)
                                         ? Color.accentColor : Color.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(FinanceStrings.cardControls)
        } footer: {
            Text(FinanceStrings.cardControlsNote).font(.caption)
        }
    }

    private func gate(_ pending: PendingAction) -> some View {
        StepUpGate(
            authenticator: stepUp,
            requiredLevel: .biometric,
            reason: stepUpReason(pending.kind),
            correlationID: CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await perform(pending, attestation: attestation) }
            },
            onCancel: { pendingAction = nil }
        )
    }

    private func stepUpReason(_ kind: PendingAction.Kind) -> String {
        switch kind {
        case .unfreeze: return FinanceStrings.stepUpReasonCardUnfreeze
        case .replace:  return FinanceStrings.stepUpReasonCardReplace
        case .controls: return FinanceStrings.stepUpReasonCardControls
        }
    }

    private func channelLabel(_ channel: CardChannel) -> String {
        switch channel {
        case .online:      return FinanceStrings.cardChannelOnline
        case .inStore:     return FinanceStrings.cardChannelInStore
        case .contactless: return FinanceStrings.cardChannelContactless
        case .atm:         return FinanceStrings.cardChannelATM
        case .recurring:   return FinanceStrings.cardChannelRecurring
        }
    }

    private func limitLabel(_ limit: CardLimit) -> String {
        let period: String
        switch limit.period {
        case .perTransaction: period = FinanceStrings.cardLimitPerTransaction
        case .daily:          period = FinanceStrings.cardLimitDaily
        case .weekly:         period = FinanceStrings.cardLimitWeekly
        case .monthly:        period = FinanceStrings.cardLimitMonthly
        }
        let scope: String
        switch limit.scope {
        case .all:           scope = FinanceStrings.cardScopeAll
        case .atm:           scope = FinanceStrings.cardScopeATM
        case .online:        scope = FinanceStrings.cardScopeOnline
        case .international: scope = FinanceStrings.cardScopeInternational
        }
        return "\(period) · \(scope)"
    }

    private func replacementLabel(_ reason: CardReplacementReason) -> String {
        switch reason {
        case .lost:        return FinanceStrings.cardReasonLost
        case .stolen:      return FinanceStrings.cardReasonStolen
        case .damaged:     return FinanceStrings.cardReasonDamaged
        case .compromised: return FinanceStrings.cardReasonCompromised
        case .expired:     return FinanceStrings.cardReasonExpired
        }
    }
}

/// L'état d'une carte, y compris celui que ce client ne connaît pas.
struct CardStatusBadge: View {
    let status: CardStatus

    var body: some View {
        Label(label, systemImage: icon).font(.caption).foregroundStyle(tint)
    }

    private var label: String {
        switch status {
        case .requested: return FinanceStrings.cardStateRequested
        case .issued:    return FinanceStrings.cardStateIssued
        case .shipped:   return FinanceStrings.cardStateShipped
        case .active:    return FinanceStrings.cardStateActive
        case .frozen:    return FinanceStrings.cardStateFrozen
        case .blocked:   return FinanceStrings.cardStateBlocked
        case .expired:   return FinanceStrings.cardStateExpired
        case .replaced:  return FinanceStrings.cardStateReplaced
        case .cancelled: return FinanceStrings.cardStateCancelled
        case .unknown:   return FinanceStrings.cardStateUnknown
        }
    }

    private var icon: String {
        switch status {
        case .active:                        return "checkmark.circle"
        case .frozen:                        return "snowflake"
        case .blocked:                       return "lock"
        case .requested, .issued, .shipped:  return "shippingbox"
        case .expired, .replaced, .cancelled: return "xmark.circle"
        case .unknown:                       return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .active:                          return AppColors.statusSuccess
        case .frozen, .blocked:                return AppColors.statusWarning
        case .unknown:                         return .secondary
        case .expired, .replaced, .cancelled:  return .secondary
        default:                               return .primary
        }
    }
}


private struct FinanceCardSummary: View {
    let card: SafeCardPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingL) {
            HStack {
                Text(card.nickname ?? card.brand).font(.title3.bold())
                Spacer()
                Image(systemName: card.form == .physical ? "creditcard.fill" : "creditcard")
            }
            Text(card.maskedLabel).font(.title2.monospaced()).padding(.top, DesignTokens.spacingM)
            HStack {
                CardStatusBadge(status: card.status)
                    .padding(DesignTokens.spacingS)
                    .background(AppColors.background, in: Capsule())
                Spacer()
                Text(card.currency).font(.subheadline)
                if card.isProvisionedOnThisDevice { Image(systemName: "wallet.pass") }
            }
            if let month = card.expiryMonth, let year = card.expiryYear {
                Text(String(format: FinanceStrings.cardExpiry, month, year)).font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(DesignTokens.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.primary.gradient, in: RoundedRectangle(cornerRadius: 20))
        .opacity(card.status.isTerminal ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}
