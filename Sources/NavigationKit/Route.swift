// NavigationKit/Route.swift

import Foundation

// MARK: - Route

/// Destination navigable dans l'application.
/// Chaque feature déclare ses propres types conformes à StackRoute.
public protocol Route: Hashable, Sendable {}

/// Route destinée à être poussée dans une NavigationStack (push/pop).
public protocol StackRoute: Route {}
