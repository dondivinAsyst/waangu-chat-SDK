//
//  PaymentLinkIssuedSheet.swift
//  FeatureChat
//
//  Phase 4 — le lien de paiement d'une demande, tout juste émis.
//

import SwiftUI
import UIKit
import WaanguCoreKit
import WaanguSharedUI

/// Le lien émis : quand il expire, ce qu'il fait — et surtout ce qu'il ne fait
/// pas — puis le geste de le copier.
///
/// **Le lien ne paie rien** (`executable=false`) : il désigne la demande, que
/// la personne paie ensuite par le parcours normal (devis, confirmation).
///
/// Le contrat rend un `token` et un `nonce` : l'adresse partagée est celle de
/// l'app, `waangu://chat/pay-link?token=…&nonce=…` (`PaymentLinkURL`), que
/// `DeepLinkParser` ouvre sur `PaymentLinkOpenView`.
struct PaymentLinkIssuedSheet: View {

    let link: MoneyRequestLink
    let onDone: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            // Le même lien, à scanner : la personne en face ouvre la demande
            // sans qu'on ait à lui envoyer quoi que ce soit.
            if let url, link.isUsable(), let code = QRCodeImageRenderer.render(url.absoluteString) {
                Image(uiImage: code)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 148, height: 148)
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                Text(FinanceStrings.requestLinkTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                if let expiresAt = link.expiresAt {
                    Text(FinanceStrings.requestLinkExpires(
                        expiresAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.subheadline)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                Text(FinanceStrings.requestLinkDetail)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if let url, link.isUsable() {
                    ShareLink(item: url) {
                        Label(FinanceStrings.requestLinkShare, systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    CustomButton(title: copied ? FinanceStrings.requestLinkCopied : FinanceStrings.requestLinkCopy,
                                 icon: copied ? "checkmark" : "doc.on.doc", style: .ghost) {
                        UIPasteboard.general.url = url
                        copied = true
                    }
                }
                CustomButton(title: FinanceStrings.close, style: .ghost, action: onDone)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.walletCanvas)
        .presentationDetents([.medium])
    }

    private var url: URL? { PaymentLinkURL.make(token: link.token, nonce: link.nonce) }
}
