//
//  PayBillView.swift
//  FeatureChat
//
//  Parcours « payer une facture » — Bloc 3, chapitre 21.
//

import SwiftUI
import UIKit
import WaanguSharedUI
import WaanguCoreKit

extension BillerCategory: Identifiable {}

/// Choisit un facturier, remplit son formulaire, résout puis paie une facture.
///
/// **Le formulaire est rendu par le backend, jamais écrit ici.** Les champs
/// varient par facturier, par pays et par version de contrat : les coder
/// obligerait à redéployer l'application chaque fois qu'un facturier ajoute une
/// référence client.
struct PayBillView: View {

    let billing: any BillPaying
    /// La règle des formulaires facturier (requis, longueurs, motif), injectée
    /// par l'app — celle du Wallet. `nil` ⇒ seule la validation serveur.
    var validateField: BillFieldValidating? = nil
    /// Conversation qui porte le paiement — le fil d'où l'écran a été ouvert,
    /// ou, hors conversation, le dossier personnel résolu par
    /// `PaymentsDestination` (§5.1.1).
    ///
    /// Le prepare l'exige : sans elle, Chat Core refuse (`SYS_002`,
    /// « conversationId must not be blank »). Un objet financier appartient
    /// toujours à un dossier — payer sa facture n'oblige pas pour autant à
    /// ouvrir une discussion avec quelqu'un.
    var conversationID: String = ""
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    /// Les services de confirmation — ceux de Send Money, réutilisés.
    @Environment(\.financeFlowSurface) private var surface

    /// Prélèvements en place, pour l'onglet « Récurrents ».
    ///
    /// `nil` ⇒ l'onglet disparaît et l'écran reste une liste de facturiers.
    /// Un onglet vide qu'on ne peut pas remplir vaut moins que pas d'onglet.
    var mandates: (any MandateManaging)?

    let onDismiss: () -> Void

    @State private var phase: Phase = .loadingBillers
    @State private var categories: [BillerCategory] = []
    @State private var search: String = ""
    /// Champs déjà touchés : une erreur ne s'affiche qu'après saisie.
    @State private var touchedFields: Set<String> = []
    @State private var fieldValues: [String: String] = [:]
    @State private var amountText: String = ""
    @State private var currentForm: (BillerForm, DynamicBiller)?
    @State private var inputError: String?
    @Environment(\.financeObjectReader) private var objectReader
    @State private var tab: Tab = .billers
    @State private var openCategory: BillerCategory?
    @State private var recurring: [Mandate] = []
    @State private var recurringLoaded = false

    private enum Tab: Hashable { case recurring, billers }

    private enum Phase: Equatable {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loadingBillers
        case noBiller
        case choosingBiller
        case loadingForm(BillerForm)
        case filling(BillerForm, DynamicBiller)
        case lookingUp(BillerForm)
        case reviewing(BillerForm, Bill)
        /// Devis du prepare (§5.1) : montant, frais, total — à confirmer.
        case confirmingQuote(BillerForm, Bill, TransferQuote)
        case paying
        case done(FinancialReference)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .lookingUp, .paying: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .filling, .reviewing: return !amountText.isEmpty || fieldValues.values.contains { !$0.isEmpty }
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .filling: return { phase = .choosingBiller; inputError = nil }
        case .reviewing:
            guard let (biller, form) = currentForm else { return nil }
            return { phase = .filling(biller, form); inputError = nil }
        case .confirmingQuote(let biller, let bill, _):
            return { phase = .reviewing(biller, bill); inputError = nil }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loadingBillers:        progress(FinanceStrings.hubLoading)
                case .noBiller:              message(.searching, FinanceStrings.billNoBiller)
                case .choosingBiller:        billerList
                case .loadingForm:           progress(FinanceStrings.hubLoading)
                case .filling(let b, let f): form(b, f)
                case .lookingUp:             progress(FinanceStrings.billLookup)
                case .reviewing(let b, let bill): review(b, bill)
                case .confirmingQuote(let b, let bill, let quote): quoteReview(b, bill, quote)
                case .paying:                progress(FinanceStrings.sendSubmitting)
                case .done(let reference): FinanceSubmissionView(reference: reference, onDismiss: onDismiss)
                case .failed(let m):         failure(m)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference, onCheckAgain: nil, onDismiss: onDismiss)
                }
            }
            .financePhase(phase)
            .safeAreaInset(edge: .top) {
                if let inputError { Text(inputError).font(.footnote).foregroundStyle(AppColors.statusDanger).padding() }
            }
            .navigationTitle(FinanceStrings.billTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
        }
        .financeLoadOnce { await loadBillers() }
    }

    // MARK: - Étapes

    private func loadBillers() async {
        switch await billing.categories() {
        case .success(let list):
            categories = list
            phase = list.isEmpty ? .noBiller : .choosingBiller
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func loadForm(_ biller: BillerForm) async {
        phase = .loadingForm(biller)
        switch await billing.form(for: biller.billerFormId) {
        case .success(let f):
            if currentForm?.0.billerFormId != biller.billerFormId { fieldValues = [:] }
            currentForm = (biller, f)
            inputError = nil
            phase = .filling(biller, f)
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func lookup(_ biller: BillerForm) async {
        guard !flowIsBusy else { return }
        inputError = nil
        phase = .lookingUp(biller)
        switch await billing.lookup(billerID: biller.billerFormId, fields: fieldValues) {
        case .success(let bill):
            amountText = "\(bill.amountDue)"
            phase = .reviewing(biller, bill)
        case .failure(let e):
            inputError = FinanceStrings.errorMessage(e)
            if let (biller, form) = currentForm { phase = .filling(biller, form) }
            else { phase = .choosingBiller }
        }
    }

    private func pay(_ bill: Bill) async {
        guard case .reviewing = phase else { return }
        inputError = nil
        let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))

        // Le montant est validé contre la facture **avant** tout appel : payer
        // au-delà du dû créerait un avoir que le Chat ne sait pas suivre.
        guard let amount, bill.accepts(amount: amount) else {
            inputError = FinanceStrings.sendMissingAmount
            return
        }
        // Le prepare veut une conversation. Hors d'un fil, c'est le dossier
        // personnel du serveur (§5.1.1) que `PaymentsDestination` a déjà résolu
        // et posé ici. Vide ⇒ ni fil, ni dossier : rien ne porterait l'opération.
        guard !conversationID.isEmpty else {
            inputError = FinanceStrings.billNeedsConversation
            return
        }
        phase = .paying

        let submissionKey166 = await operationKeys.key(for: FinanceOperationKeys.scope("bill.pay", bill.reference.id, String(describing: amount)), deviceID: deviceID)

        // Contrat §5 : prepare → devis → confirmation humaine → execute. Un
        // service sans devis (implémentation locale) garde le paiement direct.
        switch await billing.quote(bill, amount: amount,
                                   conversationID: conversationID,
                                   idempotency: submissionKey166) {
        case .success(let quote):
            if case .paying = phase, let biller = reviewingBiller {
                phase = .confirmingQuote(biller, bill, quote)
            }
            return
        // `capabilityUnavailable` a deux sens : « cette implémentation ne fait
        // pas de devis » et « le serveur a refusé ». Seul le premier autorise
        // le paiement direct — sinon l'écran débiterait après un refus, et
        // afficherait l'échec du repli à la place de ce que le serveur a dit.
        case .failure(.capabilityUnavailable) where !billing.providesQuotes:
            break
        case .failure(.capabilityUnavailable):
            phase = .failed(FinanceStrings.errorMessage(.capabilityUnavailable))
            return
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
            return
        }

        switch await billing.pay(
            bill, amount: amount,
            idempotency: submissionKey166
        ) {
        case .success(let reference): phase = .done(reference)
        case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
            // La facture a pu être réglée. L'inscrire comme ambiguë la fait
            // reprendre par la réconciliation ; afficher un échec inviterait à
            // la payer une seconde fois.
            phase = .uncertain(bill.reference)
            await objectReader?.apply(FinancialOutcomeRoute.ambiguousPayload(
                reference: bill.reference, amount: amount, currency: bill.currency,
                counterpartyName: nil))
            await objectReader?.refresh(bill.reference)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    /// Le facturier du parcours en cours, pour revenir de la confirmation.
    private var reviewingBiller: BillerForm? { currentForm?.0 }

    /// Confirmation du devis : la soumission de Send Money — clé enregistrée,
    /// inscription avant l'execute, relecture après. L'execute part sur la
    /// route de l'opération préparée (`/pay-bill/execute`).
    private func confirm(_ biller: BillerForm, _ bill: Bill, _ quote: TransferQuote) async {
        guard case .confirmingQuote = phase, let surface else { return }
        phase = .paying
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: bill.billerID,
            counterpartyName: nil,
            attestation: nil,
            sendMoney: surface.sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )
        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            phase = .done(reference)
        case .needsNewAgreement:
            // Les conditions ont bougé : le nouveau devis, pas un nouveau départ.
            if case .needsNewAgreement(_, let fresh) = outcome { phase = .confirmingQuote(biller, bill, fresh) }
        case .verifying(let reference):
            // La facture a pu être réglée : jamais présenté comme un échec.
            phase = .uncertain(reference)
        case .failed(.expired):
            // Devis expiré : on en redemande un, rien n'est parti.
            phase = .reviewing(biller, bill)
            await pay(bill)
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func quoteReview(_ biller: BillerForm, _ bill: Bill, _ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) {
                    phase = .reviewing(biller, bill)
                    Task { await pay(bill) }
                }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReviewTitle,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: biller.name,
                    rows: quoteRows(bill, quote)
                ) {
                    Text(FinanceStrings.sendQuoteLimited)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.sendConfirm,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirm(biller, bill, quote) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(AppColors.walletCanvas)
        }
    }

    private func quoteRows(_ bill: Bill, _ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = []
        if !bill.customerLabel.isEmpty {
            rows.append(.init(FinanceStrings.billCustomer, bill.customerLabel))
        }
        rows.append(.init(FinanceStrings.amount, AmountEntry.format(quote.amount, quote.currency)))
        if let fee = quote.feeAmount {
            rows.append(.init(FinanceStrings.fees, AmountEntry.format(fee, quote.feeCurrency ?? quote.currency)))
        }
        if let total = quote.totalAmount {
            rows.append(.init(FinanceStrings.total,
                              AmountEntry.format(total, quote.totalCurrency ?? quote.currency),
                              isProminent: true))
        }
        return rows
    }

    private func progress(_ label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func message(_ animation: FinanceStatusAnimationKind, _ text: String) -> some View {
        VStack(spacing: 10) {
            FinanceStatusAnimation(animation).frame(width: 96, height: 96)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Un échec : l'animation « Warning Status », jouée une fois, et la raison
    /// — celle du serveur quand il en donne une.
    private func failure(_ text: String) -> some View {
        VStack(spacing: 16) {
            FinanceWarningAnimation()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(AppColors.subtitleGray)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Le choix du facturier.
    ///
    /// **Recherche en tête, catégories en grille.** La version précédente
    /// posait une `List` de sections nues et plaçait la recherche en pied :
    /// l'écran s'ouvrait sur trois intitulés gris sans rien dessous, et le seul
    /// moyen d'avancer se trouvait tout en bas. Une facture se paie de mémoire
    /// — on sait déjà lequel on cherche — donc la recherche passe au premier
    /// plan et les catégories deviennent des cibles, pas des en-têtes.
    private var billerList: some View {
        VStack(spacing: 0) {
            searchField

            if mandates != nil { tabs }

            switch tab {
            case .billers:   categoryGrid
            case .recurring: recurringList
            }
        }
        .background(AppColors.walletCanvas)
        .chatAppearanceSheet(item: $openCategory) { category in
            BillerCategorySheet(category: category) { biller in
                openCategory = nil
                Task { await loadForm(biller) }
            } onDismiss: {
                openCategory = nil
            }
        }
        .task(id: tab) { await loadRecurring() }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.subtitleGray)

            TextField(FinanceStrings.billSearch, text: $search)
                .font(.system(size: 16))
                .autocorrectionDisabled()

            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.subtitleGray.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FinanceStrings.close)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppColors.cardBackground, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var tabs: some View {
        Picker("", selection: $tab) {
            Text(FinanceStrings.billRecurring).tag(Tab.recurring)
            Text(FinanceStrings.billTitle).tag(Tab.billers)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// Catégories en grille de deux colonnes.
    ///
    /// Deux et non trois : les intitulés réels — « Eau et électricité »,
    /// « Frais de scolarité » — ne tiennent pas sur une colonne de tiers
    /// d'écran sans se couper en plein mot.
    private var categoryGrid: some View {
        ScrollView {
            if filteredCategories.isEmpty {
                noMatch
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10),
                              GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(filteredCategories, id: \.id) { category in
                        BillerCategoryTile(category: category) {
                            // Une catégorie sans facturier n'ouvre rien : la
                            // tuile est grisée, et son motif est dans la tuile.
                            guard !category.billerForms.isEmpty else { return }
                            openCategory = category
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var noMatch: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(FinanceStrings.billNoMatch)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .accessibilityElement(children: .combine)
    }

    /// Les prélèvements déjà autorisés.
    ///
    /// Ils vivent ici plutôt que dans un écran à part : « payer une facture »
    /// et « je paie déjà celle-ci tous les mois » sont la même intention, et
    /// séparer les deux fait recréer un prélèvement qui existe déjà.
    @ViewBuilder
    private var recurringList: some View {
        if recurring.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text(FinanceStrings.billNoRecurring)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .accessibilityElement(children: .combine)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(recurring) { mandate in
                        MandateRow(mandate: mandate)
                    }
                }
                .padding(16)
            }
        }
    }

    private func loadRecurring() async {
        guard tab == .recurring, let mandates, !recurringLoaded else { return }
        recurringLoaded = true
        if case .success(let list) = await mandates.mandates() {
            await MainActor.run { recurring = list }
        }
    }

    /// Recherche locale sur une liste **déjà filtrée par le backend**.
    ///
    /// Filtrer ici ne décide de rien : le backend a établi ce qui est
    /// disponible sur ce marché, on aide seulement à le retrouver.
    private var filteredCategories: [BillerCategory] {
        guard !search.isEmpty else { return categories }
        return categories.compactMap { category in
            let matches = category.billerForms.filter {
                $0.name.localizedCaseInsensitiveContains(search)
            }
            guard !matches.isEmpty else { return nil }
            return BillerCategory(
                id: category.id, name: category.name, logo: category.logo,
                icon: category.icon, shortName: category.shortName,
                billerForms: matches
            )
        }
    }

    /// Le formulaire, rendu depuis `DynamicBillerField`.
    ///
    /// Les champs sont triés par `priority` : l'ordre d'affichage est une
    /// décision du facturier, pas de l'ordre d'arrivée JSON.
    /// Le formulaire du facturier.
    ///
    /// Découpé en étapes, il passe par l'assistant partagé (`AppWizard`) :
    /// barre de progression, précédent/suivant, validation par étape — écrits
    /// une fois dans SharedUI, pas une seconde fois ici. D'un seul tenant, il
    /// reste une page simple : un assistant d'une étape n'assiste personne.
    @ViewBuilder
    private func form(_ biller: BillerForm, _ dynamic: DynamicBiller) -> some View {
        let groups = groupedFields(of: dynamic)
        if groups.count > 1 {
            wizardForm(biller, dynamic, groups: groups)
        } else {
            singlePageForm(biller, dynamic, groups: groups)
        }
    }

    /// Une étape par section du facturier, dans son ordre.
    ///
    /// Ni étape de récapitulation ni écran de fin : la facture a déjà les
    /// siens — la relecture du montant dû puis le devis à confirmer. En ajouter
    /// ferait relire deux fois la même saisie.
    private func wizardForm(_ biller: BillerForm, _ dynamic: DynamicBiller,
                            groups: [FieldGroup]) -> some View {
        AppWizard(
            steps: groups.map { group in
                WizardStep(
                    id: String(group.id),
                    title: group.section?.title ?? biller.name,
                    subtitle: group.section?.detail.isEmpty == false ? group.section?.detail : nil,
                    // La validation lit l'état de l'assistant, pas celui de
                    // la page : c'est lui qui porte la saisie en cours, et
                    // `goForward` refuse d'avancer tant qu'elle est en échec.
                    validate: { state in
                        Self.results(of: group.fields, values: Self.values(of: state),
                                     validator: validateField)
                    },
                    content: { state, errors in
                        VStack(alignment: .leading, spacing: DesignTokens.spacingL) {
                            ForEach(group.fields, id: \.fieldName) { field in
                                fieldRow(
                                    field,
                                    value: Self.binding(
                                        in: state, field: field,
                                        kind: SupportedFieldKind(rawInputType: field.inputType) ?? .text),
                                    error: Self.message(for: field, in: errors))
                            }
                        }
                    }
                )
            },
            initialFormState: fieldValues,
            includesReviewStep: false,
            skipCompletion: true,
            submitTitle: FinanceStrings.billLookup,
            // La dernière étape franchie : la saisie de l'assistant devient
            // celle du parcours, et la facture se cherche avec.
            onComplete: { state in
                fieldValues = Self.values(of: state)
                Task { await lookup(biller) }
            }
        )
        .navigationTitle(FinanceStrings.billTitle)
        .navigationBarTitleDisplayMode(.inline)
        .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack,
                             discardDetail: .moneyEntry, onClose: onDismiss)
    }

    /// L'état de validité d'une étape, pour l'assistant.
    ///
    /// La règle reste celle du Wallet, injectée : l'assistant ne décide pas de
    /// ce qui est valide, il décide seulement s'il laisse avancer.
    /// Le refus qui vise ce champ, tel que l'assistant l'a relevé.
    private static func message(for field: DynamicBillerField,
                                in errors: [WizardValidationResult]) -> String? {
        for case .invalid(let name, let message) in errors where name == field.fieldName {
            return message
        }
        return nil
    }

    static func results(of fields: [DynamicBillerField],
                                values: [String: String],
                                validator: BillFieldValidating?) -> [WizardValidationResult] {
        let failures = fields.compactMap { field -> WizardValidationResult? in
            guard let issue = validator?(field, values) else { return nil }
            let message = field.message.isEmpty
                ? FinanceStrings.billFieldError(issue, label: field.label) : field.message
            return .invalid(field: field.fieldName, message: message)
        }
        return failures.isEmpty ? [.valid] : failures
    }

    private func singlePageForm(_ biller: BillerForm, _ dynamic: DynamicBiller,
                                groups: [FieldGroup]) -> some View {
        FinancePage {
            Text(biller.name).font(.headline).foregroundStyle(AppColors.subtitleGray)
            // Les champs partagés de l'app (`CustomTextField`) : libellé,
            // erreur en ligne, bordure — pas un `TextField` refait ici.
            //
            // Groupés par les **étapes du facturier** quand il en déclare :
            // « Identification », « Compteur », « Facture » nomment ce qu'on
            // demande et pourquoi. Cinq champs à la suite perdaient ce
            // découpage, seule explication que l'utilisateur reçoive.
            ForEach(groups, id: \.id) { group in
                if let section = group.section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        if !section.detail.isEmpty {
                            Text(section.detail)
                                .font(.footnote)
                                .foregroundStyle(AppColors.subtitleGray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }
                ForEach(group.fields, id: \.fieldName) { field in
                    fieldRow(field, in: dynamic)
                }
            }
            // La validation qui fait foi est serveur : un motif client peut
            // refuser une référence pourtant valide chez le facturier.
            Text(FinanceStrings.billFieldsVerified).font(.caption).foregroundStyle(.secondary)
        } actions: {
            CustomButton(title: FinanceStrings.billLookup) {
                Task { await lookup(biller) }
            }
            .disabled(!isFormComplete(dynamic))
        }
    }

    /// Les champs, dans l'ordre du facturier, groupés par ses étapes.
    struct FieldGroup: Identifiable {
        /// `nil` : les champs que le facturier n'a rangés nulle part.
        let section: DynamicBillerSection?
        let fields: [DynamicBillerField]
        var id: Int { section?.id ?? -1 }
    }

    /// Un champ dont l'étape n'est pas décrite n'est **jamais** perdu : il
    /// rejoint le groupe sans titre, à la fin. Le masquer reviendrait à cacher
    /// une saisie que le facturier exige.
    func groupedFields(of dynamic: DynamicBiller) -> [FieldGroup] {
        let fields = Self.visibleFields(of: dynamic)
        guard !dynamic.sections.isEmpty else { return [FieldGroup(section: nil, fields: fields)] }

        var groups = dynamic.sections.compactMap { section -> FieldGroup? in
            let members = fields.filter { $0.step == section.id }
            return members.isEmpty ? nil : FieldGroup(section: section, fields: members)
        }
        let described = Set(dynamic.sections.map(\.id))
        let orphans = fields.filter { $0.step.map { !described.contains($0) } ?? true }
        if !orphans.isEmpty { groups.append(FieldGroup(section: nil, fields: orphans)) }
        return groups
    }

    @ViewBuilder
    private func fieldRow(_ field: DynamicBillerField, in dynamic: DynamicBiller) -> some View {
        fieldRow(field, value: binding(for: field, kind: SupportedFieldKind(rawInputType: field.inputType) ?? .text),
                 error: touchedFields.contains(field.fieldName) ? validationError(field) : nil)
    }

    /// Une ligne de formulaire, sur l'état qu'on lui donne.
    ///
    /// La page simple écrit dans `fieldValues` ; l'assistant écrit dans le
    /// sien. Une seule ligne pour les deux : deux rendus auraient fini par
    /// diverger sur le clavier, le masque ou le libellé d'un champ optionnel.
    @ViewBuilder
    private func fieldRow(_ field: DynamicBillerField,
                          value: Binding<String>,
                          error: String?) -> some View {
        // Un `inputType` que cette version ne sait pas rendre **bloque** le
        // champ au lieu de retomber en silence sur un champ texte. Interpréter
        // implicitement un type inconnu est ce que l'autoprompt interdit : le
        // champ pourrait être un sélecteur de compte, pas une saisie libre.
        if let kind = SupportedFieldKind(rawInputType: field.inputType), kind == .choice {
            choiceRow(field, value: value)
        } else if let kind = SupportedFieldKind(rawInputType: field.inputType) {
            CustomTextField(
                label: field.isRequired ? field.label : "\(field.label) (\(FinanceStrings.optional))",
                placeholder: field.placeholder,
                errorMessage: error,
                keyboardType: kind.keyboard,
                autocapitalization: .never,
                // Finance : une seule couleur — l'erreur se dit par le texte.
                errorTint: AppColors.primary,
                text: value
            )
            // Une référence ou un numéro ne se corrigent pas : l'autocorrection
            // remplaçait « Hhhhh » par un mot du dictionnaire.
            .autocorrectionDisabled()
        } else {
            unsupportedRow(field)
        }
    }

    /// Un champ à valeurs imposées : la liste du facturier, rien d'autre.
    /// Sans valeurs rendues, aucun choix possible — le champ est bloqué plutôt
    /// que transformé en saisie libre.
    @ViewBuilder
    private func choiceRow(_ field: DynamicBillerField, value: Binding<String>) -> some View {
        if field.allowedValues.isEmpty {
            unsupportedRow(field)
        } else {
            let selected = value.wrappedValue
            VStack(alignment: .leading, spacing: 6) {
                Text(field.isRequired ? field.label : "\(field.label) (\(FinanceStrings.optional))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.leading, 10)
                Menu {
                    ForEach(field.allowedValues, id: \.self) { option in
                        Button(LiveBillPaying.optionLabel(option)) {
                            value.wrappedValue = option
                            touchedFields.insert(field.fieldName)
                        }
                    }
                } label: {
                    HStack {
                        Text(selected.isEmpty ? FinanceStrings.billFieldChoose
                                              : LiveBillPaying.optionLabel(selected))
                            .foregroundStyle(selected.isEmpty ? AppColors.subtitleGray : AppColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(AppColors.subtitleGray)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.separator, lineWidth: 1)
                    )
                }
                .accessibilityLabel(field.label)
            }
        }
    }

    private func unsupportedRow(_ field: DynamicBillerField) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                Text(FinanceStrings.formFieldNeedsUpdate)
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppColors.statusWarning)
        }
        .accessibilityElement(children: .combine)
    }

    private func review(_ biller: BillerForm, _ bill: Bill) -> some View {
        FinancePage {
            BillReceiptCard(biller: biller, bill: bill,
                            onRefresh: { Task { await lookup(biller) } })

            if bill.allowsPartialPayment {
                VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                    Text(FinanceStrings.amount)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.subtitleGray)
                    HStack(spacing: 8) {
                        TextField("0", text: $amountText).keyboardType(.decimalPad)
                            .font(.system(size: 26, weight: .semibold))
                            .monospacedDigit()
                            .accessibilityLabel(FinanceStrings.amount)
                        Text(bill.currency)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AppColors.subtitleGray)
                    }
                    Text(FinanceStrings.billPartialHint)
                        .font(.footnote).foregroundStyle(AppColors.subtitleGray)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.separator.opacity(0.45), lineWidth: 0.5))
            }
        } actions: {
            // Le montant sur le bouton : ce qu'on confirme se lit sur ce qu'on
            // presse, sans remonter l'écran pour vérifier.
            CustomButton(title: FinanceStrings.billPayAmount(payableAmountText(bill))) {
                Task { await pay(bill) }
            }
            .disabled(bill.isStale())
        }
    }

    /// Le montant que le bouton annonce : celui saisi s'il est valide, sinon
    /// le dû. Jamais un montant que le paiement n'enverrait pas.
    private func payableAmountText(_ bill: Bill) -> String {
        let typed = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
        let amount = typed.flatMap { bill.accepts(amount: $0) ? $0 : nil } ?? bill.amountDue
        return AmountEntry.format(amount, bill.currency)
    }

    // MARK: - Aides

    /// La saisie suit les exigences du schéma **pendant** la frappe : un
    /// téléphone ne garde que des chiffres (et un `+` en tête), et aucun champ
    /// ne dépasse sa longueur maximale.
    private func binding(for field: DynamicBillerField, kind: SupportedFieldKind) -> Binding<String> {
        Binding(
            get: { fieldValues[field.fieldName] ?? "" },
            set: { raw in
                fieldValues[field.fieldName] = Self.sanitized(raw, field: field, kind: kind)
                touchedFields.insert(field.fieldName)
            }
        )
    }

    /// La même saisie, dans l'état que porte l'assistant.
    ///
    /// L'assistant tient son propre état (`WizardFormState`) : c'est lui que
    /// ses étapes lisent et que sa validation interroge. Écrire ailleurs
    /// laissait le champ vide à l'écran — la valeur partait bien dans la vue,
    /// mais l'assistant ne la voyait jamais et ne se redessinait pas.
    static func binding(in state: Binding<WizardFormState>,
                                field: DynamicBillerField,
                                kind: SupportedFieldKind) -> Binding<String> {
        Binding(
            get: { state.wrappedValue[field.fieldName] as? String ?? "" },
            set: { state.wrappedValue[field.fieldName] = sanitized($0, field: field, kind: kind) }
        )
    }

    /// Ce qu'un champ accepte **pendant** la frappe : un téléphone ne garde que
    /// des chiffres (et un `+` en tête), et aucun champ ne dépasse sa longueur.
    static func sanitized(_ raw: String, field: DynamicBillerField,
                          kind: SupportedFieldKind) -> String {
        var value = raw
        switch kind {
        case .phone:
            value = String(value.enumerated().filter { index, char in
                char.isASCII && (char.isNumber || (index == 0 && char == "+"))
            }.map(\.element))
        case .number:
            value = value.filter { $0.isASCII && $0.isNumber }
        case .text, .email, .date, .choice:
            break
        }
        if let max = field.maxLength, value.count > max { value = String(value.prefix(max)) }
        return value
    }

    /// Les valeurs de l'assistant, dans la forme que la règle attend.
    static func values(of state: WizardFormState) -> [String: String] {
        state.compactMapValues { $0 as? String }
    }

    /// Raison donnée par la règle partagée, ou `nil`.
    ///
    /// La règle ne regarde que les champs requis : un champ **optionnel mais
    /// rempli** doit tout de même respecter ses bornes — on le lui soumet donc
    /// comme requis.
    private func validationIssue(_ field: DynamicBillerField) -> BillFieldIssue? {
        guard let validateField else { return nil }
        let value = (fieldValues[field.fieldName] ?? "").trimmingCharacters(in: .whitespaces)
        guard field.isRequired || !value.isEmpty else { return nil }
        return validateField(field.isRequired ? field : field.requiringValue(), fieldValues)
    }

    /// La raison, dans la langue de l'app — sauf si le facturier a rédigé la
    /// sienne, qui l'emporte.
    private func validationError(_ field: DynamicBillerField) -> String? {
        guard let issue = validationIssue(field) else { return nil }
        if !field.message.isEmpty { return field.message }
        return FinanceStrings.billFieldError(issue, label: field.label)
    }

    /// Complet **et rendable** : un champ requis d'un type inconnu empêche la
    /// soumission, puisqu'il n'a pas pu être saisi.
    /// Les champs à montrer, dans l'ordre du facturier.
    ///
    /// `visibility` autre qu'`ALWAYS` : une condition que cette version ne sait
    /// pas évaluer. Le champ est **masqué** plutôt que montré au hasard — et il
    /// n'empêche alors pas la recherche, puisqu'il n'a pas pu être saisi.
    static func visibleFields(of dynamic: DynamicBiller) -> [DynamicBillerField] {
        dynamic.fieldList
            .filter { $0.viewDisplay.isEmpty || $0.viewDisplay.uppercased() == "ALWAYS" }
            .sorted { $0.priority < $1.priority }
    }

    private func isFormComplete(_ dynamic: DynamicBiller) -> Bool {
        Self.visibleFields(of: dynamic).allSatisfy { field in
            let value = (fieldValues[field.fieldName] ?? "").trimmingCharacters(in: .whitespaces)
            if field.isRequired {
                guard SupportedFieldKind(rawInputType: field.inputType) != nil, !value.isEmpty else { return false }
            }
            // Requis, longueurs, motif : la règle partagée — une saisie hors
            // bornes ne part pas, le Biller Hub la refuserait (`CF_055`).
            return validationIssue(field) == nil
        }
    }

    private func localized(_ key: String) -> String {
        // Résolution par TranslationKit ; le repli n'est plus qu'un
        // dernier recours. Sans cela, une clé de protocole s'affichait
        // telle quelle à l'utilisateur.
        FinanceLocalization.string(key, fallback: key.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " "))
    }
}

// MARK: - Types de champ rendables

/// Les `inputType` que cette version de l'application sait rendre.
///
/// `DynamicBillerField.inputType` est une `String` libre côté backend — c'est ce
/// qui rend le catalogue extensible sans redéploiement. La contrepartie est
/// qu'un type inconnu peut arriver à tout moment, et l'autoprompt du Bloc 4
/// l'exige explicitement : « safe fallback ou blocage contrôlé, jamais une
/// interprétation silencieuse ».
///
/// Retomber sur un champ texte semblerait inoffensif et ne l'est pas : un
/// sélecteur de compte rendu en saisie libre laisserait taper n'importe quoi
/// là où le facturier attend une valeur d'une liste fermée.
enum SupportedFieldKind: Sendable {
    case text, number, phone, email, date
    /// Valeurs imposées par le facturier : un choix, jamais une saisie libre.
    case choice

    init?(rawInputType: String) {
        switch rawInputType.lowercased() {
        case "text", "string", "":       self = .text
        case "number", "numeric", "int": self = .number
        case "phone", "tel", "msisdn":   self = .phone
        case "email":                    self = .email
        case "date":                     self = .date
        case "enum", "select", "choice": self = .choice
        default:                         return nil
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .number: return .numberPad
        case .phone:  return .phonePad
        case .email:  return .emailAddress
        case .text, .date, .choice: return .default
        }
    }
}

// MARK: - Tuile de catégorie

/// Une famille de facturiers, en tuile.
///
/// L'icône et sa couleur viennent d'une table locale indexée par la **nature**
/// de la catégorie, pas de son intitulé : l'intitulé est traduit et change de
/// marché en marché, alors que `id` est stable. Une catégorie inconnue tombe
/// sur un pictogramme neutre plutôt que sur rien.
private struct BillerCategoryTile: View {

    let category: BillerCategory
    let action: () -> Void

    private var isOpen: Bool { !category.billerForms.isEmpty }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(isOpen ? 0.14 : 0.07))
                        .frame(width: 42, height: 42)
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(isOpen ? tint : AppColors.subtitleGray)
                }

                Text(category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOpen ? AppColors.textPrimary : AppColors.subtitleGray)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(isOpen
                     ? FinanceStrings.billerCount(category.billerForms.count)
                     : FinanceStrings.billNoBillerInCategory)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.subtitleGray)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(AppColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.separator.opacity(0.45), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOpen ? .isButton : [])
    }

    /// Le pictogramme rendu par le backend l'emporte ; la table locale ne sert
    /// qu'à combler son absence.
    private var symbol: String { BillerAppearance.of(nature: category.id, logo: category.icon).symbol }

    private var tint: Color { BillerAppearance.of(category.id).tint }
}

// MARK: - Le reçu

/// La facture avant paiement, présentée comme un reçu.
///
/// Un reçu et non une pile de libellés : l'écran précédent alignait un titre,
/// un sous-titre et un montant dans un bloc teinté, et laissait les trois
/// quarts de la page vides — alors que la facture porte une échéance, des
/// arriérés, une référence et un instant de lecture qu'on ne montrait pas.
/// Ce qui est vrai de la facture est donc affiché ; ce qui manque disparaît
/// plutôt que de laisser une ligne vide.
///
/// Le trait discontinu sépare l'identité du facturier du montant, comme la
/// perforation d'un ticket : deux informations de nature différente, une seule
/// carte.
private struct BillReceiptCard: View {

    let biller: BillerForm
    let bill: Bill
    let onRefresh: () -> Void

    private var appearance: (symbol: String, tint: Color) { BillerAppearance.of(biller) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppColors.separator.opacity(0.5))
                .padding(.horizontal, 16)
            amount
            if !rows.isEmpty {
                Divider().overlay(AppColors.separator.opacity(0.5))
                    .padding(.horizontal, 16)
                VStack(spacing: 10) {
                    ForEach(rows, id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.subtitleGray)
                            Spacer(minLength: 12)
                            Text(row.value)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(16)
            }
            if bill.isStale() { staleNotice }
        }
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppColors.separator.opacity(0.45), lineWidth: 0.5))
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(appearance.tint.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: appearance.symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(appearance.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(biller.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                // Le libellé client arrive masqué du serveur — il est rendu
                // tel quel, jamais complété ni démasqué.
                Text(bill.customerLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var amount: some View {
        VStack(spacing: 4) {
            Text(FinanceStrings.billAmountDue)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.subtitleGray)
            Text(AmountEntry.format(bill.amountDue, bill.currency))
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(AppColors.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }

    /// Une lecture datée ne se paie pas en silence : le montant a pu changer.
    private var staleNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .medium))
            Text(FinanceStrings.billStale)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(FinanceStrings.billRefresh, action: onRefresh)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(AppColors.statusWarning)
        .padding(14)
        .background(AppColors.statusWarning.opacity(0.08))
    }

    /// Ce que la facture dit d'elle-même. Un champ absent ne laisse pas de
    /// ligne vide : il n'apparaît pas.
    private var rows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let due = bill.dueDate {
            rows.append((FinanceStrings.billDueDate,
                         due.formatted(date: .abbreviated, time: .omitted)))
        }
        if let arrears = bill.arrears, arrears > 0 {
            rows.append((FinanceStrings.billArrears, AmountEntry.format(arrears, bill.currency)))
        }
        rows.append((FinanceStrings.billReadAt,
                     bill.fetchedAt.formatted(.relative(presentation: .named))))
        return rows
    }
}

// MARK: - Pictogramme d'une nature de facturier

/// Icône et teinte d'une famille de facturiers.
///
/// Indexé par la **nature** (`id`, `type`), pas par l'intitulé : l'intitulé est
/// traduit et change de marché en marché, alors que la nature est stable.
/// Partagé par la grille des catégories et l'en-tête du reçu — deux tables
/// auraient fini par donner deux icônes au même facturier.
enum BillerAppearance {

    static func of(_ nature: String) -> (symbol: String, tint: Color) {
        switch nature.lowercased() {
        // L'eau d'abord : `UTILITY_WATER` contient aussi « util ».
        case let key where key.contains("water") || key.contains("eau"):
            return ("drop.fill", AppColors.water)
        case let key where key.contains("util") || key.contains("electric") || key.contains("power"):
            return ("bolt.fill", AppColors.electricity)
        case let key where key.contains("telecom") || key.contains("internet"):
            return ("antenna.radiowaves.left.and.right", AppColors.mobileTopup)
        case let key where key.contains("educ") || key.contains("school"):
            return ("graduationcap.fill", AppColors.education)
        case let key where key.contains("insur"):
            return ("shield.fill", AppColors.sendMoney)
        case let key where key.contains("loan") || key.contains("credit"):
            return ("percent", AppColors.requestMoney)
        case let key where key.contains("tv") || key.contains("media"):
            return ("play.tv.fill", AppColors.shopping)
        case let key where key.contains("tax") || key.contains("gov"):
            return ("building.columns.fill", AppColors.primary)
        default:
            return ("doc.text.fill", AppColors.primary)
        }
    }

    /// Un facturier : son propre pictogramme s'il en rend un **que le système
    /// sait dessiner**, sinon celui de sa nature.
    ///
    /// `logo` n'est pas garanti être un symbole SF : le serveur y met aussi
    /// bien une URL ou un nom d'actif à lui. `Image(systemName:)` ne dessine
    /// alors rien du tout — une pastille teintée et vide, ce qu'affichaient
    /// l'eau comme la télévision. On vérifie donc que le nom existe avant de
    /// s'en servir.
    static func of(_ biller: BillerForm) -> (symbol: String, tint: Color) {
        let nature = [biller.type, biller.billerFormId, biller.name]
            .first { !$0.isEmpty } ?? ""
        return of(nature: nature, logo: biller.logo)
    }

    /// Le pictogramme du serveur l'emporte **s'il est dessinable** ; la table
    /// locale comble son absence comme son invalidité.
    static func of(nature: String, logo: String) -> (symbol: String, tint: Color) {
        let fallback = of(nature)
        guard isSystemSymbol(logo) else { return fallback }
        return (logo, fallback.tint)
    }

    private static func isSystemSymbol(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return UIImage(systemName: name) != nil
    }
}

// MARK: - Facturiers d'une catégorie

/// Les facturiers d'une catégorie, en feuille.
///
/// En feuille et non en poussée : choisir un facturier est une étape courte, et
/// revenir à la grille doit coûter un geste, pas une navigation.
private struct BillerCategorySheet: View {

    let category: BillerCategory
    let onPick: (BillerForm) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(category.billerForms, id: \.billerFormId) { biller in
                Button {
                    onPick(biller)
                } label: {
                    HStack(spacing: 12) {
                        Text(biller.name)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FinanceStrings.close, action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Prélèvement

/// Un prélèvement autorisé.
///
/// Porte son **plafond** et sa **prochaine échéance** : ce sont les deux
/// chiffres qui disent ce qui va partir du compte sans nouvelle action, et une
/// ligne qui ne les montre pas laisse découvrir le montant au relevé.
private struct MandateRow: View {

    let mandate: Mandate

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.primary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mandate.creditorDisplayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let cap = mandate.maxAmount {
                Text(Self.format(cap))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let next = mandate.nextExecutionAt else {
            return FinanceLocalization.string("mandate_status_" + mandate.status.rawValue.lowercased(),
                                              fallback: mandate.status.rawValue)
        }
        return FinanceStrings.billNextOn(next.formatted(date: .abbreviated, time: .omitted))
    }

    /// `Money` porte son propre exposant, **qui fait autorité** : il vient du
    /// backend. Le formateur partagé le déduit de la locale, ce qui suffit à
    /// l'affichage mais pas ici, où l'information exacte est disponible.
    private static func format(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = money.currency.exponent
        formatter.locale = .current
        let value = money.majorUnitsForDisplay as NSDecimalNumber
        return (formatter.string(from: value) ?? "\(value)") + " " + money.currency.code
    }
}

extension DynamicBillerField {
    /// Le même champ, exigé — pour faire valider un champ optionnel rempli.
    /// Partagé avec Waangu Copilot, qui mène le même formulaire dans le fil.
    func requiringValue() -> DynamicBillerField {
        DynamicBillerField(
            fieldName: fieldName, label: label, dataType: dataType, inputType: inputType,
            minLength: minLength, maxLength: maxLength, isRequired: true, regex: regex,
            value: value, viewDisplay: viewDisplay, valueRange: valueRange, keyName: keyName,
            placeholder: placeholder, fieldMapping: fieldMapping, parent: parent, minBy: minBy,
            mask: mask, err: err, message: message, isMapping: isMapping, valueMask: valueMask,
            priority: priority, children: children)
    }
}
