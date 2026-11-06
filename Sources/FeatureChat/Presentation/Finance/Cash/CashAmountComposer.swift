//
//  CashAmountComposer.swift
//  FeatureChat
//
//  Saisie d'un montant en espèces — dépôt et retrait.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Le canal, le montant, et rien d'autre.
///
/// **Un seul composeur pour le dépôt et le retrait.** Les deux écrans posaient
/// exactement les mêmes deux questions dans deux `Form` distincts, à un mot
/// près : deux copies qui divergeront à la première retouche, sur un parcours
/// où le montant compte.
///
/// Le canal reste **visible même quand il n'y en a qu'un**. Les versions
/// précédentes masquaient le sélecteur dans ce cas : on déposait sans savoir
/// où, et « Agent » n'est pas la même chose que « Banque » quand il faut se
/// déplacer.
struct CashAmountComposer<Channel: Hashable & Identifiable>: View {

    let title: String
    let channels: [Channel]
    @Binding var selected: Channel?
    let currency: String

    /// Libellé lisible d'un canal. Fourni par l'appelant : `CashInChannel` et
    /// `CashOutChannel` sont deux types, et leur traduction n'est pas la même.
    let describe: (Channel) -> String

    /// Pictogramme du canal.
    let symbol: (Channel) -> String

    @Binding var amountText: String
    var footnote: String?
    let onContinue: () -> Void

    @FocusState private var keypadFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 14) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        AmountDisplay(digits: amountText,
                                      currencyCode: currency,
                                      fractionDigits: AmountEntry.fractionDigits(for: currency))
                            .padding(.top, 6)

                        Spacer(minLength: 12)

                        channelRow

                        if let footnote {
                            Text(footnote)
                                .font(.footnote)
                                .foregroundStyle(AppColors.subtitleGray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.bottom, 12)
                    .frame(minHeight: viewport.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: 12) {
                CustomButton(title: FinanceStrings.sendContinue,
                             isDisabled: selected == nil || AmountEntry.isBlank(amountText),
                             action: onContinue)

                AmountKeypad(allowsDecimal: AmountEntry.fractionDigits(for: currency) > 0) { key in
                    AmountEntry.apply(key, to: &amountText,
                                      fractionDigits: AmountEntry.fractionDigits(for: currency))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
    }

    private var channelRow: some View {
        FundingSourcePicker(
            label: FinanceStrings.cashChannel,
            sources: channels,
            selection: $selected
        ) { channel in
            FundingSourcePicker.Descriptor(
                title: describe(channel),
                subtitle: nil,
                symbol: symbol(channel),
                isUsable: true
            )
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Identité de présentation

/// `FundingSourcePicker` exige `Identifiable` ; la valeur brute suffit, elle est
/// unique par canal. Déclaré ici plutôt que dans CoreKit : c'est un besoin
/// d'affichage, et le contrat n'a pas à porter une identité qu'il n'utilise pas.
extension CashInChannel: Identifiable {
    public var id: String { rawValue }
}

extension CashOutChannel: Identifiable {
    public var id: String { rawValue }
}
