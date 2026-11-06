//
//  MerchantProfileView.swift
//  FeatureChat
//
//  Profil marchand et paiement marchand — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Le profil d'un marchand, et le paiement qu'on lui fait.
///
/// Un marchand n'est pas un contact avec une pastille bleue. L'écran affiche
/// d'abord **qui l'a vérifié**, ensuite seulement ce qu'on peut lui payer :
/// l'ordre inverse invite à payer avant de regarder.
struct MerchantProfileView: View {

    let merchantID: String
    let profiles: any MerchantProfileProviding
    let commerce: any CommerceOrdering
    let conversationID: String?
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var amountText = ""
    @State private var reference = ""
    @State private var showsCatalog = false

    private enum Phase {
        case loading
        case loaded(MerchantProfile)
        /// Le profil a changé pendant la saisie ; il doit être relu.
        case identityChanged(MerchantProfile)
        case revalidating
        case blocked(String)
        case quoting
        case reviewing(MerchantProfile, FinancialQuote)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .revalidating, .quoting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .reviewing: return !amountText.isEmpty || !reference.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing(let profile, _): return { phase = .loaded(profile) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:
                    FinanceProgress(label: FinanceStrings.merchantLoading)
                case .loaded(let profile):
                    detail(profile)
                case .identityChanged(let profile):
                    identityChanged(profile)
                case .revalidating:
                    FinanceProgress(label: FinanceStrings.merchantRevalidating)
                case .blocked(let message):
                    FinanceMessage(icon: "xmark.shield", text: message)
                case .quoting:
                    FinanceProgress(label: FinanceStrings.sendQuoting)
                case .reviewing(let profile, let quote):
                    review(profile, quote)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.merchantTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(isPresented: $showsCatalog) {
                MerchantCatalogView(
                    merchantID: merchantID, commerce: commerce,
                    deviceID: deviceID, onDismiss: { showsCatalog = false }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Chargement

    private func load() async {
        phase = .loading
        switch await profiles.profile(merchantID: merchantID) {
        case .success(let profile): phase = .loaded(profile)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func requestQuote(_ profile: MerchantProfile) async {
        guard let decimal = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              decimal > 0,
              let currency = profile.acceptedCurrencies.first
        else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }

        // **Revalider d'abord.** Le profil a été lu à l'ouverture ; entre-temps
        // le marchand a pu être suspendu ou changer de bénéficiaire. Coter sur
        // la foi d'un profil vieux de deux minutes, c'est coter une identité
        // qui n'existe peut-être plus.
        phase = .revalidating
        let snapshot = profile.snapshot()

        switch await profiles.revalidate(snapshot) {
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
            return
        case .success(let verdict):
            switch verdict {
            case .unchanged:
                break
            case .changed(let fresh):
                // Ni une erreur, ni un feu vert : un profil neuf que
                // l'utilisateur doit revoir avant de payer.
                phase = .identityChanged(fresh)
                return
            case .suspended(let reasonKey):
                phase = .blocked(reasonKey)
                return
            case .revoked(let reasonKey):
                phase = .blocked(reasonKey)
                return
            }
        }

        phase = .quoting
        // L'exposant vient de la devise **telle que le marchand l'accepte**.
        // Il était codé à zéro : sur une devise à deux décimales, 12,50 partait
        // pour 12 unités mineures — un facteur 100 sur un montant réel.
        let money = Money(
            minorUnits: NSDecimalNumber(decimal: decimal).int64Value,
            currency: currency
        )
        let quote = await profiles.quotePayment(
            merchantID: merchantID, amount: money,
            reference: reference.isEmpty ? nil : reference,
            conversationID: conversationID,
            // L'identité épinglée part avec le devis : le backend rejette une
            // cotation demandée sur une identité périmée.
            identity: snapshot
        )
        switch quote {
        case .success(let quote): phase = .reviewing(profile, quote)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func detail(_ profile: MerchantProfile) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    logo(profile)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.actor.displayName).font(.headline)
                        if profile.actor.verification.showsTrustBadge {
                            Label(FinanceStrings.merchantVerified, systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.tint)
                        }
                        // Un statut retiré n'est pas l'absence de badge : c'est
                        // une information, et elle doit se voir.
                        if profile.actor.verification.warrantsWarning {
                            Label(FinanceStrings.merchantWarning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(AppColors.statusWarning)
                        }
                        if let category = profile.categoryKey {
                            Text(category).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if profile.descriptionKey != nil || profile.addressLine != nil || profile.publicContact != nil {
                Section(FinanceStrings.merchantAbout) {
                    if let description = profile.descriptionKey { Text(description).font(.subheadline) }
                    if let address = profile.addressLine {
                        Label(address, systemImage: "mappin.and.ellipse").font(.caption)
                    }
                    if let contact = profile.publicContact {
                        Label(contact, systemImage: "phone").font(.caption).textSelection(.enabled)
                    }
                }
            }

            Section {
                Button(FinanceStrings.merchantBrowseCatalog) { showsCatalog = true }
            }

            if profile.isPayable {
                Section(FinanceStrings.merchantPayTitle) {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(FinanceStrings.amount)
                        Text(profile.acceptedCurrencies.first?.code ?? "").foregroundStyle(.secondary)
                    }
                    TextField(FinanceStrings.merchantReference, text: $reference)
                    CustomButton(title: FinanceStrings.sendContinue) { Task { await requestQuote(profile) } }
                    .disabled(amountText.isEmpty)
                }
            } else {
                Section {
                    Label(
                        profile.unavailableReasonKey ?? FinanceStrings.merchantNotPayable,
                        systemImage: "lock"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let policy = profile.returnPolicyKey {
                Section(FinanceStrings.merchantReturnPolicy) {
                    Text(policy).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Le profil a changé pendant la saisie.
    ///
    /// On ne reprend pas le paiement automatiquement : ce que l'utilisateur a
    /// approuvé n'existe plus, et enchaîner reviendrait à lui faire payer une
    /// identité qu'il n'a jamais vue.
    private func identityChanged(_ profile: MerchantProfile) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40)).foregroundStyle(AppColors.statusWarning)
            Text(FinanceStrings.merchantIdentityChangedTitle).font(.headline)
            Text(FinanceStrings.merchantIdentityChangedDetail)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button(FinanceStrings.merchantReviewProfile) { phase = .loaded(profile) }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.top, 48)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func logo(_ profile: MerchantProfile) -> some View {
        if let url = profile.logoURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: "storefront")
                .font(.system(size: 34)).foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
        }
    }

    private func review(_ profile: MerchantProfile, _ quote: FinancialQuote) -> some View {
        Form {
            Section { Text(profile.actor.displayName).font(.headline) }

            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.amount,
                               value: AmountEntry.format(quote.sourceAmount, quote.sourceCurrency))
                ForEach(quote.fees, id: \.labelKey) { fee in
                    LabeledContent(fee.labelKey, value: AmountEntry.format(fee.amount, fee.currency))
                }
                ForEach(quote.taxes, id: \.labelKey) { tax in
                    LabeledContent(tax.labelKey, value: AmountEntry.format(tax.amount, tax.currency))
                }
                LabeledContent(FinanceStrings.total) {
                    Text(AmountEntry.format(quote.totalDebit, quote.sourceCurrency))
                        .font(.body.weight(.semibold))
                }
            }

            Section {
                Text(FinanceStrings.flowExecutionUnavailable).font(.footnote).foregroundStyle(.secondary)
            }

            // Un devis non exécutable ne s'exécute pas, même si tout le reste
            // s'affiche correctement.
            if !quote.executable {
                Section {
                    Label(FinanceStrings.quoteNotExecutable, systemImage: "xmark.octagon")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }
        }
    }
}
