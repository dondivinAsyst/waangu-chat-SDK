//
//  QuoteValidityReader.swift
//  FeatureChat
//
//  Suit l'expiration d'un devis pendant qu'il est affiché — Bloc 10, chapitre 80.
//

import SwiftUI
import WaanguSharedUI

/// Réévalue la validité d'un devis chaque seconde et la passe au contenu.
///
/// `TimelineView` plutôt qu'un minuteur en `@State` : il suit l'apparition de
/// la vue, s'arrête hors écran, et ne survit pas à la vue qui l'a lancé.
struct QuoteValidityReader<Content: View>: View {

    let expiresAt: Date
    @ViewBuilder let content: (QuoteValidity) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(QuoteValidity.at(context.date, expiresAt: expiresAt))
        }
    }
}

/// Bandeau d'expiration : rien quand le devis est valide, un compte à rebours
/// quand il expire bientôt, une invitation à actualiser une fois expiré.
struct QuoteValidityBanner: View {

    let validity: QuoteValidity
    let onRefresh: () -> Void

    var body: some View {
        switch validity {
        case .valid:
            EmptyView()
        case .expiring(let seconds):
            banner(icon: "hourglass", text: String(format: FinanceStrings.quoteExpiresIn, "\(seconds)"),
                   action: nil)
                // Relu à chaque seconde, VoiceOver le signale sans l'annoncer en boucle.
                .accessibilityAddTraits(.updatesFrequently)
        case .expired:
            banner(icon: "clock.badge.exclamationmark", text: FinanceStrings.quoteExpired,
                   action: onRefresh)
        }
    }

    private func banner(icon: String, text: String, action: (() -> Void)?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.statusWarning)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(FinanceStrings.quoteRefresh, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.statusWarning.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}
