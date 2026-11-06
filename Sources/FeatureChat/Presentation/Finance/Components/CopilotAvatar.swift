//
//  CopilotAvatar.swift
//  FeatureChat
//
//  L'avatar de Waangu Copilot — ligne de la liste, en-tête de sa conversation.
//

import SwiftUI
import WaanguSharedUI

/// Les étincelles sur la couleur primaire, à la taille d'un avatar de ligne.
///
/// Blanc **fixe** : `AppColors.white` vire au quasi-noir en mode sombre, et
/// disparaîtrait sur la pastille.
struct CopilotAvatar: View {
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(AppColors.primary, in: Circle())
            .accessibilityHidden(true)
    }
}
