//
//  RemoteFormView.swift
//  FeatureChat
//
//  Formulaires distants — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Rend un formulaire dont le backend décide de la forme.
///
/// Deux règles portent tout l'écran :
///
/// - **Un champ d'un type inconnu bloque, il ne retombe pas sur du texte.**
///   Rendre un sélecteur en saisie libre accepte des valeurs que le partenaire
///   refusera, et l'erreur n'apparaît qu'après l'envoi.
/// - **La validation qui fait foi est serveur.** Ce qui est vérifié ici évite
///   d'envoyer un formulaire manifestement vide, rien de plus.
struct RemoteFormView: View {

    let formID: String
    let context: [String: String]
    let forms: any RemoteFormProviding
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onCompleted: (RemoteFormOutcome) -> Void
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    /// Formulaire dont la soumission est d'issue inconnue.
    @State private var uncertainForm: RemoteForm?
    @State private var values: [String: String] = [:]
    @State private var initialValues: [String: String] = [:]
    @State private var fieldErrors: [String: String] = [:]

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loading
        case editing(RemoteForm)
        case submitting
        case accepted(RemoteFormOutcome)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .submitting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        if case .editing = phase { return values != initialValues }
        return false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:    FinanceProgress(label: FinanceStrings.formLoading)
                case .submitting: FinanceProgress(label: FinanceStrings.formSubmitting)
                case .editing(let form): editor(form)
                case .accepted(let outcome):
                    FinancePage {
                        Image(systemName: "doc.badge.clock").font(.largeTitle)
                        Text(outcome.messageKey ?? FinanceStrings.sendDone).font(.title2.bold())
                        if let resultID = outcome.resultID {
                            LabeledContent(FinanceStrings.receiptReference, value: resultID)
                                .textSelection(.enabled)
                        }
                    } actions: {
                        CustomButton(title: FinanceStrings.flowReturn) { onCompleted(outcome) }
                    }
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: uncertainForm.map { form in { Task { await submit(form) } } },
                                                onDismiss: onDismiss)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private var title: String {
        if case .editing(let form) = phase { return form.titleKey }
        return FinanceStrings.formTitle
    }

    // MARK: - Chargement et envoi

    private func load() async {
        phase = .loading
        switch await forms.form(id: formID, context: context) {
        case .success(let form):
            // Les valeurs pré-remplies viennent du backend, pas d'un cache local.
            values = form.fields.reduce(into: [:]) { result, field in
                if let value = field.defaultValue { result[field.name] = value }
            }
            initialValues = values
            phase = .editing(form)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func submit(_ form: RemoteForm) async {
        switch phase {
        case .editing, .uncertain: break
        default: return
        }
        guard isComplete(form) else { return }
        phase = .submitting
        fieldErrors = [:]

        let submissionKey118 = await operationKeys.key(for: FinanceOperationKeys.scope("form.submit", form.id, form.version, String(describing: values.sorted { $0.key < $1.key })), deviceID: deviceID)
        let result = await forms.submit(
            formID: form.id, formVersion: form.version, values: values,
            idempotency: submissionKey118
        )
        switch result {
        case .success(let outcome):
            if outcome.isAccepted {
                phase = .accepted(outcome)
            } else {
                // Refus **arbitré par le serveur** : on réaffiche le formulaire
                // avec ses erreurs par champ plutôt qu'un message global, qui
                // ferait relire les dix champs pour en corriger un.
                fieldErrors = outcome.fieldErrors
                phase = .editing(form)
            }
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            // Renvoyé sous la même clé, le formulaire fait rendre l'issue de la
            // première soumission au lieu d'en créer une seconde.
            uncertainForm = form
            phase = .uncertain(nil)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Rempli **et rendable**.
    ///
    /// Un champ requis d'un type inconnu empêche la soumission : il n'a pas pu
    /// être saisi, et l'envoyer vide ferait échouer côté serveur sans que
    /// l'utilisateur comprenne pourquoi.
    private func isComplete(_ form: RemoteForm) -> Bool {
        guard form.unrenderableRequiredFields().isEmpty else { return false }
        return form.fields.allSatisfy { field in
            guard field.isRequired else { return true }
            return !(values[field.name] ?? "").isEmpty
        }
    }

    // MARK: - Vues

    private func editor(_ form: RemoteForm) -> some View {
        Form {
            if let description = form.descriptionKey {
                Section { Text(description).font(.subheadline) }
            }

            Section {
                ForEach(form.fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        row(field)
                        if let help = field.helpKey {
                            Text(help).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let error = fieldErrors[field.name] {
                            Text(error).font(.caption2).foregroundStyle(AppColors.statusDanger)
                        }
                    }
                }
            }

            let blocked = form.unrenderableRequiredFields()
            if !blocked.isEmpty {
                Section {
                    Label(FinanceStrings.formNeedsUpdate, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section {
                CustomButton(title: form.submitLabelKey ?? FinanceStrings.formSubmit) { Task { await submit(form) } }
                .disabled(!isComplete(form))
                .financeActionRow()
            } footer: {
                Text(FinanceStrings.formServerValidates).font(.caption)
            }
        }
    }

    @ViewBuilder
    private func row(_ field: RemoteFormField) -> some View {
        switch field.kind {
        case .text, .number, .phone, .email, .date:
            HStack {
                Text(field.labelKey).foregroundStyle(.secondary)
                Spacer()
                TextField(field.placeholderKey ?? "", text: binding(field.name))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboard(field.kind))
                    .accessibilityLabel(field.labelKey)
            }

        case .multilineText:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.labelKey).font(.caption).foregroundStyle(.secondary)
                TextField(field.placeholderKey ?? "", text: binding(field.name), axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel(field.labelKey)
            }

        // Liste fermée : l'utilisateur choisit, il ne tape pas.
        case .select:
            Picker(field.labelKey, selection: binding(field.name)) {
                if !field.isRequired {
                    Text(FinanceStrings.formNoChoice).tag("")
                }
                ForEach(field.options) { option in
                    Text(option.labelKey).tag(option.value)
                }
            }

        case .toggle:
            Toggle(field.labelKey, isOn: Binding(
                get: { values[field.name] == "true" },
                set: { values[field.name] = $0 ? "true" : "false" }
            ))

        // Type inconnu de cette version : nommé et bloqué, jamais deviné.
        case .unsupported:
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.labelKey)
                    Text(FinanceStrings.formFieldNeedsUpdate)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppColors.statusWarning)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }

    private func keyboard(_ kind: RemoteFormFieldKind) -> UIKeyboardType {
        switch kind {
        case .number: return .numberPad
        case .phone:  return .phonePad
        case .email:  return .emailAddress
        default:      return .default
        }
    }
}
