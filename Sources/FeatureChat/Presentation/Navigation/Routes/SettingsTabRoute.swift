//
//  SettingsTabRoute.swift
//  FeatureChat
//
//  Settings tab navigation routes
//

import SwiftUI
import WaanguNavigationKit

public enum SettingsTabRoute: StackRoute {
    case root
    case profile
    case privacy
    case notifications
    case account

    /// Surface financière, hors conversation.
    ///
    /// Le hub vivait derrière la feuille d'actions d'un fil : sans conversation
    /// ouverte, aucune fonction financière n'était atteignable.
    case finance

    /// Mon QR : se faire ajouter, écrire ou payer, et scanner celui des autres.
    case myQRCode
}
