//
//  NativeAppView.swift
//  FeatureChat
//
//  Mini-apps et commerce conversationnel — Bloc 6, chapitre 52.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Rend un objet appartenant à une application propriétaire.
///
/// **Divin ne connaît pas les neuf métiers.** Il rend une `UniversalCard` que
/// l'application remplit de libellés — jamais de vues. C'est ce qui empêche une
/// mini-app d'injecter de l'interface arbitraire dans une conversation, et ce
/// qui garde le rendu cohérent entre course, pharmacie et billetterie.
struct NativeAppObjectView: View {

    let reference: NativeObjectReference
    let apps: any NativeAppObjectProviding
    let deviceID: String
    /// Ouvre l'application propriétaire sur cet objet. C'est `AppCoordinator`
    /// qui sait le faire ; cette vue ne connaît aucune autre feature.
    let onOpenNativeApp: (NativeObjectReference) -> Void
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var descriptor: NativeAppDescriptor?

    private enum Phase {
        case loading
        case loaded(NativeAppObject)
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
                case .loading: FinanceProgress(label: FinanceStrings.nativeLoading)
                case .loaded(let object): detail(object)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.nativeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        phase = .loading

        // Le registre d'abord : router un objet de pharmacie vers l'application
        // de course produit un écran vide et un ticket de support.
        if case .success(let registry) = await apps.registry() {
            descriptor = registry.first { $0.appID == reference.appID }
        }

        guard descriptor?.handles(objectType: reference.objectType) != false else {
            phase = .failed(FinanceStrings.nativeUnsupportedObject)
            return
        }

        let result = await apps.resolve(
            appID: reference.appID, objectType: reference.objectType,
            objectID: reference.objectID
        )
        switch result {
        case .success(let object): phase = .loaded(object)
        case .failure(let error):  phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func requery(_ object: NativeAppObject) async {
        if case .success(let fresh) = await apps.requery(object.reference) {
            phase = .loaded(fresh)
        }
    }

    // MARK: - Vues

    private func detail(_ object: NativeAppObject) -> some View {
        Form {
            Section {
                UniversalCardView(card: object.card) { action in
                    handle(action, on: object)
                }
            }

            Section {
                LabeledContent(FinanceStrings.nativeLifecycle,
                               value: lifecycleLabel(object.lifecycle))
                if let app = descriptor {
                    LabeledContent(FinanceStrings.nativeOwner, value: app.owner)
                }
                LabeledContent(FinanceStrings.remittanceUpdatedAt,
                               value: object.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
            }

            // La corrélation financière : c'est ce champ qui rend le
            // rapprochement possible. Sans lui, une commande payée et un débit
            // constaté restent deux faits sans lien.
            if let financial = object.financialReference {
                Section(FinanceStrings.nativeFinancialLink) {
                    Text(financial.id)
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
            }

            Section {
                // Un état incertain se requête, il ne se recrée pas.
                if object.lifecycle.requiresRequery {
                    Button {
                        Task { await requery(object) }
                    } label: {
                        Label(FinanceStrings.remittanceRefresh, systemImage: "arrow.clockwise")
                    }
                }

                if let app = descriptor {
                    if app.isAvailable && app.capabilities.contains(.deepLink) {
                        Button(FinanceStrings.nativeOpenApp) { onOpenNativeApp(object.reference) }
                    } else {
                        fallbackRow(app)
                    }
                }
            }
        }
    }

    /// Ce qu'on propose quand l'application n'est pas joignable.
    ///
    /// Sans repli, un objet référencé dans une conversation devient un
    /// cul-de-sac le jour où l'application est retirée du marché.
    @ViewBuilder
    private func fallbackRow(_ app: NativeAppDescriptor) -> some View {
        switch app.fallback {
        case .web:
            Button(FinanceStrings.nativeOpenWeb) { onOpenNativeApp(reference) }
        case .install:
            Button(FinanceStrings.nativeInstall) { onOpenNativeApp(reference) }
        case .cardOnly:
            Text(app.unavailableReasonKey ?? FinanceStrings.nativeCardOnly)
                .font(.caption).foregroundStyle(.secondary)
        case .none:
            Text(app.unavailableReasonKey ?? FinanceStrings.nativeUnavailable)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func handle(_ action: UniversalCardAction, on object: NativeAppObject) {
        // Une action inconnue de ce client ne s'exécute pas, quoi qu'en dise
        // `isEnabled` : c'est la mini-app qui l'a déclarée, pas nous.
        guard action.kind.isExecutable, action.isEnabled else { return }

        switch action.kind {
        case .open, .track, .pay, .cancel, .contact, .receipt:
            onOpenNativeApp(object.reference)
        case .unknown:
            break
        }
    }

    private func lifecycleLabel(_ lifecycle: NativeObjectLifecycle) -> String {
        switch lifecycle {
        case .draft:      return FinanceStrings.nativeLifecycleDraft
        case .pending:    return FinanceStrings.nativeLifecyclePending
        case .confirmed:  return FinanceStrings.nativeLifecycleConfirmed
        case .inProgress: return FinanceStrings.nativeLifecycleInProgress
        case .completed:  return FinanceStrings.nativeLifecycleCompleted
        case .cancelled:  return FinanceStrings.nativeLifecycleCancelled
        case .failed:     return FinanceStrings.nativeLifecycleFailed
        case .unknown:    return FinanceStrings.nativeLifecycleUnknown
        }
    }
}

/// Rend une `UniversalCard`.
///
/// Un seul rendu pour les neuf intégrations. Ce qui varie sont des libellés que
/// l'application fournit ; ce qui est fixe est la mise en forme, qui reste
/// entre les mains de Divin.
struct UniversalCardView: View {

    let card: UniversalCard
    let onAction: (UniversalCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = card.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(card.titleKey).font(.headline)
                if let subtitle = card.subtitleKey {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                if let status = card.statusKey {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let amount = card.amount {
                Text(AmountEntry.format(amount.majorUnitsForDisplay, amount.currency.code))
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }

            ForEach(card.rows) { row in
                HStack {
                    Text(row.labelKey).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.valueKey).font(.caption)
                }
            }

            // Les actions désactivées restent **visibles avec leur motif** :
            // les masquer ferait chercher une action qui a existé hier.
            ForEach(card.actions) { action in
                VStack(alignment: .leading, spacing: 2) {
                    Button(action.labelKey) { onAction(action) }
                        .font(.subheadline)
                        .disabled(!action.isEnabled || !action.kind.isExecutable)
                    if !action.isEnabled, let reason = action.disabledReasonKey {
                        Text(reason).font(.caption2).foregroundStyle(.secondary)
                    }
                    // Une action que cette version ne sait pas rendre le dit,
                    // plutôt que de proposer un bouton inerte.
                    if !action.kind.isExecutable {
                        Text(FinanceStrings.nativeActionUnsupported)
                            .font(.caption2).foregroundStyle(AppColors.statusWarning)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// La liste des applications déclarées, et leurs capacités.
struct NativeAppRegistryView: View {

    let apps: any NativeAppObjectProviding
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case empty
        case loaded([NativeAppDescriptor])
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
                case .loading: FinanceProgress(label: FinanceStrings.nativeLoadingRegistry)
                case .empty:   FinanceMessage(icon: "square.grid.2x2", text: FinanceStrings.nativeNoApp)
                case .loaded(let list):
                    List(list) { app in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(app.displayNameKey).font(.subheadline.weight(.medium))
                                Spacer()
                                if !app.isAvailable {
                                    Text(FinanceStrings.nativeUnavailableShort)
                                        .font(.caption2).foregroundStyle(AppColors.statusWarning)
                                }
                            }
                            Text(app.owner).font(.caption2).foregroundStyle(.secondary)
                            // Les capacités accordées, visibles : une
                            // application qui peut facturer et une qui ne peut
                            // qu'afficher ne demandent pas la même confiance.
                            Text(app.capabilities.map(\.rawValue).sorted().joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                    .listStyle(.plain)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.nativeRegistryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await apps.registry() {
        case .success(let list):
            phase = list.isEmpty ? .empty : .loaded(list)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }
}
