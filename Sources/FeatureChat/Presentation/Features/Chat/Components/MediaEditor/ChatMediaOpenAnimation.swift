//
//  ChatMediaOpenAnimation.swift
//  FeatureChat
//

import SwiftUI

/// Shared WhatsApp-like timing for camera ↔ media editor transitions.
enum ChatMediaOpenAnimation {
    static let duration: Double = 0.34

    static var spring: Animation {
        .spring(response: 0.38, dampingFraction: 0.86)
    }

    static var ease: Animation {
        .easeInOut(duration: duration)
    }

    /// Editor insertion: fade + slight scale-up (feels like growing from the thumb).
    static var editorInsertion: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.04, anchor: .center))
        )
    }

    static var chromeEnter: Animation {
        .easeOut(duration: 0.28).delay(0.08)
    }
}
