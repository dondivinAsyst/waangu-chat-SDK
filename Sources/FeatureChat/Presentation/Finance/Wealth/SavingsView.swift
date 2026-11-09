//
//  SavingsView.swift
//  FeatureChat
//
//  Épargne — Bloc 5, chapitre 40.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Pockets, objectifs, règles d'alimentation, et les mouvements.
///
/// Aucun solde n'est ajusté ici. Alimenter et retirer renvoient le pocket tel
/// que le serveur le voit ensuite : décrémenter localement en attendant la
/// réponse afficherait un solde qui n'existe nulle part.
struct SavingsView: View {

    let savings: any SavingsManaging
    /// Satisfait le niveau de step-up exigé par le backend pour les retraits.
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    /// Devise imposée par le serveur. `nil` tant que la session n'a pas répondu :
    /// on ne crée pas de poche dans une devise que l'app aurait choisie.
    let currency: String?

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var movement: Movement?
    @State private var isCreating = false
    @State private var closing: SavingsPocket?

    private enum Phase: Equatable {
        case loading
        case empty
        case loaded([SavingsPocket])
        case working
        case failed(String)
    }

    /// Un mouvement en cours de saisie : quel pocket, dans quel sens.
    private struct Movement: Identifiable {
        let pocket: SavingsPocket
        let direction: Direction
        var id: String { "\(pocket.id)-\(direction)" }

        enum Direction: String { case fund, withdraw }
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
                case .loading:  FinanceProgress(label: FinanceStrings.hubLoading)
                case .empty:    empty
                case .loaded(let pockets): list(pockets)
                case .working:  FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.savingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: {
                        Label(FinanceStrings.savingsNewPocket, systemImage: "plus")
                    }
                    .disabled(currency == nil)
                }
            }
            .financeDestination(isPresented: $isCreating) {
                SavingsPocketCreationView(
                    savings: savings, deviceID: deviceID, currency: currency ?? "",
                    onCreated: { isCreating = false; Task { await load() } },
                    onDismiss: { isCreating = false }
                )
            }
            .financeDestination(item: $movement) { pending in
                SavingsMovementView(
                    pocket: pending.pocket,
                    isWithdrawal: pending.direction == .withdraw,
                    savings: savings, stepUp: stepUp, deviceID: deviceID,
                    onDone: { movement = nil; Task { await load() } },
                    onDismiss: { movement = nil }
                )
            }
            .confirmationDialog(
                FinanceStrings.savingsCloseConfirmTitle,
                isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
                titleVisibility: .visible
            ) {
                Button(FinanceStrings.savingsClose, role: .destructive) {
                    if let pocket = closing { Task { await close(pocket) } }
                }
                Button(FinanceStrings.cancel, role: .cancel) { closing = nil }
            } message: {
                Text(FinanceStrings.savingsCloseConfirmDetail)
            }
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Chargement et gestes

    private func load() async {
        switch await savings.pockets() {
        case .success(let pockets):
            phase = pockets.isEmpty ? .empty : .loaded(pockets)
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func toggleRule(_ pocket: SavingsPocket, _ rule: SavingsRule) async {
        phase = .working
        // L'état visé fait partie de la portée : suspendre puis reprendre sont
        // deux opérations, et reprendre puis suspendre de nouveau en est une
        // troisième — d'où la libération au succès.
        let scope = FinanceOperationKeys.scope("savings.toggleRule", pocket.id, rule.id, rule.isPaused)
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)
        let result = rule.isPaused
            ? await savings.resumeRule(pocketID: pocket.id, ruleID: rule.id, idempotency: idempotency)
            : await savings.pauseRule(pocketID: pocket.id, ruleID: rule.id, idempotency: idempotency)

        switch result {
        case .success: await operationKeys.release(scope); await load()
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    /// Ferme le pocket. Le solde restant est reversé **par le backend** : le
    /// client n'orchestre pas un retrait suivi d'une fermeture, ce qui laisserait
    /// un pocket vide et ouvert si la seconde moitié échouait.
    private func close(_ pocket: SavingsPocket) async {
        closing = nil
        phase = .working
        let submissionKey147 = await operationKeys.key(for: FinanceOperationKeys.scope("savings.close", pocket.id), deviceID: deviceID)
        let result = await savings.closePocket(
            pocket.id, idempotency: submissionKey147
        )
        switch result {
        case .success: await load()
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    // MARK: - Vues

    private var empty: some View {
        VStack(spacing: 16) {
            FinanceMessage(icon: "banknote", text: FinanceStrings.savingsNoPocket)
            Button(FinanceStrings.savingsNewPocket) { isCreating = true }
                .buttonStyle(.borderedProminent)
                .disabled(currency == nil)
        }
    }

    private func list(_ pockets: [SavingsPocket]) -> some View {
        List {
            ForEach(pockets) { pocket in
                Section(pocket.name) {
                    LabeledContent(FinanceStrings.savingsBalance, value: money(pocket.balance))

                    if let target = pocket.targetMinorUnits, let progress = pocket.progressPercent {
                        LabeledContent(
                            FinanceStrings.savingsGoal,
                            value: money(Money(minorUnits: target,
                                               currency: pocket.balance.currency))
                        )
                        ProgressView(value: min(1, Double(truncating: progress as NSNumber) / 100))
                            .accessibilityLabel("\(FinanceStrings.savingsGoal), \(progress) %")
                    }

                    // Rendement **affiché**, rendu par le partenaire.
                    if let yield = pocket.displayedYieldPercent {
                        LabeledContent(FinanceStrings.savingsYield, value: "\(yield) %")
                    }

                    // Les règles se suspendent et se reprennent — exigé mot pour
                    // mot au §13.
                    ForEach(pocket.rules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.kind.rawValue)
                                if let failure = rule.lastFailureKey {
                                    Text(failure)
                                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                                }
                            }
                            Spacer()
                            Button(rule.isPaused
                                   ? FinanceStrings.savingsResumeRule
                                   : FinanceStrings.savingsPauseRule) {
                                Task { await toggleRule(pocket, rule) }
                            }
                            .font(.caption)
                        }
                    }

                    actions(pocket)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ pocket: SavingsPocket) -> some View {
        // Alimenter suppose seulement un pocket vivant.
        if pocket.state.allowsMovement {
            Button(FinanceStrings.savingsFund) {
                movement = Movement(pocket: pocket, direction: .fund)
            }
        }

        // Retirer suppose en plus qu'aucune restriction ni échéance ne s'y
        // oppose. Proposer le geste sans le dire mène à un refus incompris.
        if pocket.allowsWithdrawal() {
            Button(FinanceStrings.savingsWithdraw) {
                movement = Movement(pocket: pocket, direction: .withdraw)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label(FinanceStrings.savingsLocked, systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(pocket.withdrawalRestrictionKeys, id: \.self) { key in
                    Text(key).font(.caption2).foregroundStyle(.secondary)
                }
                if let matures = pocket.maturesAt {
                    Text(String(format: FinanceStrings.savingsMaturesAt,
                                matures.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }

        if pocket.state != .closed && pocket.state != .closing {
            Button(FinanceStrings.savingsClose, role: .destructive) { closing = pocket }
        }
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }
}

// MARK: - Création d'un pocket

/// Crée un pocket d'épargne.
///
/// Le type de pocket n'est pas cosmétique : un `lockedSavings` bloque les
/// retraits, une `tontine` engage un groupe. Le choix se fait donc à la
/// création, où il est encore révisable, et non par un réglage ultérieur.
struct SavingsPocketCreationView: View {

    let savings: any SavingsManaging
    let deviceID: String
    /// Devise du serveur, jamais choisie par l'app (`FinanceSessionStatus.currency`).
    let currency: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onCreated: () -> Void
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var kind: SavingsPocketKind = .pocket
    @State private var targetText = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Date()
    @State private var phase: Phase = .composing

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case composing
        case creating
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .creating: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing: return !name.isEmpty || !targetText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .composing: form
                case .creating:  FinanceProgress(label: FinanceStrings.savingsCreating)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await create() } },
                                                onDismiss: onDismiss)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.savingsNewPocket)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
    }

    private func create() async {
        phase = .creating
        // L'objectif est facultatif. Un objectif vide n'est pas zéro : un
        // objectif à zéro afficherait une progression de 100 % dès l'ouverture.
        let target = Decimal(string: targetText.replacingOccurrences(of: ",", with: "."))
        let draft = SavingsPocketDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            currency: currency,
            // Saisi en unités majeures ; le brouillon porte des unités mineures
            // (exposant ISO 4217 de la devise du serveur).
            targetMinorUnits: target.map {
                NSDecimalNumber(decimal: $0 * pow(Decimal(10), LiveInvoiceProvider.exponent(of: currency))).int64Value
            },
            targetDate: hasTargetDate ? targetDate : nil
        )
        let submissionKey327 = await operationKeys.key(for: FinanceOperationKeys.scope("savings.create", String(describing: draft)), deviceID: deviceID)
        switch await savings.create(draft, idempotency: submissionKey327) {
        case .success: onCreated()
        case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
            // Même brouillon, même clé : une seconde tentative rend le pocket créé.
            phase = .uncertain(nil)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private var form: some View {
        Form {
            Section(FinanceStrings.savingsPocketName) {
                TextField(FinanceStrings.savingsPocketName, text: $name)
            }

            Section(FinanceStrings.savingsPocketKind) {
                Picker(FinanceStrings.savingsPocketKind, selection: $kind) {
                    ForEach(SavingsPocketKind.allCases, id: \.self) { value in
                        Text(label(for: value)).tag(value)
                    }
                }
                Text(explanation(for: kind)).font(.caption).foregroundStyle(.secondary)
            }

            Section(FinanceStrings.savingsGoal) {
                HStack {
                    TextField(FinanceStrings.savingsGoalOptional, text: $targetText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.savingsGoal)
                    Text(currency).foregroundStyle(.secondary)
                }
                Toggle(FinanceStrings.savingsGoalDate, isOn: $hasTargetDate)
                if hasTargetDate {
                    DatePicker(FinanceStrings.savingsGoalDate, selection: $targetDate,
                               in: Date()..., displayedComponents: .date)
                }
            }

            Section {
                CustomButton(title: FinanceStrings.savingsCreate) { Task { await create() } }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .financeActionRow()
        }
    }

    private func label(for kind: SavingsPocketKind) -> String {
        switch kind {
        case .pocket:         return FinanceStrings.savingsKindPocket
        case .vault:          return FinanceStrings.savingsKindVault
        case .lockedSavings:  return FinanceStrings.savingsKindLocked
        case .partnerProduct: return FinanceStrings.savingsKindPartner
        case .groupGoal:      return FinanceStrings.savingsKindGroup
        case .tontine:        return FinanceStrings.savingsKindTontine
        }
    }

    /// Ce que le type implique — dit avant le choix, pas découvert au premier
    /// retrait refusé.
    private func explanation(for kind: SavingsPocketKind) -> String {
        switch kind {
        case .pocket:         return FinanceStrings.savingsKindPocketNote
        case .vault:          return FinanceStrings.savingsKindVaultNote
        case .lockedSavings:  return FinanceStrings.savingsKindLockedNote
        case .partnerProduct: return FinanceStrings.savingsKindPartnerNote
        case .groupGoal:      return FinanceStrings.savingsKindGroupNote
        case .tontine:        return FinanceStrings.savingsKindTontineNote
        }
    }
}

// MARK: - Alimenter et retirer

/// Un mouvement sur un pocket, dans un sens ou dans l'autre.
///
/// Les deux sens partagent l'écran mais pas les règles : retirer engage des
/// fonds vers l'extérieur et le backend exige un step-up, alimenter non.
struct SavingsMovementView: View {

    let pocket: SavingsPocket
    let isWithdrawal: Bool
    let savings: any SavingsManaging
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    let onDone: () -> Void
    let onDismiss: () -> Void

    @State private var amountText = ""
    @State private var phase: Phase = .composing
    /// Une seule clé pour toute la tentative, step-up compris : la regénérer
    /// après l'authentification produirait un second mouvement si le premier
    /// avait abouti sans que la réponse revienne.
    @State private var idempotency: IdempotencyContext?
    @Environment(\.financeOperationKeys) private var operationKeys

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case composing
        case reviewing(Money)
        /// Le montant est arrêté, l'authentification reste à satisfaire.
        case awaitingStepUp(Money)
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
        case .composing, .reviewing, .awaitingStepUp: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing: return { phase = .composing }
        case .awaitingStepUp(let amount): return { phase = .reviewing(amount) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .composing: form
                case .reviewing(let amount): review(amount)
                case .awaitingStepUp(let amount): gate(amount)
                case .working:   FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { onDone() },
                                                onDismiss: onDismiss)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(isWithdrawal ? FinanceStrings.savingsWithdraw : FinanceStrings.savingsFund)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
    }

    /// Valide le montant puis oriente : alimenter part directement, retirer
    /// passe par l'authentification.
    private func submit() async {
        guard case .composing = phase else { return }
        guard let decimal = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              decimal > 0
        else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }

        // L'exposant vient du pocket, pas d'une constante : BIF vaut 0, CAD
        // vaut 2, et le coder en dur produirait un facteur 100.
        let amount = Money(
            minorUnits: NSDecimalNumber(decimal: decimal).int64Value,
            currency: CurrencyCode(code: pocket.currency, exponent: pocket.exponent)
        )
        // Persistée, et non plus tenue dans l'état : un kill pendant le
        // mouvement la perdait, et le geste refait partait sous une clé neuve.
        idempotency = await operationKeys.key(for: moveScope(amount), deviceID: deviceID)

        phase = .reviewing(amount)
    }

    private func moveScope(_ amount: Money) -> String {
        FinanceOperationKeys.scope(isWithdrawal ? "savings.withdraw" : "savings.fund",
                                   pocket.id, amount.minorUnits, amount.currency.code)
    }

    private func move(_ amount: Money, attestation: StepUpAttestation?) async {
        switch phase {
        case .reviewing, .awaitingStepUp: break
        default: return
        }
        phase = .working
        let scope = moveScope(amount)
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)

        let result = isWithdrawal
            ? await savings.withdraw(pocketID: pocket.id, amount: amount,
                                     idempotency: idempotency, stepUp: attestation)
            : await savings.fund(pocketID: pocket.id, amount: amount, idempotency: idempotency)

        switch result {
        case .success:
            // Mouvement confirmé : un second versement identique sera nouveau.
            await operationKeys.release(scope)
            onDone()
        case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
            // Le mouvement a peut-être eu lieu. Revenir au pocket en relit le
            // solde, qui dit ce qui s'est passé ; un échec ferait refaire le geste.
            phase = .uncertain(nil)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func gate(_ amount: Money) -> some View {
        StepUpGate(
            authenticator: stepUp,
            // Plancher pour une sortie d'épargne. Le backend peut exiger plus ;
            // il ne peut pas exiger moins par l'absence de réponse.
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonWithdraw,
            correlationID: idempotency?.correlationID ?? CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await move(amount, attestation: attestation) }
            },
            // Annuler ramène à la saisie, sans perdre le montant tapé.
            onCancel: { phase = .reviewing(amount) }
        )
    }

    private func review(_ amount: Money) -> some View {
        FinancePage {
            Text(pocket.name).font(.title2.bold())
            FinanceAmountSummary(title: FinanceStrings.amount,
                                 value: AmountEntry.format(amount.majorUnitsForDisplay, amount.currency.code))
            Text(FinanceStrings.savingsMovementNote).foregroundStyle(.secondary)
        } actions: {
            CustomButton(title: isWithdrawal ? FinanceStrings.savingsWithdraw : FinanceStrings.savingsFund) {
                if isWithdrawal { phase = .awaitingStepUp(amount) }
                else { Task { await move(amount, attestation: nil) } }
            }
        }
    }

    private var form: some View {
        Form {
            Section(pocket.name) {
                LabeledContent(
                    FinanceStrings.savingsBalance,
                    value: AmountEntry.format(pocket.balance.majorUnitsForDisplay, pocket.currency)
                )
            }

            Section(FinanceStrings.amount) {
                HStack {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(pocket.currency).foregroundStyle(.secondary)
                }
            }

            Section {
                CustomButton(title: FinanceStrings.flowReview) { Task { await submit() } }
                .disabled(amountText.isEmpty)
            } footer: {
                // Le solde disponible n'est pas vérifié ici : le client ne
                // connaît pas les fonds réservés, et refuser localement un
                // retrait pourtant possible est pire que le laisser au backend.
                Text(FinanceStrings.savingsMovementNote).font(.caption)
            }
        }
    }
}
