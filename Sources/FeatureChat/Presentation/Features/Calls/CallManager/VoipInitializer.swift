//
//  VoipInitializer.swift
//  Pods
//
//  Created by Asyst on 11/11/25.
//

import Foundation
import UIKit
import WaanguCoreKit

class VoipInitializer {
    static let shared = VoipInitializer()
    private var initialized = false

    private init() {}

    func initializeIfNeeded() {
        guard !initialized else {
            debugLog("VoIP already initialized")
            return
        }

        debugLog("Initializing VoIP subsystem…")

        // Forcer l’initialisation du singleton
        _ = VoipManager.shared

        // Écouter les changements d’état d’application
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        initialized = true
    }

    @objc private func appDidEnterBackground() {
        VoipManager.shared.handleAppBackground()
    }

    @objc private func appWillEnterForeground() {
        VoipManager.shared.handleAppForeground()
    }
}
