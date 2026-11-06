//
//  FXAutomaticRulesView.swift
//  FeatureChat
//
//  Règles de conversion automatique — Bloc 5, chapitre 37.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Les conversions qui se déclenchent sans vous.
///
/// Une règle automatique est une **autorisation permanente** de convertir de
/// l'argent : même exigence qu'un mandat. Elle doit être visible, dater son
/// consentement, et se révoquer en un geste — une autorisation qu'on ne peut
/// pas retrouver est une autorisation qu'on ne peut pas retirer.
struct FXAutomaticRulesView: View {

    let fx: any FXConverting
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var revoking: FXAutomaticRule?

    private enum Phase {
        case loading
        case empty
        case loaded([FXAutomaticRule])
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
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.fxRulesLoading)
                case .empty:   FinanceMessage(icon: "arrow.triangle.2.circlepath",
                                              text: FinanceStrings.fxNoRule)
                case .working: FinanceProgress(label: FinanceStrings.fxRevoking)
                case .loaded(let rules): list(rules)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.fxRulesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .confirmationDialog(
                FinanceStrings.fxRevokeConfirmTitle,
                isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                titleVisibility: .visible
            ) {
                Button(FinanceStrings.fxRevoke, role: .destructive) {
                    if let rule = revoking { Task { await revoke(rule) } }
                }
                Button(FinanceStrings.cancel, role: .cancel) { revoking = nil }
            } message: {
                Text(FinanceStrings.fxRevokeConfirmDetail)
            }
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Chargement et révocation

    private func load() async {
        switch await fx.automaticRules() {
        case .success(let rules):
            phase = rules.isEmpty ? .empty : .loaded(rules)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Révoque la règle. **Irréversible** : la recréer exige un nouveau
    /// consentement, ce que le dialogue de confirmation annonce.
    private func revoke(_ rule: FXAutomaticRule) async {
        revoking = nil
        phase = .working
        let submissionKey98 = await operationKeys.key(for: FinanceOperationKeys.scope("fx.revokeRule", rule.id), deviceID: deviceID)
        switch await fx.revokeRule(rule.id, idempotency: submissionKey98) {
        case .success: await load()
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func list(_ rules: [FXAutomaticRule]) -> some View {
        List {
            ForEach(rules, id: \.id) { rule in
                Section {
                    LabeledContent(FinanceStrings.fxRuleDirection,
                                   value: "\(rule.sourceCurrency) → \(rule.targetCurrency)")
                    LabeledContent(FinanceStrings.fxRuleTrigger, value: triggerLabel(rule.trigger))

                    // Le plafond par exécution borne le risque d'une règle qui
                    // se déclenche plus souvent que prévu. Son absence se dit :
                    // « pas de plafond » n'est pas la même chose que « inconnu ».
                    if let cap = rule.maxAmountPerExecution {
                        LabeledContent(
                            FinanceStrings.fxRuleCap,
                            value: AmountEntry.format(cap.majorUnitsForDisplay, cap.currency.code)
                        )
                    } else {
                        Text(FinanceStrings.fxRuleNoCap)
                            .font(.caption).foregroundStyle(AppColors.statusWarning)
                    }

                    // La trace du consentement : quand, et sur quelle version.
                    // Sans elle, révoquer revient à contester de mémoire.
                    LabeledContent(FinanceStrings.fxRuleConsent,
                                   value: rule.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                    Text(String(format: FinanceStrings.fxRuleConsentVersion, rule.consentVersion))
                        .font(.caption2).foregroundStyle(.secondary)

                    if !rule.isActive {
                        Label(FinanceStrings.fxRuleInactive, systemImage: "pause.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Button(FinanceStrings.fxRevoke, role: .destructive) { revoking = rule }
                }
            }
        }
    }

    /// Ce qui déclenche la règle, dit en clair.
    ///
    /// `rateReaches` est une **comparaison**, pas un calcul : l'écran affiche
    /// le seuil, il ne prédit pas quand il sera atteint.
    private func triggerLabel(_ trigger: FXRuleTrigger) -> String {
        switch trigger {
        case .balanceAbove(let minorUnits):
            return String(format: FinanceStrings.fxTriggerBalanceAbove, "\(minorUnits)")
        case .rateReaches(let rate):
            return String(format: FinanceStrings.fxTriggerRateReaches, "\(rate)")
        case .scheduled(let frequency):
            return String(format: FinanceStrings.fxTriggerScheduled, frequency.rawValue)
        }
    }
}
