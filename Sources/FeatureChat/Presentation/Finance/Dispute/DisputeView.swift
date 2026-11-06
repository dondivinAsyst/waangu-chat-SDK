//
//  DisputeView.swift
//  FeatureChat
//
//  Parcours « signaler un problème » — Bloc 3, chapitre 25.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Ouvre un litige sur une opération, **prérempli**.
///
/// Quelqu'un qui vient de subir un débit qu'il conteste est la dernière personne
/// à qui demander de retranscrire un identifiant de corrélation. Tout ce que le
/// client sait déjà est repris ; l'utilisateur choisit un motif, décrit, et
/// consent — trois gestes, pas dix.
struct DisputeView: View {

    let filing: any DisputeFiling
    let reference: FinancialReference
    let observedStatus: PaymentStatus
    let conversationID: String?
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    /// Les catégories du serveur (`GET /disputes/taxonomy`) — nil tant qu'elles se chargent.
    @State private var categories: [String]?
    @State private var category: String = ""
    @State private var description: String = ""
    @State private var consent: Bool = false
    @State private var phase: Phase = .composing

    private enum Phase: Equatable {
        case composing
        case submitting
        case done(FinancialReference)
        case failed(String)
    }

    private var draft: DisputeDraft {
        DisputeDraft(
            reference: reference,
            description: description,
            correlationID: reference.correlationID,
            observedStatus: observedStatus,
            conversationID: conversationID,
            sharingConsent: consent,
            category: category.isEmpty ? nil : category
        )
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .submitting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing: return !description.isEmpty
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
                case .composing:     composer
                case .submitting:    progress
                // Un litige se suit par ses propres routes : `/objects/` ne le connaît
                // pas, et le reçu de paiement y lisait une intention qui n'existe pas.
                case .done(let result): filed(result)
                case .failed(let m): message("exclamationmark.triangle", m)
                }
            }
            .financePhase(phase)
            .task { await loadCategories() }
            .navigationTitle(FinanceStrings.disputeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
    }

    private var composer: some View {
        Form {
            Section(FinanceStrings.disputeReason) {
                if let categories {
                    // Les catégories du serveur, telles quelles : l'app n'en invente aucune.
                    Picker(FinanceStrings.disputeReason, selection: $category) {
                        // Aucun choix par défaut : c'est l'utilisateur qui qualifie son problème.
                        Text("—").tag("")
                        ForEach(categories, id: \.self) { c in
                            Text(FinanceStrings.disputeCategoryLabel(c)).tag(c)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } else {
                    ProgressView()
                }
            }

            Section(FinanceStrings.disputeDescription) {
                TextField(FinanceStrings.optional, text: $description, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel(FinanceStrings.disputeDescription)
            }

            // Ce que l'utilisateur n'a **pas** à saisir, montré pour qu'il sache
            // ce qui part avec son signalement.
            Section(FinanceStrings.disputePrefilled) {
                LabeledContent(FinanceStrings.disputeOperation, value: reference.type.rawValue)
                LabeledContent(FinanceStrings.disputeObservedStatus, value: observedStatus.rawValue)
                LabeledContent(FinanceStrings.disputeRevision, value: "\(reference.version)")
            }

            Section {
                // Sans valeur par défaut, et à `false` : un consentement présumé
                // n'en est pas un, et le dossier part chez un tiers.
                Toggle(isOn: $consent) {
                    Text(FinanceStrings.disputeConsent).font(.caption)
                }
                .accessibilityLabel(FinanceStrings.disputeConsent)
            }

            Section {
                CustomButton(title: FinanceStrings.disputeSubmit) {
                    Task { await submit() }
                }
                .disabled(!draft.isSubmittable || category.isEmpty)
            }
            .financeActionRow()
        }
    }

    /// Le dossier ouvert : son statut, ses échéances et sa frise, lus sur `GET /disputes/{id}`.
    private func filed(_ reference: FinancialReference) -> some View {
        FinancePage {
            CopilotDisputeCard(reference: reference, disputes: filing)
        } actions: {
            CustomButton(title: FinanceStrings.close, style: .ghost, action: onDismiss)
        }
    }

    private var progress: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(FinanceStrings.sendSubmitting).font(.subheadline).foregroundStyle(.secondary)
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

    /// `GET /disputes/taxonomy` — illisible, rien ne se devine : l'écran le dit.
    private func loadCategories() async {
        guard categories == nil else { return }
        switch await filing.categories() {
        case .success(let list) where !list.isEmpty:
            categories = list
        case .success:
            phase = .failed(FinanceStrings.errorMessage(.capabilityUnavailable))
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func submit() async {
        guard case .composing = phase, draft.isSubmittable else { return }
        phase = .submitting
        let submissionKey161 = await operationKeys.key(for: FinanceOperationKeys.scope("dispute.file", String(describing: draft)), deviceID: deviceID)
        switch await filing.file(
            draft, idempotency: submissionKey161
        ) {
        case .success(let result): phase = .done(result)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func localized(_ key: String) -> String {
        // Résolution par TranslationKit ; le repli n'est plus qu'un
        // dernier recours. Sans cela, une clé de protocole s'affichait
        // telle quelle à l'utilisateur.
        FinanceLocalization.string(key, fallback: key.split(separator: ".").last.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? key)
    }
}
