//
//  PaymentLinkView.swift
//  FeatureChat
//
//  Liens de paiement — Bloc 6, chapitre 46.2.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Ouvre un lien de paiement reçu dans une conversation.
///
/// **Le lien n'est jamais lu par l'écran.** Il est envoyé au backend, qui seul
/// sait qui est le bénéficiaire et combien il réclame. Tout ce qu'un lien
/// affirme de lui-même est falsifiable, puisqu'un lien se recopie.
struct PaymentLinkView: View {

    let token: String
    /// Le lien vient d'en dehors de l'application — SMS, presse-papiers, site.
    let isExternal: Bool
    let links: any PaymentLinkResolving
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .resolving
    @State private var amountText = ""
    /// Nonce lié à cette résolution : empêche qu'une réponse capturée serve
    /// à une autre tentative.
    @State private var nonce = UUID().uuidString

    private enum Phase {
        case resolving
        case resolved(ResolvedPaymentLink)
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
                case .resolving: FinanceProgress(label: FinanceStrings.linkResolving)
                case .resolved(let link): detail(link)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.linkTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await resolve() }
    }

    private func resolve() async {
        phase = .resolving
        switch await links.resolve(token: token, nonce: nonce) {
        case .success(let link): phase = .resolved(link)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func detail(_ link: ResolvedPaymentLink) -> some View {
        Form {
            // L'origine extérieure est dite **en premier**. Un lien reçu par
            // SMS n'a pas la même présomption qu'un lien émis dans le fil, et
            // l'hameçonnage par lien de paiement vit de cette confusion.
            if link.isExternalOrigin || isExternal {
                Section {
                    Label(FinanceStrings.linkExternalWarning, systemImage: "exclamationmark.shield")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section(FinanceStrings.linkPayee) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 30)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(link.payee.displayName).font(.subheadline.weight(.medium))
                        if link.payee.verification.showsTrustBadge {
                            Label(FinanceStrings.merchantVerified, systemImage: "checkmark.seal.fill")
                                .font(.caption2).foregroundStyle(.tint)
                        }
                        if link.payee.verification.warrantsWarning {
                            Label(FinanceStrings.merchantWarning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(AppColors.statusWarning)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }

            amountSection(link)

            if let expiresAt = link.expiresAt {
                Section {
                    Label(
                        String(format: FinanceStrings.linkExpiresAt,
                               expiresAt.formatted(date: .abbreviated, time: .shortened)),
                        systemImage: "clock"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }

            if link.usage == .singleUse {
                Section {
                    Text(FinanceStrings.linkSingleUse).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Label(FinanceStrings.flowExecutionUnavailable, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            } footer: {
                if !link.isUsable() {
                    Text(link.unavailableReasonKey ?? FinanceStrings.linkUnusable)
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                } else if !link.amount.isPayableAsIs {
                    Text(FinanceStrings.linkIndicativeOnly).font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }
        }
    }

    @ViewBuilder
    private func amountSection(_ link: ResolvedPaymentLink) -> some View {
        Section(FinanceStrings.amount) {
            switch link.amount {
            case .fixed(let money):
                Text("\(money.majorUnitsForDisplay) \(money.currency.code)")
                    .font(.title3.weight(.semibold)).monospacedDigit()

            case .open(let minimum, let maximum):
                HStack {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(minimum?.currency.code ?? maximum?.currency.code ?? "")
                        .foregroundStyle(.secondary)
                }
                // Les bornes viennent du lien résolu, pas d'une règle locale.
                if let minimum {
                    Text(String(format: FinanceStrings.linkMinimum,
                                "\(minimum.majorUnitsForDisplay) \(minimum.currency.code)"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let maximum {
                    Text(String(format: FinanceStrings.linkMaximum,
                                "\(maximum.majorUnitsForDisplay) \(maximum.currency.code)"))
                        .font(.caption2).foregroundStyle(.secondary)
                }

            // Un montant indicatif ne devient jamais ferme par le seul fait
            // d'être affiché. Il est montré barré de son avertissement.
            case .indicative(let money):
                VStack(alignment: .leading, spacing: 4) {
                    Text("~ \(money.majorUnitsForDisplay) \(money.currency.code)")
                        .font(.title3).monospacedDigit().foregroundStyle(.secondary)
                    Text(FinanceStrings.linkIndicativeOnly)
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }
        }
    }
}

/// Les liens que l'utilisateur a émis, et leur révocation.
///
/// Sans cet écran, un lien partagé dans un groupe reste payable jusqu'à son
/// expiration — y compris après que son auteur a compris son erreur.
struct IssuedPaymentLinksView: View {

    let links: any PaymentLinkResolving
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var revoking: IssuedPaymentLink?

    private enum Phase {
        case loading
        case empty
        case loaded([IssuedPaymentLink])
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
                case .loading: FinanceProgress(label: FinanceStrings.linkLoadingIssued)
                case .empty:   FinanceMessage(icon: "link", text: FinanceStrings.linkNoIssued)
                case .working: FinanceProgress(label: FinanceStrings.linkRevoking)
                case .loaded(let issued): list(issued)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.linkIssuedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .confirmationDialog(
                FinanceStrings.linkRevokeConfirmTitle,
                isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                titleVisibility: .visible
            ) {
                Button(FinanceStrings.linkRevoke, role: .destructive) {
                    if let link = revoking { Task { await revoke(link) } }
                }
                Button(FinanceStrings.cancel, role: .cancel) { revoking = nil }
            } message: {
                Text(FinanceStrings.linkRevokeConfirmDetail)
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await links.issuedLinks() {
        case .success(let issued):
            phase = issued.isEmpty ? .empty : .loaded(issued)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func revoke(_ link: IssuedPaymentLink) async {
        revoking = nil
        phase = .working
        let submissionKey261 = await operationKeys.key(for: FinanceOperationKeys.scope("link.revoke", link.id), deviceID: deviceID)
        switch await links.revoke(linkID: link.id,
                                  idempotency: submissionKey261) {
        case .success: await load()
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func list(_ issued: [IssuedPaymentLink]) -> some View {
        List(issued) { link in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    PaymentLinkStateBadge(state: link.state)
                    Spacer()
                    // Le nombre de paiements vient du backend : le client ne
                    // sait pas si quelqu'un vient de consommer le lien.
                    if link.paymentCount > 0 {
                        Text(String(format: FinanceStrings.linkPaymentCount, link.paymentCount))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Text(link.url.absoluteString)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)

                Text(link.issuedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)

                if link.isRevocable() {
                    Button(FinanceStrings.linkRevoke, role: .destructive) { revoking = link }
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }
}

struct PaymentLinkStateBadge: View {
    let state: PaymentLinkState

    var body: some View {
        Label(label, systemImage: icon).font(.caption).foregroundStyle(tint)
    }

    private var label: String {
        switch state {
        case .active:   return FinanceStrings.linkStateActive
        case .consumed: return FinanceStrings.linkStateConsumed
        case .revoked:  return FinanceStrings.linkStateRevoked
        case .expired:  return FinanceStrings.linkStateExpired
        case .unknown:  return FinanceStrings.linkStateUnknown
        }
    }

    private var icon: String {
        switch state {
        case .active:   return "link"
        case .consumed: return "checkmark.circle"
        case .revoked:  return "xmark.circle"
        case .expired:  return "clock.badge.xmark"
        case .unknown:  return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .active:  return .primary
        case .revoked: return AppColors.statusWarning
        default:       return .secondary
        }
    }
}
