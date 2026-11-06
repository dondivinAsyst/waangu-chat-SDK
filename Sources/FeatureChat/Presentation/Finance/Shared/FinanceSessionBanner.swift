//
//  FinanceSessionBanner.swift
//  FeatureChat
//
//  Pourquoi les paiements sont indisponibles — Phase 1, affichage.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Bandeau de session de l'accueil Paiements.
///
/// Ne s'affiche que lorsque Chat Core refuse l'écriture, et dit pourquoi. Les
/// tuiles, elles, restent pilotées par le Hub : ce bandeau explique, il
/// n'ouvre ni ne ferme rien.
struct FinanceSessionBanner: View {

    /// Le modèle appartient à l'accueil : c'est lui qui décide aussi si l'écran
    /// entier cède la place à l'indisponibilité, et deux modèles distincts
    /// liraient la session deux fois pour répondre à la même question.
    @ObservedObject var viewModel: FinanceSessionViewModel

    var body: some View {
        Group {
            if let restriction = viewModel.restriction {
                FinanceInfoCard(
                    symbol: Self.symbol(for: restriction),
                    title: FinanceStrings.sessionRestrictionTitle(restriction),
                    points: [FinanceStrings.sessionRestrictionDetail(restriction)]
                )
                .padding(.horizontal, 16)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func symbol(for restriction: FinanceSessionViewModel.Restriction) -> String {
        switch restriction {
        case .countryClosed:    return "globe"
        case .serviceSuspended: return "pause.circle"
        case .readDenied:       return "eye.slash"
        case .safeMode:         return "eye"
        case .sessionLocked:    return "lock.rotation"
        case .paymentsDisabled: return "nosign"
        case .unavailable:      return "wifi.exclamationmark"
        }
    }
}
