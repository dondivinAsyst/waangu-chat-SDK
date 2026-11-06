//
//  CashJourneyCard.swift
//  FeatureChat
//
//  Espèces — le parcours de terrain, montré comme un parcours (§6).
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Les étapes d'un dépôt ou d'un retrait chez un agent, et où l'on en est.
///
/// **Le découpage est le message.** Le §6 tient en une phrase — « physique
/// confirmé ≠ argent au ledger » — et une phrase se lit une fois puis
/// s'oublie. Un parcours en trois temps, dont le dernier reste visiblement à
/// venir, se comprend sans être lu : la remise est faite, le crédit ne l'est
/// pas, et rien ne le laisse croire.
///
/// Les écrans montraient auparavant un champ isolé en haut d'une page vide,
/// puis une ligne de texte. Ni l'opération, ni son montant, ni ce qui restait à
/// faire n'y figuraient.
struct CashJourneyCard<Content: View>: View {

    /// Ce qu'on est en train de faire — le titre de la carte.
    let title: String
    /// Le montant en jeu, déjà formaté. Vide ⇒ pas de ligne de montant.
    var amount: String = ""
    let caption: String
    let symbol: String
    let steps: [CashJourneyStep]
    /// L'animation d'état, quand l'étape courante en mérite une.
    var animation: FinanceStatusAnimationKind?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 14) {
            header
            if !steps.isEmpty { tracker }
            content()
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.primary.opacity(0.10))
                    .frame(width: 64, height: 64)
                if let animation {
                    FinanceStatusAnimation(animation)
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                if !amount.isEmpty {
                    Text(amount)
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(AppColors.primary)
                }
                if !caption.isEmpty {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Le parcours

    /// Trois temps, reliés par un trait : ce qui est fait, ce qu'on fait, ce
    /// qui reste. L'étape à venir garde sa place en gris — l'escamoter ferait
    /// croire le parcours terminé une étape trop tôt.
    private var tracker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        marker(step.state)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.state == .done ? AppColors.primary
                                                          : AppColors.separator.opacity(0.6))
                                .frame(width: 1.5)
                                .frame(minHeight: step.detail.isEmpty ? 18 : 34)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 14, weight: step.state == .current ? .semibold : .regular))
                            .foregroundStyle(step.state == .upcoming ? AppColors.subtitleGray
                                                                     : AppColors.textPrimary)
                        if !step.detail.isEmpty {
                            Text(step.detail)
                                .font(.footnote)
                                .foregroundStyle(AppColors.subtitleGray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, index < steps.count - 1 ? 10 : 0)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppColors.separator.opacity(0.45), lineWidth: 0.5))
    }

    @ViewBuilder
    private func marker(_ state: CashJourneyStep.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(AppColors.primary)
        case .current:
            Circle()
                .stroke(AppColors.primary, lineWidth: 2)
                .frame(width: 15, height: 15)
                .overlay(Circle().fill(AppColors.primary).frame(width: 6, height: 6))
        case .upcoming:
            Circle()
                .stroke(AppColors.separator, lineWidth: 1.5)
                .frame(width: 15, height: 15)
        }
    }
}

/// Une étape du parcours.
///
/// Hors du type générique : les écrans la construisent avant de savoir ce que
/// contiendra la carte, et `CashJourneyCard<EmptyView>.Step` les obligeait à
/// nommer un contenu qu'ils n'ont pas encore.
struct CashJourneyStep: Identifiable {
    let id: Int
    let title: String
    /// Ce que cette étape signifie **et ne signifie pas**. Vide ⇒ rien à dire.
    var detail: String = ""
    let state: State

    enum State { case done, current, upcoming }
}
