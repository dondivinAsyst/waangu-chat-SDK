//
//  CallPiPAnchorView.swift
//  FeatureChat
//
//  `AVPictureInPictureController` needs a source view that is live in the window
//  hierarchy — it is the thing the floating window animates out of. Rather than
//  ride on a camera preview that comes and goes with the call screen, PiP is
//  anchored to this: a zero-content view whose only job is to exist, mounted by
//  `CallPictureInPictureHost` for as long as the app shell does.
//

import SwiftUI
import UIKit

struct CallPiPAnchorView: UIViewRepresentable {

    /// Called once the backing view is in the hierarchy.
    let onViewCreated: (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        // Handed over on the next runloop turn: at makeUIView time the view has
        // no window yet, and PiP rejects a source view that is not on screen.
        DispatchQueue.main.async { onViewCreated(view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
