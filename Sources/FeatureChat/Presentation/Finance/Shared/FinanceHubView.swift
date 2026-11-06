//
//  FinanceHubView.swift
//  FeatureChat
//
//  Les états d'indisponibilité de la surface financière.
//
//  L'ancien `FinanceHubView` vivait ici. Il composait sa propre page — solde
//  absent, quatre pastilles, une liste — pendant que les Réglages en
//  composaient une autre, et les deux dessinaient le même produit
//  différemment. Un seul accueil les remplace : `FinanceHomeView`, et
//  `FinanceServicesGridView` pour le reste du catalogue.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

// MARK: - Graphe sans finance

/// Affiché quand le graphe est construit sans surface financière.
///
/// Distinct du catalogue vide, et c'est délibéré : « aucun service disponible »
/// répond à une question de marché, celui-ci répond à une question de
/// configuration. Les confondre enverrait un utilisateur au support pour un
/// défaut d'assemblage.
struct FinanceHubUnavailableView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(FinanceStrings.hubUnavailableTitle)
                .font(.subheadline.weight(.medium))
            Text(FinanceStrings.hubUnavailableDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Backend injoignable

/// Affiché **à la place** de tout l'accueil quand Chat Core ne répond pas.
///
/// Pas un bandeau au-dessus de la page : sans session ni catalogue, la page
/// n'aurait plus que du décor — un solde qu'on ne sait pas relire, des pastilles
/// grisées, un relevé vide. Laisser ce décor visible donne à croire qu'une des
/// commandes finira par répondre. Un seul message, une seule action.
///
/// Distinct de `FinanceHubUnavailableView` : celui-là dit « pas installé »,
/// celui-ci dit « pas joignable maintenant », et la conduite à tenir n'est pas
/// la même.
struct FinanceUnreachableView: View {

    /// Ce que le serveur a répondu, dans ses mots. `nil` ⇒ il n'a rien dit
    /// d'affichable, et l'écran garde sa phrase.
    ///
    /// Un refus nommé ne se remplace pas par « service indisponible » : le
    /// serveur qui refuse `conversationType=SELF` dit exactement ce qui ne va
    /// pas, et le taire fait chercher la panne là où elle n'est pas.
    var detail: String?

    /// Relance la lecture de la session et du catalogue.
    let onRetry: () async -> Void

    var body: some View {
        FinanceNoticeScreen(
            badge: detail == nil ? "wifi.slash" : "exclamationmark.triangle",
            title: FinanceStrings.sessionRestrictionTitle(.unavailable),
            detail: detail ?? FinanceStrings.sessionRestrictionDetail(.unavailable),
            actionTitle: FinanceStrings.sessionRetry,
            action: onRetry
        )
    }
}

// MARK: - Pays non ouvert

/// Affiché **à la place** du Hub quand le pays du compte n'est pas ouvert ou
/// pas localisé (`countryApproved` / `countryLocalized` à `false`, §1.2).
///
/// Sans bouton : réessayer ne change rien à une décision de marché, et un
/// bouton qui ne mène nulle part se lit comme une panne.
struct FinanceCountryClosedView: View {

    /// Relire la session. Un instantané pris avant la reprise disait « pays non
    /// ouvert » sans recours ; le serveur, lui, peut répondre autrement après.
    var onRetry: (() async -> Void)?

    var body: some View {
        FinanceNoticeScreen(
            badge: "globe",
            title: FinanceStrings.sessionRestrictionTitle(.countryClosed),
            detail: FinanceStrings.sessionRestrictionDetail(.countryClosed),
            actionTitle: onRetry == nil ? nil : FinanceStrings.failureRetry,
            action: onRetry
        )
    }
}

// MARK: - Mise en page commune

/// Écran plein d'état financier : le portefeuille, un badge qui dit la cause,
/// un titre, une explication, et au plus une action.
private struct FinanceNoticeScreen: View {

    let badge: String
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var action: (() async -> Void)? = nil

    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Le portefeuille, marqué de la cause : c'est l'accès qui manque,
            // pas le compte. Un cadenas aurait dit « on vous refuse », un
            // triangle « quelque chose est cassé chez vous ».
            ZStack {
                Image(systemName: "wallet.bifold")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(AppColors.primary.opacity(0.55))

                Image(systemName: badge)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.white)
                    .padding(6)
                    .background(AppColors.primary, in: Circle())
                    .offset(x: 34, y: 30)
            }
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 22)

            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.subtitleGray)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            if let actionTitle, let action {
                actionButton(actionTitle, action: action)
                    .padding(.top, 26)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .background(AppColors.walletCanvas)
    }

    /// Un seul bouton, plein, à la couleur de marque : c'est la seule action de
    /// l'écran. L'attente, elle, n'est pas dessinée ici — l'accueil remplace cet
    /// écran par son chargeur dès l'appui, comme au premier chargement.
    private func actionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.white)
                .frame(maxWidth: 260)
                .frame(height: 50)
                .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel(title)
    }
}

// MARK: - Parcours non livré

/// Affiché quand une entrée du catalogue n'a pas encore son parcours.
///
/// Dire explicitement « pas encore disponible » plutôt qu'ouvrir un écran vide :
/// un écran vide se lit comme une panne, et produit un ticket de support pour
/// une fonctionnalité qui n'a simplement pas été construite.
struct FinanceEntryUnavailableView: View {

    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.height(240)])
        .accessibilityElement(children: .combine)
    }
}
