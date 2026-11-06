//
//  CampaignView.swift
//  FeatureChat
//
//  Tontines, cagnottes et collectes — Bloc 6, chapitre 51.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Les collectes auxquelles l'utilisateur participe.
struct CampaignListView: View {

    let campaigns: any CampaignManaging
    let stepUp: any StepUpAuthenticating
    let conversationID: String?
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var selected: Campaign?

    private enum Phase {
        case loading
        case empty
        case loaded([Campaign])
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
                case .loading: FinanceProgress(label: FinanceStrings.campaignLoading)
                case .empty:   FinanceMessage(icon: "person.3", text: FinanceStrings.campaignEmpty)
                case .loaded(let list):
                    List(list) { campaign in
                        Button { selected = campaign } label: { row(campaign) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.campaignTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: $selected) { campaign in
                CampaignDetailView(
                    campaignID: campaign.id, campaigns: campaigns,
                    stepUp: stepUp, deviceID: deviceID,
                    onDismiss: { selected = nil; Task { await load() } }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await campaigns.campaigns(cursor: nil) {
        case .success(let list):
            phase = list.isEmpty ? .empty : .loaded(list)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func row(_ campaign: Campaign) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(campaign.titleKey).font(.subheadline.weight(.medium))
                Spacer()
                CampaignStateBadge(state: campaign.state)
            }

            if let target = campaign.target, let progress = campaign.progressPercent {
                ProgressView(value: min(1, Double(truncating: progress as NSNumber) / 100))
                Text(String(format: FinanceStrings.campaignProgress,
                            money(campaign.collected), money(target)))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(String(format: FinanceStrings.campaignCollectedOnly, money(campaign.collected)))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }

            // Un organisateur signalé ou nouveau se dit **dans la liste**, pas
            // seulement au moment de payer : le tri se fait à l'œil.
            if campaign.organizer.trustLevel.warrantsWarning {
                Label(FinanceStrings.campaignTrustWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(AppColors.statusWarning)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }
}

/// Le détail d'une collecte : contribuer, voter, demander un décaissement.
struct CampaignDetailView: View {

    let campaignID: String
    let campaigns: any CampaignManaging
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var amountText = ""
    @State private var isAnonymous = false
    @State private var message = ""
    @State private var pendingContribution: ContributionIntent?
    @State private var isReporting = false

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loading
        case loaded(Campaign)
        case reviewing(Campaign, ContributionIntent)
        case working
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .working: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .loaded, .reviewing: return !amountText.isEmpty || !message.isEmpty || isAnonymous
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        if case .reviewing(let campaign, _) = phase { return { phase = .loaded(campaign) } }
        return nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.campaignLoading)
                case .working: FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .loaded(let campaign): detail(campaign)
                case .reviewing(let campaign, let intent): review(campaign, intent)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await load() } },
                                                onDismiss: onDismiss)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.campaignTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: $pendingContribution) { intent in
                StepUpGate(
                    authenticator: stepUp,
                    requiredLevel: .biometric,
                    reason: FinanceStrings.stepUpReasonCampaign,
                    correlationID: CorrelationId(),
                    deviceID: deviceID,
                    onSatisfied: { attestation in
                        Task { await contribute(intent, attestation: attestation) }
                    },
                    onCancel: { pendingContribution = nil }
                )
            }
            .confirmationDialog(
                FinanceStrings.campaignReportTitle,
                isPresented: $isReporting,
                titleVisibility: .visible
            ) {
                Button(FinanceStrings.campaignReport, role: .destructive) {
                    Task { await report() }
                }
                Button(FinanceStrings.cancel, role: .cancel) { isReporting = false }
            } message: {
                Text(FinanceStrings.campaignReportDetail)
            }
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Actions

    private func load() async {
        phase = .loading
        switch await campaigns.campaign(id: campaignID) {
        case .success(let campaign): phase = .loaded(campaign)
        case .failure(let error):    phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func contribute(_ intent: ContributionIntent,
                            attestation: StepUpAttestation?) async {
        guard case .reviewing = phase, pendingContribution != nil else { return }
        pendingContribution = nil
        amountText = ""
        message = ""
        isAnonymous = false
        phase = .working
        let submissionKey222 = await operationKeys.key(for: FinanceOperationKeys.scope("campaign.contribute", String(describing: intent)), deviceID: deviceID)
        let result = await campaigns.contribute(
            intent, idempotency: submissionKey222,
            stepUp: attestation
        )
        switch result {
        case .success(let campaign): phase = .loaded(campaign)
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            // L'objet porte la vérité : le relire dit si le paiement est passé.
            // Afficher un échec inviterait à payer une seconde fois.
            phase = .uncertain(nil)
        case .failure(let error):    phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func vote(_ disbursementID: String, approve: Bool) async {
        phase = .working
        let submissionKey235 = await operationKeys.key(for: FinanceOperationKeys.scope("campaign.vote", disbursementID, approve), deviceID: deviceID)
        let result = await campaigns.vote(
            disbursementID: disbursementID, approve: approve,
            idempotency: submissionKey235
        )
        switch result {
        case .success: await load()
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Signaler est **immédiat et sans friction** : une collecte frauduleuse
    /// collecte pendant qu'on hésite.
    private func report() async {
        isReporting = false
        phase = .working
        let submissionKey250 = await operationKeys.key(for: FinanceOperationKeys.scope("campaign.report", campaignID), deviceID: deviceID)
        let result = await campaigns.report(
            campaignID: campaignID, reasonKey: "user.report.suspicious",
            idempotency: submissionKey250
        )
        switch result {
        case .success: await load()
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func requestRefund() async {
        phase = .working
        let submissionKey262 = await operationKeys.key(for: FinanceOperationKeys.scope("campaign.refund", campaignID), deviceID: deviceID)
        let result = await campaigns.requestRefund(
            campaignID: campaignID, reasonKey: "user.refund.requested",
            idempotency: submissionKey262
        )
        switch result {
        case .success: await load()
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func detail(_ campaign: Campaign) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(campaign.titleKey).font(.headline)
                    CampaignStateBadge(state: campaign.state)
                    if let description = campaign.descriptionKey {
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    // Une tontine engage un tour de cotisations : le dire
                    // **avant** l'adhésion, pas au premier appel de fonds.
                    if campaign.kind.createsRecurringObligation {
                        Label(FinanceStrings.campaignTontineNote, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(AppColors.statusWarning)
                    }
                }
            }

            trustSection(campaign)
            progressSection(campaign)

            if campaign.acceptsContributions() {
                contributionSection(campaign)
            } else {
                Section {
                    Label(unavailableReason(campaign), systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            escrowSection(campaign)

            Section {
                if campaign.policy.allowsRefund {
                    Button(FinanceStrings.campaignRequestRefund) {
                        Task { await requestRefund() }
                    }
                }
                Button(FinanceStrings.campaignReport, role: .destructive) {
                    isReporting = true
                }
            }
        }
    }

    @ViewBuilder
    private func trustSection(_ campaign: Campaign) -> some View {
        Section(FinanceStrings.campaignOrganizer) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(campaign.organizer.actor.displayName).font(.subheadline.weight(.medium))
                    Text(trustLabel(campaign.organizer.trustLevel))
                        .font(.caption2)
                        .foregroundStyle(campaign.organizer.trustLevel.warrantsWarning
                                         ? AppColors.statusWarning : Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }

        // Le bénéficiaire est **distinct** de l'organisateur : les confondre
        // rendrait invisible le changement de destinataire, qui est le vecteur
        // classique de détournement.
        Section(FinanceStrings.campaignBeneficiary) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 30))
                    .foregroundStyle(campaign.beneficiary.verification.permitsCollection
                                     ? Color.accentColor : AppColors.statusWarning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(campaign.beneficiary.actor.displayName).font(.subheadline.weight(.medium))
                    Text(beneficiaryLabel(campaign.beneficiary.verification))
                        .font(.caption2)
                        .foregroundStyle(campaign.beneficiary.verification.permitsCollection
                                         ? Color.secondary : AppColors.statusWarning)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func progressSection(_ campaign: Campaign) -> some View {
        Section(FinanceStrings.detailSection) {
            LabeledContent(FinanceStrings.campaignCollected, value: money(campaign.collected))
            if let target = campaign.target {
                LabeledContent(FinanceStrings.campaignTarget, value: money(target))
                if let progress = campaign.progressPercent {
                    ProgressView(value: min(1, Double(truncating: progress as NSNumber) / 100))
                        .accessibilityLabel("\(FinanceStrings.campaignTarget), \(progress) %")
                }
            }
            if campaign.disbursed.minorUnits > 0 {
                LabeledContent(FinanceStrings.campaignDisbursed, value: money(campaign.disbursed))
            }
            LabeledContent(FinanceStrings.campaignContributors,
                           value: "\(campaign.contributionCount)")
            if let deadline = campaign.deadline {
                LabeledContent(FinanceStrings.campaignDeadline,
                               value: deadline.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    private func contributionSection(_ campaign: Campaign) -> some View {
        Section(FinanceStrings.campaignContribute) {
            if let fixed = campaign.policy.fixedContribution {
                // Montant imposé : pas de champ de saisie, pas d'ambiguïté.
                LabeledContent(FinanceStrings.amount, value: money(fixed))
            } else {
                HStack {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(campaign.collected.currency.code).foregroundStyle(.secondary)
                }
                if let minimum = campaign.policy.minimumContribution {
                    Text(String(format: FinanceStrings.linkMinimum, money(minimum)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if campaign.policy.allowsPublicAnonymity {
                Toggle(FinanceStrings.campaignAnonymous, isOn: $isAnonymous)
                    .font(.subheadline)
                // L'anonymat est **public**, jamais réglementaire. Le dire ici
                // évite qu'un contributeur le croie opposable à la conformité.
                Text(FinanceStrings.campaignAnonymousNote)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            TextField(FinanceStrings.campaignMessage, text: $message, axis: .vertical)
                .lineLimit(1...3)

            CustomButton(title: FinanceStrings.flowReview) {
                if let intent = intent(for: campaign) { phase = .reviewing(campaign, intent) }
            }
            .disabled(intent(for: campaign) == nil)
        }
    }

    private func review(_ campaign: Campaign, _ intent: ContributionIntent) -> some View {
        FinancePage {
            Text(FinanceStrings.campaignContribute).font(.title2.bold())
            LabeledContent(FinanceStrings.receiptReference, value: campaign.id)
            FinanceAmountSummary(title: FinanceStrings.amount, value: money(intent.amount))
            if intent.isPubliclyAnonymous { Text(FinanceStrings.campaignAnonymousNote) }
            if let message = intent.messageText { Text(message) }
        } actions: {
            CustomButton(title: FinanceStrings.campaignContributeAction) { pendingContribution = intent }
        }
    }

    @ViewBuilder
    private func escrowSection(_ campaign: Campaign) -> some View {
        if let escrow = campaign.escrow {
            Section(FinanceStrings.campaignEscrow) {
                LabeledContent(FinanceStrings.campaignEscrowState,
                               value: escrowLabel(escrow.state))
                LabeledContent(FinanceStrings.campaignEscrowHeld, value: money(escrow.heldAmount))
                // Les fonds sont détenus **ailleurs**. Le dire évite de laisser
                // croire que l'application les garde.
                Text(FinanceStrings.campaignEscrowNote)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func intent(for campaign: Campaign) -> ContributionIntent? {
        let amount: Money
        if let fixed = campaign.policy.fixedContribution {
            amount = fixed
        } else {
            guard let decimal = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
                  decimal > 0 else { return nil }
            amount = Money(minorUnits: NSDecimalNumber(decimal: decimal).int64Value,
                           currency: campaign.collected.currency)
        }

        let candidate = ContributionIntent(
            campaignID: campaign.id, amount: amount,
            isPubliclyAnonymous: isAnonymous,
            messageText: message.isEmpty ? nil : message
        )
        return candidate.isWellFormed(under: campaign.policy) ? candidate : nil
    }

    private func unavailableReason(_ campaign: Campaign) -> String {
        if !campaign.beneficiary.verification.permitsCollection {
            return FinanceStrings.campaignBeneficiaryUnverified
        }
        if campaign.state == .suspended { return FinanceStrings.campaignSuspended }
        return FinanceStrings.campaignClosedToContributions
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }

    private func trustLabel(_ level: OrganizerTrustLevel) -> String {
        switch level {
        case .newOrganizer: return FinanceStrings.campaignTrustNew
        case .established:  return FinanceStrings.campaignTrustEstablished
        case .trusted:      return FinanceStrings.campaignTrustTrusted
        case .flagged:      return FinanceStrings.campaignTrustFlagged
        }
    }

    private func beneficiaryLabel(_ verification: BeneficiaryVerification) -> String {
        switch verification {
        case .unverified: return FinanceStrings.campaignBeneficiaryUnverifiedShort
        case .pending:    return FinanceStrings.campaignBeneficiaryPending
        case .verified:   return FinanceStrings.campaignBeneficiaryVerified
        case .rejected:   return FinanceStrings.campaignBeneficiaryRejected
        }
    }

    private func escrowLabel(_ state: EscrowState) -> String {
        switch state {
        case .holding:   return FinanceStrings.campaignEscrowHolding
        case .releasing: return FinanceStrings.campaignEscrowReleasing
        case .released:  return FinanceStrings.campaignEscrowReleased
        case .refunding: return FinanceStrings.campaignEscrowRefunding
        case .frozen:    return FinanceStrings.campaignEscrowFrozen
        case .unknown:   return FinanceStrings.campaignEscrowUnknown
        }
    }
}

extension ContributionIntent: Identifiable {
    public var id: String { "\(campaignID)-\(amount.minorUnits)" }
}

struct CampaignStateBadge: View {
    let state: CampaignState

    var body: some View {
        Label(label, systemImage: icon).font(.caption2).foregroundStyle(tint)
    }

    private var label: String {
        switch state {
        case .draft:      return FinanceStrings.campaignStateDraft
        case .open:       return FinanceStrings.campaignStateOpen
        case .targetMet:  return FinanceStrings.campaignStateTargetMet
        case .closed:     return FinanceStrings.campaignStateClosed
        case .disbursing: return FinanceStrings.campaignStateDisbursing
        case .completed:  return FinanceStrings.campaignStateCompleted
        case .suspended:  return FinanceStrings.campaignStateSuspended
        case .refunding:  return FinanceStrings.campaignStateRefunding
        case .cancelled:  return FinanceStrings.campaignStateCancelled
        case .unknown:    return FinanceStrings.campaignStateUnknown
        }
    }

    private var icon: String {
        switch state {
        case .open, .targetMet:      return "circle.fill"
        case .disbursing, .refunding: return "arrow.right.circle"
        case .completed:             return "checkmark.circle"
        case .suspended:             return "exclamationmark.octagon"
        case .cancelled, .closed:    return "xmark.circle"
        default:                     return "circle"
        }
    }

    private var tint: Color {
        switch state {
        case .open, .targetMet: return AppColors.statusSuccess
        case .suspended:        return AppColors.statusDanger
        case .disbursing, .refunding: return AppColors.statusWarning
        default:                return .secondary
        }
    }
}
