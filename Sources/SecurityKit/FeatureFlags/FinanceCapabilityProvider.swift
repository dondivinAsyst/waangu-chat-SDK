//
//  FinanceCapabilityProvider.swift
//  SecurityKit
//
//  Fournit le catalogue de capacités financières aux features — tâche 3.1.

import Foundation
import WaanguCoreKit

/// Résout et met en cache les capacités financières.
///
/// S'adosse à `SovereignFeatureFlags` pour la souveraineté du catalogue, et au
/// backend pour sa résolution. Le cache est invalidé dès qu'une dimension du
/// contexte change — pays, tenant, KYC, risque — parce qu'un utilisateur qui
/// change de pays ne doit pas conserver les capacités du précédent.
///
/// **Fermé par défaut** : toute erreur, tout catalogue expiré, tout contexte
/// divergent donne `.none`.
public actor FinanceCapabilityProvider: FinanceCapabilityProviding {

    /// Résout le catalogue auprès du backend.
    ///
    /// Fermeture plutôt que dépendance sur `FinanceAPIClientProtocol` : cela
    /// évite un cycle, l'API client ayant lui-même besoin de connaître les
    /// capacités pour refuser un appel non autorisé.
    public typealias Resolver = @Sendable (FinanceCapabilityContext) async throws -> FinanceCapabilities

    private let resolve: Resolver
    private let contextProvider: @Sendable () async -> FinanceCapabilityContext
    private let logger: AppLogger

    private var cached: FinanceCapabilities?
    private var cachedFor: FinanceCapabilityContext = .unknown

    public init(
        logger: AppLogger,
        contextProvider: @escaping @Sendable () async -> FinanceCapabilityContext,
        resolve: @escaping Resolver
    ) {
        self.logger = logger
        self.contextProvider = contextProvider
        self.resolve = resolve
    }

    // MARK: - FinanceCapabilityProviding

    public func capabilities() async -> FinanceCapabilities {
        let context = await contextProvider()

        // Le cache ne vaut que pour le contexte exact qui l'a produit.
        if let cached, cachedFor.matches(context), cached.isValid() {
            return cached
        }

        do {
            let resolved = try await resolve(context)

            // Le catalogue doit répondre pour le contexte demandé. Un catalogue
            // résolu ailleurs — réponse en cache côté réseau, changement de compte
            // en vol — ne s'applique pas ici.
            guard resolved.context.matches(context) else {
                await logger.log(
                    "Catalogue de capacités hors contexte — ignoré",
                    level: .warning
                )
                return .none
            }

            cached = resolved
            cachedFor = context
            return resolved.effective()

        } catch {
            // Aucun repli permissif : une capacité non résolue est une capacité fermée.
            await logger.log(
                "Résolution des capacités financières impossible — catalogue fermé",
                level: .warning
            )
            return .none
        }
    }

    public func invalidate() async {
        cached = nil
        cachedFor = .unknown
    }
}

// MARK: - Fournisseur statique

/// Catalogue fixe, pour les tests et les cibles où la finance est désactivée.
public struct StaticFinanceCapabilityProvider: FinanceCapabilityProviding {

    private let value: FinanceCapabilities

    /// Par défaut `.none` : un fournisseur construit sans argument n'ouvre rien.
    public init(_ value: FinanceCapabilities = .none) {
        self.value = value
    }

    public func capabilities() async -> FinanceCapabilities { value.effective() }
    public func invalidate() async {}
}
