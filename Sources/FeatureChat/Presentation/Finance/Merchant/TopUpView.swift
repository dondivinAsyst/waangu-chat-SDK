//
//  TopUpView.swift
//  FeatureChat
//
//  Parcours « recharger » — Bloc 3, chapitre 23.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Recharge une ou plusieurs lignes, et rend compte de **chacune**.
///
/// **L'écran de résultat est la raison d'être de cette vue.** Une recharge
/// groupée de cinq lignes peut en réussir trois ; afficher « échoué » sur une
/// opération partiellement débitée est un faux état, et le Bloc 1 a été écrit
/// pour les empêcher.
struct TopUpView: View {

    let ordering: any TopUpOrdering
    let conversationID: String
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    /// Numéro du pair, comme point de départ. L'opérateur est déterminé par le
    /// backend : un préfixe deviné devient faux dès qu'un numéro est porté.
    let suggestedNumber: String?
    let onDismiss: () -> Void

    /// Les services de confirmation — ceux de Send Money, réutilisés.
    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeObjectReader) private var objectReader

    @State private var phase: Phase = .composing
    @State private var msisdn: String = ""
    @State private var products: [TopUpProduct] = []
    @State private var selected: TopUpProduct?

    /// Les numéros déjà retenus, en plus de celui en cours de saisie.
    ///
    /// Un seul numéro reste le cas ordinaire : la liste est vide, et le champ
    /// porte tout. Elle se remplit quand on ajoute un destinataire, et c'est
    /// alors `/top-up/bulk` qui prépare — **un FCO par ligne**.
    @State private var numbers: [String] = []

    /// Tous les destinataires : ceux retenus, plus la saisie en cours si elle
    /// tient debout. Sans cela, taper un numéro et appuyer sur « Continuer »
    /// sans l'avoir « ajouté » le perdrait en silence.
    private var allNumbers: [String] {
        let pending = msisdn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending.count >= 6, !numbers.contains(pending) else { return numbers }
        return numbers + [pending]
    }

    private enum Phase: Equatable {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case composing
        case loadingCatalog
        case noProduct
        case choosing
        case reviewing
        case ordering
        /// Devis rendu par `/top-up/prepare` : frais, total, à confirmer.
        /// Recharger ne commence qu'après cette acceptation (§5.3).
        case confirmingQuote(TransferQuote)
        /// Un devis **par destinataire**, rendus par `/top-up/bulk`. Le total
        /// affiché est leur somme ; chacun s'exécute pour son propre compte.
        case confirmingBatch([TopUpQuotedLine])
        /// Lot en cours : les lignes déjà rendues, et celle qui part.
        case submittingBatch(done: Int, total: Int)
        case result(TopUpOrder)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .loadingCatalog, .ordering, .submittingBatch: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .choosing, .reviewing: return !allNumbers.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .choosing, .noProduct: return { phase = .composing }
        case .reviewing: return { phase = .choosing }
        // Revenir sur un devis l'abandonne : rien n'est débité tant qu'il
        // n'est pas confirmé, et le suivant sera demandé à neuf.
        case .confirmingQuote, .confirmingBatch: return { phase = .reviewing }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .composing:       numberEntry
                case .loadingCatalog:  progress(FinanceStrings.hubLoading)
                case .noProduct:       message("antenna.radiowaves.left.and.right.slash",
                                               FinanceStrings.topUpNoProduct)
                case .choosing:        productList
                case .reviewing: review
                case .ordering:        progress(FinanceStrings.sendSubmitting)
                case .confirmingQuote(let quote): quoteReview(quote)
                case .confirmingBatch(let lines): batchReview(lines)
                case .submittingBatch(let done, let total):
                    progress(FinanceStrings.topUpBatchProgress(done, total))
                case .result(let o):   resultView(o)
                case .failed(let m):   message("exclamationmark.triangle", m)
                case .uncertain(let reference):
                    // Avec une référence, « revérifier » relit l'état
                    // (`/top-up/requery`) : repasser par la commande sous la
                    // même clé est le repli du service sans devis, pas une
                    // seconde recharge.
                    FinanceUncertainOutcomeView(
                        reference: reference,
                        onCheckAgain: {
                            Task {
                                if let reference { await read(reference) } else { await placeOrder() }
                            }
                        },
                        onDismiss: onDismiss)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.topUpTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
        }
        .onAppear { if msisdn.isEmpty, let n = suggestedNumber { msisdn = n } }
    }

    // MARK: - Étapes

    private func loadCatalog() async {
        phase = .loadingCatalog
        // Le catalogue se lit sur le premier destinataire : le lot n'accepte
        // qu'un produit, et c'est le pays — pas le numéro — qui le détermine.
        switch await ordering.catalog(for: allNumbers.first ?? msisdn) {
        case .success(let list):
            products = list
            selected = list.first
            phase = list.isEmpty ? .noProduct : .choosing
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func placeOrder() async {
        // `.uncertain` admis : renvoyer la commande sous la **même clé** fait rendre
        // par le serveur l'issue de la première tentative, jamais une seconde recharge.
        switch phase {
        case .reviewing, .uncertain: break
        default: return
        }
        guard let product = selected else { return }
        let recipients = allNumbers
        guard !recipients.isEmpty else { return }
        phase = .ordering

        let request = TopUpOrderRequest(
            lines: recipients.map { TopUpLine(msisdn: $0, productID: product.id) },
            conversationID: conversationID
        )

        let submissionKey113 = await operationKeys.key(for: FinanceOperationKeys.scope("topup.order", String(describing: request)), deviceID: deviceID)

        // Contrat §5.3 : prepare → devis → confirmation humaine → execute. Un
        // service sans devis garde l'ordre direct.
        if ordering.providesQuotes {
            // Plusieurs destinataires ⇒ `/top-up/bulk`, un FCO par ligne. Un
            // seul ⇒ `/top-up/prepare` : le lot n'a pas à exister pour un numéro.
            let outcome: Result<[TopUpQuotedLine], FinanceError>
            if recipients.count == 1 {
                outcome = await ordering.quote(request, idempotency: submissionKey113)
                    .map { [TopUpQuotedLine(msisdn: recipients[0], quote: $0)] }
            } else {
                outcome = await ordering.quoteBatch(request, idempotency: submissionKey113)
            }

            switch outcome {
            case .success(let lines) where lines.count == 1:
                phase = .confirmingQuote(lines[0].quote)
            case .success(let lines):
                phase = .confirmingBatch(lines)
            case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
                phase = .uncertain(nil)
            case .failure(let e):     phase = .failed(FinanceStrings.errorMessage(e))
            }
            return
        }

        switch await ordering.order(
            request, idempotency: submissionKey113
        ) {
        case .success(let order): phase = .result(order)
        case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
            phase = .uncertain(nil)
        case .failure(let e):     phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    /// La confirmation humaine, puis l'execute — la soumission partagée de
    /// Send Money : clé enregistrée, inscription avant l'envoi, relecture après.
    private func confirm(_ quote: TransferQuote) async {
        guard case .confirmingQuote = phase, let surface else { return }
        phase = .ordering
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: msisdn,
            counterpartyName: nil,
            attestation: nil,
            sendMoney: surface.sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )
        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            // Le débit est parti ; le crédit télécom, non. L'overlay dit les
            // deux séparément — c'est lui qui remplit le compte rendu, jamais
            // une réussite déduite de la soumission.
            await read(reference)
        case .needsNewAgreement:
            if case .needsNewAgreement(_, let fresh) = outcome { phase = .confirmingQuote(fresh) }
        case .verifying(let reference):
            phase = .uncertain(reference)
        case .failed(.expired):
            // Devis périmé : en redemander un, jamais confirmer l'ancien.
            phase = .reviewing
            await placeOrder()
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Le lot : **un execute par ligne**, et un compte rendu par destinataire.
    ///
    /// Le contrat l'exige — « chaque ligne = son propre FCO + confirmation (pas
    /// un seul execute pour le lot) ». Chaque confirmation prend sa clé de
    /// `TransferSubmission`, dont la portée est la référence du devis : deux
    /// lignes ne peuvent donc pas partager une clé, et reprendre un lot
    /// interrompu rejoue chaque ligne sous la sienne — le serveur rend alors
    /// l'issue de la première tentative au lieu de recharger deux fois.
    ///
    /// Une ligne qui échoue **n'arrête pas** les suivantes : c'est tout l'objet
    /// du compte rendu partiel. Les arrêter laisserait l'utilisateur débité
    /// pour le début du lot sans savoir ce qui reste à faire.
    private func confirmBatch(_ lines: [TopUpQuotedLine]) async {
        guard case .confirmingBatch = phase, let surface else { return }

        var results: [TopUpLineResult] = []
        var firstReference: FinancialReference?

        for (index, line) in lines.enumerated() {
            phase = .submittingBatch(done: index, total: lines.count)

            let outcome = await TransferSubmission.confirm(
                line.quote,
                recipientID: line.msisdn,
                counterpartyName: nil,
                attestation: nil,
                sendMoney: surface.sendMoney,
                operationKeys: operationKeys,
                objects: objectReader,
                deviceID: deviceID
            )
            if firstReference == nil { firstReference = line.quote.reference }

            // Le sort de *cette* ligne, sans rien conclure des autres.
            let status: PaymentStatus
            switch FinancialOutcomeRoute.route(outcome, submittedReference: line.quote.reference) {
            case .submitted:          status = .queued
            case .verifying:          status = .unknown
            case .needsNewAgreement:  status = .expired
            case .failed(.expired):   status = .expired
            case .failed:             status = .failed
            }
            results.append(TopUpLineResult(id: line.quote.reference.id,
                                           msisdn: line.msisdn,
                                           status: status))
        }

        guard let reference = firstReference else { return }
        // Le lot n'a pas de statut propre : celui du parent se **dérive** des
        // lignes (`TopUpOrder.aggregate`). La référence portée ici est celle de
        // la première ligne, pour que la relecture ait par où commencer.
        phase = .result(TopUpOrder(reference: reference, results: results))
    }

    /// L'état de la recharge soumise, lu au serveur.
    ///
    /// Illisible ⇒ `.uncertain` avec la référence : la soumission a bien eu
    /// lieu, c'est son issue qu'on ignore. Un échec affiché ici inviterait à
    /// recharger une ligne peut-être déjà créditée.
    private func read(_ reference: FinancialReference) async {
        switch await ordering.requery(reference) {
        case .success(let order): phase = .result(order)
        case .failure:            phase = .uncertain(reference)
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

    /// Le numéro à recharger.
    ///
    /// **Une seule question par écran.** La version précédente empilait un
    /// champ, un bouton enfermé dans une carte blanche et une note sous le
    /// bouton : la note expliquait le champ, mais se lisait après avoir validé.
    /// Ici la question est en tête, l'explication la suit immédiatement, et le
    /// bouton reste en pied avec le clavier.
    private var numberEntry: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Text(FinanceStrings.topUpWhichNumber)
                        .font(.system(size: 26, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    HStack(spacing: 10) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 22)

                        TextField("+257…", text: $msisdn)
                            .keyboardType(.phonePad)
                            .font(.system(size: 19, weight: .medium))
                            .accessibilityLabel(FinanceStrings.topUpNumber)

                        if !msisdn.isEmpty {
                            Button { msisdn = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColors.subtitleGray.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(FinanceStrings.close)
                        }
                    }
                    .padding(14)
                    .background(AppColors.cardBackground,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)

                    // Le numéro du fil, proposé plutôt qu'imposé : on recharge
                    // souvent la ligne de quelqu'un d'autre depuis sa
                    // conversation, mais pas toujours.
                    if let suggestedNumber, !suggestedNumber.isEmpty, msisdn != suggestedNumber {
                        Button {
                            msisdn = suggestedNumber
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(FinanceStrings.topUpUsePeerNumber(suggestedNumber))
                                    .font(.system(size: 14, weight: .medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }

                    // Ajouter un destinataire : le même forfait part sur
                    // plusieurs lignes, chacune avec sa propre opération.
                    if msisdn.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 {
                        Button {
                            addNumber()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(FinanceStrings.topUpAddNumber)
                                    .font(.system(size: 14, weight: .medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }

                    if !numbers.isEmpty { recipientChips }

                    FinanceInfoCard(
                        symbol: "antenna.radiowaves.left.and.right",
                        title: FinanceStrings.topUpOperatorTitle,
                        points: [
                            FinanceStrings.topUpOperatorNote,
                            FinanceStrings.topUpPortedNote
                        ]
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            CustomButton(title: FinanceStrings.sendContinue,
                         isDisabled: allNumbers.isEmpty) {
                Task { await loadCatalog() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
    }

    /// Les forfaits, groupés par nature.
    ///
    /// Une liste plate mêlait crédit d'appel et forfaits data : ce sont deux
    /// achats différents, et le prix seul ne les distingue pas. Les grouper
    /// laisse choisir *ce qu'on achète* avant *combien*.
    private var productList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    lineHeader

                    // Le serveur ne nomme pas toujours la nature d'un forfait :
                    // il range crédit d'appel et data sous une même catégorie.
                    // Un seul groupe ⇒ pas d'intitulé, plutôt qu'un intitulé
                    // qui prétendrait distinguer ce qui ne l'est pas.
                    if grouped.count <= 1 {
                        productGrid(products)
                    } else {
                        ForEach(Self.kindOrder.filter { grouped[$0] != nil }, id: \.self) { kind in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(FinanceStrings.topUpKind(kind.rawValue))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.subtitleGray)
                                    .padding(.horizontal, 16)

                                productGrid(grouped[kind] ?? [])
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }

            CustomButton(title: FinanceStrings.sendContinue,
                         isDisabled: selected == nil) {
                phase = .reviewing
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
    }

    /// Retient la saisie en cours et vide le champ pour la suivante.
    private func addNumber() {
        let pending = msisdn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending.count >= 6, !numbers.contains(pending) else { return }
        numbers.append(pending)
        msisdn = ""
    }

    /// Les destinataires retenus, chacun retirable.
    ///
    /// Un numéro de trop se retire ici : s'en apercevoir à la confirmation,
    /// quand les devis sont déjà demandés, obligerait à tout recommencer.
    private var recipientChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FinanceStrings.topUpRecipients(numbers.count))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.subtitleGray)

            ForEach(numbers, id: \.self) { number in
                HStack(spacing: 10) {
                    Image(systemName: "simcard.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.primary)
                    Text(number).font(.system(size: 15, weight: .medium))
                    Spacer(minLength: 0)
                    Button {
                        numbers.removeAll { $0 == number }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.subtitleGray.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(FinanceStrings.close)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.cardBackground,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
    }

    /// La ligne rechargée, rappelée en tête du catalogue.
    ///
    /// Sans elle, on choisit un forfait sans plus voir quel numéro le recevra —
    /// et une recharge part sur un numéro, pas sur un nom.
    private var lineHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.primary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "simcard.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.primary)
            }

            VStack(alignment: .leading, spacing: 1) {
                // Plusieurs destinataires : leur nombre, pas le premier seul —
                // choisir un forfait en croyant ne recharger qu'une ligne est
                // exactement ce qu'il faut éviter.
                Text(allNumbers.count > 1
                     ? FinanceStrings.topUpRecipients(allNumbers.count)
                     : (allNumbers.first ?? msisdn))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                if let operatorName = products.first?.operatorName {
                    Text(operatorName)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.subtitleGray)
                }
            }

            Spacer(minLength: 8)

            Button {
                phase = .composing
            } label: {
                Text(FinanceStrings.recipientChange)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    /// La grille des forfaits, deux par rangée.
    private func productGrid(_ list: [TopUpProduct]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10),
                      GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(list) { product in
                TopUpProductTile(product: product, isSelected: selected == product) {
                    selected = product
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Ordre d'affichage des natures — du plus courant au plus rare.
    /// `.unspecified` n'y figure pas : il ne se groupe pas (voir `productList`).
    private static let kindOrder: [TopUpKind] = [.airtime, .data, .bundle, .voice, .sms, .roaming]

    private var grouped: [TopUpKind: [TopUpProduct]] {
        Dictionary(grouping: products, by: \.kind)
    }

    /// Le récapitulatif de la recharge.
    ///
    /// Le montant en tête et la ligne rechargée juste dessous : ce sont les
    /// deux choses qu'on relit avant de commander, et une recharge partie sur
    /// le mauvais numéro ne se rattrape pas.
    private var review: some View {
        VStack(spacing: 0) {
            FinanceReviewSummary(
                title: FinanceStrings.flowReview,
                amount: selected.map { AmountEntry.format($0.amount, $0.currency) },
                amountCaption: allNumbers.count > 1
                    ? FinanceStrings.topUpRecipients(allNumbers.count)
                    : selected.map { FinanceStrings.topUpFor(allNumbers.first ?? msisdn, $0.operatorName) },
                rows: reviewRows
            ) {
                Text(FinanceStrings.topUpOperatorNote)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
            }

            CustomButton(title: FinanceStrings.topUpOrder) {
                Task { await placeOrder() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
    }

    /// Le devis du serveur : frais et total tels qu'il les rend, et sa
    /// validité. Le récapitulatif précédent montrait le prix du produit ; seul
    /// le devis dit ce qui sera débité.
    private func quoteReview(_ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) {
                    phase = .reviewing
                    Task { await placeOrder() }
                }
                FinanceReviewSummary(
                    // « Récapitulatif », comme l'étape précédente : le titre
                    // partagé des devis dit « Prêt à envoyer ? », ce qu'une
                    // recharge n'est pas.
                    title: FinanceStrings.flowReview,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: selected.map {
                        FinanceStrings.topUpFor(allNumbers.first ?? msisdn, $0.operatorName)
                    },
                    rows: Self.quoteRows(quote)
                ) {
                    Text(FinanceStrings.topUpOperatorNote)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.topUpOrder,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirm(quote) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    /// Le lot à confirmer : une ligne par destinataire, et la somme.
    ///
    /// Le total est **la somme des devis rendus**, pas le prix du forfait
    /// multiplié par le nombre de lignes : le serveur facture chaque ligne, et
    /// rien ne garantit que les frais soient les mêmes pour toutes.
    ///
    /// La validité affichée est celle qui expire **la première** : confirmer un
    /// lot dont une ligne est déjà périmée ferait partir les autres et échouer
    /// celle-là, sans que rien ne l'ait annoncé.
    private func batchReview(_ lines: [TopUpQuotedLine]) -> some View {
        QuoteValidityReader(expiresAt: lines.map(\.quote.expiresAt).min() ?? Date()) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) {
                    phase = .reviewing
                    Task { await placeOrder() }
                }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReview,
                    amount: Self.batchTotal(lines),
                    amountCaption: FinanceStrings.topUpRecipients(lines.count),
                    rows: lines.map { line in
                        .init(line.msisdn,
                              AmountEntry.format(line.quote.totalAmount ?? line.quote.amount,
                                                 line.quote.totalCurrency ?? line.quote.currency))
                    }
                ) {
                    Text(FinanceStrings.topUpBatchNote)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.topUpOrder,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirmBatch(lines) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    /// La somme du lot. Devises mêlées ⇒ pas de total : additionner des devises
    /// différentes produirait un nombre qui ne veut rien dire.
    private static func batchTotal(_ lines: [TopUpQuotedLine]) -> String? {
        let currencies = Set(lines.map { $0.quote.totalCurrency ?? $0.quote.currency })
        guard let currency = currencies.first, currencies.count == 1 else { return nil }
        let total = lines.reduce(Decimal(0)) { $0 + ($1.quote.totalAmount ?? $1.quote.amount) }
        return AmountEntry.format(total, currency)
    }

    private static func quoteRows(_ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = [
            .init(FinanceStrings.amount, AmountEntry.format(quote.amount, quote.currency))
        ]
        if let fee = quote.feeAmount {
            rows.append(.init(FinanceStrings.fees,
                              AmountEntry.format(fee, quote.feeCurrency ?? quote.currency)))
        }
        if let total = quote.totalAmount {
            rows.append(.init(FinanceStrings.total,
                              AmountEntry.format(total, quote.totalCurrency ?? quote.currency),
                              isProminent: true))
        }
        return rows
    }

    private var reviewRows: [FinanceReviewSummary<Text>.Row] {
        guard let product = selected else { return [] }
        return [
            // Tous les numéros, pas le premier : c'est la ligne qu'on relit
            // avant d'engager, et une recharge partie sur le mauvais numéro ne
            // se rattrape pas.
            .init(FinanceStrings.topUpNumber, allNumbers.joined(separator: ", ")),
            .init(FinanceStrings.recipientOperator, product.operatorName),
            .init(FinanceStrings.topUpKind(product.kind.rawValue),
                  FinanceLocalization.string(product.labelKey, fallback: product.labelKey)),
            // Le total répété en gras : c'est la ligne qui engage, et le
            // montant du haut est une mise en avant, pas une ligne de compte.
            .init(FinanceStrings.total, AmountEntry.format(product.amount, product.currency), isProminent: true)
        ]
    }

    /// Formatage **partagé avec la tuile du catalogue**.
    ///
    /// Le récapitulatif interpolait `\(product.amount)` directement : la grille
    /// affichait « 1 000 » et le récapitulatif « 1000 » pour le même forfait.
    /// Deux écritures d'un même montant dans un même parcours font douter du
    /// montant.

    /// Relit l'état — **ligne par ligne** quand il y en a plusieurs.
    ///
    /// Chaque destinataire est un FCO distinct : une seule relecture sur la
    /// référence du parent ne rendrait l'état que du premier, et effacerait les
    /// autres du compte rendu. Une ligne illisible garde l'état qu'on lui
    /// connaissait plutôt que de disparaître.
    private func refresh(_ order: TopUpOrder) async {
        guard case .result = phase else { return }
        phase = .ordering

        guard order.results.count > 1 else {
            switch await ordering.requery(order.reference) {
            case .success(let fresh): phase = .result(fresh)
            case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
            }
            return
        }

        var refreshed: [TopUpLineResult] = []
        for line in order.results {
            let reference = FinancialReference(type: order.reference.type, id: line.id,
                                               version: 0, correlationID: CorrelationId())
            switch await ordering.requery(reference) {
            case .success(let fresh):
                // Le serveur rend une ligne : on garde son statut, et le numéro
                // déjà affiché s'il ne le renvoie pas masqué.
                let updated = fresh.results.first
                refreshed.append(TopUpLineResult(
                    id: line.id,
                    msisdn: updated?.msisdn.isEmpty == false ? updated!.msisdn : line.msisdn,
                    status: updated?.status ?? line.status,
                    failureReasonKey: updated?.failureReasonKey ?? line.failureReasonKey))
            case .failure:
                refreshed.append(line)
            }
        }
        phase = .result(TopUpOrder(reference: order.reference, results: refreshed))
    }

    /// Le compte rendu, ligne par ligne.
    private func resultView(_ order: TopUpOrder) -> some View {
        Form {
            Section {
                aggregateBanner(order.aggregate)
            }

            Section {
                ForEach(order.results) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.msisdn).font(.body)
                            if let reason = line.failureReasonKey {
                                Text(localized(reason))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        lineStatus(line.status)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            // The existing contract provides requery, not a failed-line retry.
            // Never recreate the entire order from a follow-up button.
            Section {
                    Button {
                        Task { await refresh(order) }
                    } label: {
                        Text(FinanceStrings.flowCheckStatus).frame(maxWidth: .infinity)
                    }
            }
        }
    }

    @ViewBuilder
    private func aggregateBanner(_ aggregate: TopUpOrder.Aggregate) -> some View {
        switch aggregate {
        case .allSucceeded:
            Label(FinanceStrings.topUpAllSucceeded, systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppColors.statusSuccess)
        case .allFailed:
            Label(FinanceStrings.topUpAllFailed, systemImage: "xmark.circle.fill")
                .foregroundStyle(AppColors.statusDanger)
        case .partial(let ok, let ko):
            // Ni vert ni rouge : l'utilisateur a été débité pour une partie.
            Label(FinanceStrings.topUpPartial(ok, ko), systemImage: "circle.lefthalf.filled")
                .foregroundStyle(AppColors.statusWarning)
        case .inFlight:
            Label(FinanceStrings.sendSubmitting, systemImage: "clock")
                .foregroundStyle(AppColors.statusWarning)
        case .undetermined:
            // L'ignorance l'emporte : pas de moyenne rassurante.
            Label(FinanceStrings.topUpUndetermined, systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func lineStatus(_ status: PaymentStatus) -> some View {
        switch status {
        case .completed, .confirmed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.statusSuccess)
        case .failed, .expired, .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.statusDanger)
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        default:
            Image(systemName: "clock").foregroundStyle(AppColors.statusWarning)
        }
    }

    private func localized(_ key: String) -> String {
        // Résolution par TranslationKit ; le repli n'est plus qu'un
        // dernier recours. Sans cela, une clé de protocole s'affichait
        // telle quelle à l'utilisateur.
        FinanceLocalization.string(key, fallback: key.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " "))
    }
}

// MARK: - Tuile de forfait

/// Un forfait, en tuile sélectionnable.
///
/// Le **montant domine** et l'intitulé le suit : à l'achat d'une recharge, la
/// question est « combien je mets », et le nom commercial du forfait ne la
/// départage pas. La sélection se marque par le liseré et la teinte du fond,
/// pas seulement par une coche — une coche seule se cherche sur une grille.
private struct TopUpProductTile: View {

    let product: TopUpProduct
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(AmountEntry.format(product.amount, product.currency))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(AppColors.primary)
                    }
                }

                Text(FinanceLocalization.string(product.labelKey, fallback: product.labelKey))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AppColors.primary.opacity(0.08) : AppColors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? AppColors.primary : AppColors.separator.opacity(0.45),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

}
