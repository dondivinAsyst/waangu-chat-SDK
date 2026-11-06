//
//  PrivacyShield.swift
//  SharedUI
//
//  Bloc 9, G9-04 (ch. 73, §14) — masquage à l'entrée en arrière-plan.
//

import UIKit
import SwiftUI

/// Masque le contenu sensible avant que le système ne photographie l'écran.
///
/// iOS capture une image de l'application à chaque passage en arrière-plan pour
/// l'App Switcher, et **l'écrit sur disque**. Sans masquage, cette image porte
/// le dernier écran affiché : solde, bénéficiaire, montant, QR de paiement.
/// Elle survit à la fermeture de l'application et se retrouve dans une
/// sauvegarde.
///
/// Le moment est ce qui compte. `willResignActive` arrive **avant** la capture ;
/// `didEnterBackground` arrive après, et masquer là ne protège de rien.
@MainActor
public final class PrivacyShield {

    private weak var window: UIWindow?
    private var overlay: UIView?
    private var observers: [NSObjectProtocol] = []

    public init() {}

    /// Arme le masquage sur cette fenêtre.
    public func attach(to window: UIWindow) {
        self.window = window
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cover() }
            }
        )

        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.uncover() }
            }
        )
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Masquage

    private func cover() {
        guard let window, overlay == nil else { return }

        let view = UIView(frame: window.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Fond opaque du système, pas une couleur de marque : l'écran de
        // masquage n'est pas une surface de design, et un fond translucide
        // laisserait transparaître ce qu'il doit cacher.
        view.backgroundColor = .systemBackground

        let mark = UIImageView(image: UIImage(systemName: "lock.fill"))
        mark.tintColor = .tertiaryLabel
        mark.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        window.addSubview(view)
        overlay = view
    }

    private func uncover() {
        overlay?.removeFromSuperview()
        overlay = nil
    }
}

// MARK: - Vue sensible

/// Retire le contenu de la capture système, écran par écran.
///
/// Complément de ``PrivacyShield``, qui masque toute la fenêtre : ce modificateur
/// s'applique à une vue précise — un solde, un numéro de carte — et sert aussi
/// contre la capture d'écran, que `PrivacyShield` ne voit pas.
///
/// Le mécanisme s'appuie sur un `UITextField` en mode saisie sécurisée, dont la
/// couche est exclue des captures par le système. C'est un détour, mais c'est le
/// seul moyen documenté d'obtenir ce comportement sur iOS.
public struct SensitiveContentModifier: ViewModifier {

    public func body(content: Content) -> some View {
        SecureContainer { content }
    }
}

public extension View {

    /// Exclut cette vue des captures et de l'instantané système.
    func sensitiveContent() -> some View {
        modifier(SensitiveContentModifier())
    }
}

private struct SecureContainer<Content: View>: UIViewRepresentable {

    @ViewBuilder let content: () -> Content

    func makeUIView(context: Context) -> UIView {
        let field = UITextField()
        field.isSecureTextEntry = true

        // La couche protégée du champ est son premier sous-vue. Si l'implémentation
        // système change, on retombe sur une vue ordinaire : le contenu reste
        // lisible plutôt que de disparaître, ce qui serait un défaut visible.
        let container = field.subviews.first ?? UIView()
        container.subviews.forEach { $0.removeFromSuperview() }

        let hosting = UIHostingController(rootView: content())
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        context.coordinator.hosting = hosting
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hosting?.rootView = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var hosting: UIHostingController<Content>?
    }
}
