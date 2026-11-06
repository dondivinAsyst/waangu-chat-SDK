// NavigationKit — Coordinator.swift
// Protocoles fondamentaux du pattern coordinator.

import SwiftUI

// MARK: - Coordinator

/// Protocole racine pour tout coordinator de l'application.
///
/// Un coordinator est responsable d'un sous-arbre de navigation.
/// Il instancie ses vues, gère son état de navigation, et expose
/// un point d'entrée `view()` typé.
///
/// Contrainte Swift 6 : `@MainActor` sur le protocole garantit que
/// toutes les implémentations s'exécutent sur le thread principal,
/// ce qui est requis par SwiftUI.
@MainActor
public protocol Coordinator: AnyObject {
    /// Type de la vue racine exposée par ce coordinator.
    associatedtype Body: View

    /// Vue racine gérée par ce coordinator.
    /// SwiftUI differ ce type statiquement — ne jamais envelopper dans AnyView.
    @ViewBuilder
    func view() -> Body

    /// Point d'entrée du cycle de vie.
    /// Appelé par le coordinator parent via `addChild(_:)`.
    func start()
}


// MARK: - StackCoordinator

/// Coordinator gérant une pile de navigation SwiftUI.
///
/// Utilise `NavigationPath` pour rester agnostique des types de routes.
/// Les destinations concrètes sont déclarées via `navigationDestination`
/// dans la vue générée par `view()`.
///
/// Règle importante : ne jamais utiliser `AnyRoute` dans
/// `navigationDestination` — toujours passer le type concret.
///
/// ```swift
/// .navigationDestination(for: WalletStackRoute.self) { route in
///     self.destination(for: route)   // @ViewBuilder typé
/// }
/// ```
@MainActor
public protocol StackCoordinator: Coordinator {
    var navigationPath: NavigationPath { get set }

    func push(_ route: some StackRoute)
    func pop()
    func popToRoot()
    func popLast(_ count: Int)
}

public extension StackCoordinator {
    func push(_ route: some StackRoute) {
        navigationPath.append(route)
    }

    func pop() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    func popToRoot() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast(navigationPath.count)
    }

    func popLast(_ count: Int) {
        let safeCount = min(count, navigationPath.count)
        guard safeCount > 0 else { return }
        navigationPath.removeLast(safeCount)
    }
    
}


@MainActor
public protocol TabStackCoordinator: StackCoordinator {
    var pendingAction: (() -> Void)? { get set }
}

public extension TabStackCoordinator {
    func setPendingAction(_ action: @escaping () -> Void) {
        pendingAction = action
    }

    func consumePendingAction() {
        pendingAction?()
        pendingAction = nil
    }

}
