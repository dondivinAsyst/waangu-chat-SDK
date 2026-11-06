// NavigationKit/Intent/NavigationIntent.swift

import Foundation

/// Intention de navigation cross-feature.
/// Purement sémantique — zéro import de feature.
/// Chaque feature l'utilise via NavigationIntents.FeatureName.*
public struct NavigationIntent: Hashable, Sendable {
    public let feature: String
    public let screen: String
    public let params: [String: String]

    public init(feature: String, screen: String, params: [String: String] = [:]) {
        self.feature = feature
        self.screen = screen
        self.params = params
    }
}
