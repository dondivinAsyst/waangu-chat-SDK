//
//  HideKeyboard.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//

import SwiftUI
import UIKit

enum ChatKeyboard {
    /// Dismisses the first responder (composer) from Views or ViewModels.
    @MainActor
    static func hide() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    public func hideKeyboard() {
        ChatKeyboard.hide()
    }
}
