//
//  PrivacyShieldTests.swift
//  SharedUITests
//
//  Bloc 9, G9-04 — preuve (niveau 6) du masquage à l'entrée en arrière-plan.
//

import XCTest
import UIKit
@testable import WaanguSharedUI

/// Vérifie que le masque se pose **avant** la capture système et se retire après.
///
/// Le défaut que ces tests attrapent n'est pas « le masque n'existe pas » mais
/// « le masque arrive trop tard ». iOS photographie l'écran entre
/// `willResignActive` et `didEnterBackground` : un masque posé sur la seconde
/// notification est parfaitement visible à l'exécution et parfaitement inutile.
@MainActor
final class PrivacyShieldTests: XCTestCase {

    private var window: UIWindow!
    private var shield: PrivacyShield!

    override func setUp() async throws {
        try await super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        shield = PrivacyShield()
        shield.attach(to: window)
    }

    override func tearDown() async throws {
        shield = nil
        window = nil
        try await super.tearDown()
    }

    private var overlayCount: Int {
        window.subviews.filter { $0.backgroundColor == .systemBackground }.count
    }

    // MARK: - Le contrôle central

    func test_coversOnWillResignActive_notOnlyOnBackground() {
        XCTAssertEqual(overlayCount, 0, "Aucun masque avant la mise en arrière-plan")

        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )

        XCTAssertEqual(
            overlayCount, 1,
            "Le masque doit être posé sur willResignActive : la capture système intervient avant didEnterBackground."
        )
    }

    func test_uncoversOnDidBecomeActive() {
        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )
        XCTAssertEqual(overlayCount, 1)

        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification, object: nil
        )

        XCTAssertEqual(overlayCount, 0, "Le masque doit disparaître au retour au premier plan")
    }

    /// Deux passages en arrière-plan sans retour au premier plan ne doivent pas
    /// empiler deux masques : le second resterait après le retrait du premier.
    func test_repeatedResign_doesNotStackOverlays() {
        for _ in 0..<3 {
            NotificationCenter.default.post(
                name: UIApplication.willResignActiveNotification, object: nil
            )
        }

        XCTAssertEqual(overlayCount, 1, "Un seul masque, quel que soit le nombre de notifications")

        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        XCTAssertEqual(overlayCount, 0, "Un retrait doit suffire à tout enlever")
    }

    /// Le masque doit être opaque : un fond translucide laisserait transparaître
    /// ce qu'il est censé cacher.
    func test_overlayIsOpaque() {
        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )

        let overlay = window.subviews.first { $0.backgroundColor == .systemBackground }

        // `systemBackground` est une couleur dynamique : il faut la résoudre
        // pour un style d'interface avant de lire ses composantes. Interroger
        // la couleur dynamique directement échoue et rendrait alpha à 0, ce qui
        // ferait échouer ce test pour une mauvaise raison.
        let resolved = overlay?.backgroundColor?.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        var alpha: CGFloat = 0
        let readable = resolved?.getRed(nil, green: nil, blue: nil, alpha: &alpha) ?? false

        XCTAssertTrue(readable, "Composantes illisibles — couleur non résolue")
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001, "Le masque doit être opaque")
        XCTAssertEqual(overlay?.alpha, 1.0, "La vue elle-même ne doit pas être transparente")
    }

    /// Le masque doit couvrir toute la fenêtre, y compris après rotation.
    func test_overlayCoversFullWindow() {
        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )

        let overlay = window.subviews.first { $0.backgroundColor == .systemBackground }
        XCTAssertEqual(overlay?.frame, window.bounds)
        XCTAssertTrue(
            overlay?.autoresizingMask.contains(.flexibleWidth) ?? false,
            "Sans redimensionnement automatique, une rotation découvrirait l'écran."
        )
    }
}
