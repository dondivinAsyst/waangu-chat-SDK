//
//  PaymentCardView.swift
//  FeatureChat
//
//  Carte de paiement — tâche 6.5.

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Rend un paiement dans le fil.
///
/// **Miroir strict.** Aucune valeur n'est calculée ici : le montant, les frais et
/// le statut viennent du backend. Le total affiché passe par
/// `FinancialCardPayload.totalAmount`, qui additionne ce que le backend a rendu —
/// il n'applique aucune règle de frais locale, qui divergerait du ledger dès le
/// prochain changement de barème.
struct PaymentCardView: View {

    let payload: FinancialCardPayload
    /// `nil` hors du fil (détail, aperçu) : la carte garde alors son titre neutre.
    @Environment(\.financeCardDirection) private var direction

    var body: some View {
        FinancialCardChrome(payload: payload, title: title, symbol: directionSymbol) {
            VStack(alignment: .leading, spacing: 6) {

                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.formattedAmount)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        // Un contenu non authentifié est barré plutôt que masqué :
                        // le masquer laisserait croire à un incident d'affichage.
                        .strikethrough(payload.isRepudiated)

                    if let fee = payload.feeAmount, fee > 0 {
                        Text(String(format: FinanceStrings.cardIncludingFee, feeLabel(fee)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let name = counterpartyLine {
                    FinanceHairline()
                    name
                }

                if let note = payload.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    /// Which way the money went, shown as a small badge before the title.
    private var directionSymbol: String? {
        switch direction {
        case .sent?:     return "arrow.up.right"
        case .received?: return "arrow.down.left"
        case nil:        return nil
        }
    }

    private var title: String {
        switch (payload.reference.type, direction) {
        case (.merchantPayment, _): return "Paiement marchand"
        case (.cashIn, _):          return "Dépôt"
        case (.cashOut, _):         return "Retrait"
        case (.payout, _):          return "Versement"
        case (.remittance, nil):    return "Transfert international"
        case (_, .sent?):           return FinanceStrings.cardMoneySent
        case (_, .received?):       return FinanceStrings.cardMoneyReceived
        default:                    return "Paiement"
        }
    }

    /// Le nom porté par la carte est celui que l'**expéditeur** a saisi : chez
    /// le destinataire, c'est son propre nom. Il n'est donc montré qu'à qui a
    /// envoyé (« À … ») ; à la réception, la conversation dit déjà de qui vient
    /// l'argent.
    private var counterpartyLine: AnyView? {
        guard let name = payload.counterpartyName, !name.isEmpty else { return nil }
        switch direction {
        case .sent?:
            return AnyView(
                HStack(spacing: 4) {
                    Text(FinanceStrings.cardTo).foregroundStyle(.secondary)
                    Text(name).fontWeight(.medium).lineLimit(1)
                }
                .font(.subheadline)
            )
        case .received?:
            return nil
        case nil:
            return AnyView(Text(name).font(.subheadline).foregroundStyle(.secondary))
        }
    }

    /// Libellé des frais, dans **leur** devise.
    ///
    /// Un paiement transfrontalier peut facturer ses frais dans une devise
    /// distincte du montant. Afficher ces frais avec le code devise du montant
    /// n'est pas une approximation de mise en forme : c'est un montant faux
    /// présenté comme exact.
    private func feeLabel(_ fee: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSDecimalNumber(decimal: fee)) ?? "\(fee)"
        return "\(value) \(payload.feeCurrency ?? payload.currency)"
    }
}

// MARK: - Aperçus — Bloc 10, chapitre 79 (Burundi, Rwanda, Canada)

#Preview("Burundi · Rwanda · Canada") {
    PaymentCardCountryPreview()
}

#Preview("Sombre · texte XXL") {
    PaymentCardCountryPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}

private struct PaymentCardCountryPreview: View {

    private static func reference(_ id: String) -> FinancialReference {
        FinancialReference(type: .payment, id: id, version: 3, correlationID: CorrelationId())
    }

    /// Un paiement par pays, chacun dans un état différent : réussite vérifiée,
    /// vérification en cours, échec — les trois lectures qui ne doivent jamais
    /// se confondre.
    private let payloads: [(String, FinancialCardPayload)] = [
        ("fr_BI", FinancialCardPayload(reference: reference("bi"), status: .completed,
                                       amount: 250_000, currency: "BIF",
                                       counterpartyName: "Yohana Niyonzima", verification: .verified)),
        ("rw_RW", FinancialCardPayload(reference: reference("rw"), status: .completed,
                                       amount: 18_500, currency: "RWF", feeAmount: 150, feeCurrency: "RWF",
                                       counterpartyName: "Aline Uwase", verification: .unverified)),
        ("fr_CA", FinancialCardPayload(reference: reference("ca"), status: .failed,
                                       amount: 42.75, currency: "CAD",
                                       counterpartyName: "Marie-Ève Tremblay-Gagnon", verification: .verified)),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(payloads, id: \.1.reference.id) { locale, payload in
                    PaymentCardView(payload: payload)
                        .environment(\.locale, Locale(identifier: locale))
                        .padding(12)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
        .background(AppColors.walletCanvas)
    }
}
