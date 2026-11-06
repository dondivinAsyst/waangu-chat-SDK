//
//  BlurView.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  BlurViewButton.swift
//  chatpreview
//
//  Created by Asyst on 7/1/25.

import SwiftUI
import UIKit

public struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterial // Stronger than ultraThin

    public func makeUIView(context: Context) -> UIVisualEffectView {
        let effect = UIBlurEffect(style: style)
        let view = UIVisualEffectView(effect: effect)
        view.overrideUserInterfaceStyle = ChatAppearanceStore.shared.defaultAppearance.userInterfaceStyle
        view.backgroundColor = UIColor.systemFill.withAlphaComponent(0.2)
        view.clipsToBounds = true
        return view
    }

    public func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.overrideUserInterfaceStyle = ChatAppearanceStore.shared.defaultAppearance.userInterfaceStyle
    }
}

