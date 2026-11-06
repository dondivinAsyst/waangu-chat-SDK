// NavigationKit/CoordinatorView.swift

import SwiftUI

// MARK: - CoordinatorView

/// Vue générique qui délègue le rendu à un coordinator.
///
/// Préserve le type statique de `C.Body` — SwiftUI peut differ
/// l'arbre de vues sans recréer les composants.
///
/// Usage :
/// ```swift
/// CoordinatorView(coordinator: coordinator)
/// ```
public struct CoordinatorView<C: Coordinator>: View {
    private let coordinator: C

    public init(coordinator: C) {
        self.coordinator = coordinator
    }

    public var body: some View {
        coordinator.view()
    }
}
