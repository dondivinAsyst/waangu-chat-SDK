//
//  Haptic.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  Haptics.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 31.01.2025.
//

import UIKit

public enum Haptic {
   public static func impact(_ style: Style) {
        switch style {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    public enum Style {
        case light
        case medium
        case heavy
        case error
        case success
        case warning
    }
}
