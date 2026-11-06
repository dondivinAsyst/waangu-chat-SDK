//
//  SovereignFeatureFlags.swift
//  CoreKit
//
//  Sovereign feature flags (backend-controlled only)
//  RULE: Feature flags souverains uniquement

import Foundation
import WaanguCoreKit

public actor SovereignFeatureFlags {
    
    public static let shared = SovereignFeatureFlags()
    
    private var flags: [String: FeatureFlag] = [:]
    private var localOverrideAttempts: [OverrideAttempt] = []

    /// Vérificateur de signature. `nil` tant qu'aucun n'est installé — auquel cas
    /// aucun drapeau backend n'est accepté.
    private var verifier: (any FinancialSignatureVerifying)?
    
    private init() {}

    /// Installe le vérificateur de signature des drapeaux.
    public func configure(verifier: any FinancialSignatureVerifying) {
        self.verifier = verifier
    }
    
    // MARK: - Feature Flag Management
    
    /// Sets feature flag from backend (sovereign source)
    /// RULE: Feature flags souverains uniquement
    public func setFlagFromBackend(
        name: String,
        enabled: Bool,
        backendSignature: String,
        metadata: [String: String] = [:]
    ) async throws {
        
        // Verify backend signature
        guard try await verifyBackendSignature(name: name, enabled: enabled, signature: backendSignature) else {
            throw FeatureFlagError.invalidBackendSignature
        }
        
        let flag = FeatureFlag(
            name: name,
            enabled: enabled,
            source: .backend,
            signature: backendSignature,
            metadata: metadata,
            updatedAt: Date()
        )
        
        flags[name] = flag
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "feature_flag_updated",
                "flag": name,
                "enabled": String(enabled),
                "source": "backend"
            ],
            severity: .info
        )
    }
    
    /// Attempts to set flag locally (BLOCKED)
    /// RULE: Feature flags souverains uniquement
    public func setFlagLocally(name: String, enabled: Bool) async throws {
        
        // RULE: Feature flags souverains uniquement
        let attempt = OverrideAttempt(
            flagName: name,
            attemptedValue: enabled,
            timestamp: Date(),
            blocked: true
        )
        
        localOverrideAttempts.append(attempt)
        
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "violation": "local_feature_flag_override_blocked",
                "flag": name,
                "attempted_value": String(enabled)
            ]
        )
        
        throw FeatureFlagError.localOverrideNotAllowed(flag: name)
    }
    
    /// Checks if feature is enabled
    public func isEnabled(_ name: String) -> Bool {
        flags[name]?.enabled ?? false
    }
    
    /// Gets feature flag
    public func getFlag(_ name: String) -> FeatureFlag? {
        flags[name]
    }
    
    /// Gets all flags
    public func getAllFlags() -> [FeatureFlag] {
        Array(flags.values)
    }
    
    /// Gets blocked override attempts
    public func getBlockedOverrides() -> [OverrideAttempt] {
        localOverrideAttempts
    }
    
    // MARK: - Backend Signature Verification
    
    /// Vérifie la signature backend d'un drapeau.
    ///
    /// ## Audit — tâche 2.6 du BLOC1-IMPLEMENTATION-TODO
    ///
    /// **Verdict : ne vérifie rien d'exploitable.** Les deux contrôles portent sur
    /// la forme de la chaîne — non vide, décodable en base64 — et non sur son
    /// authenticité. Ni `name` ni `enabled` n'entrent dans le calcul : la même
    /// signature autorise donc n'importe quel drapeau à n'importe quelle valeur.
    /// Concrètement, `"AAAA"` active tout.
    ///
    /// **Conséquence pour le Bloc 1.** Ce drapeau souverain est présenté comme la
    /// protection intérimaire des capacités financières tant que le contrat backend
    /// #1 n'est pas livré. Une protection qui accepte `"AAAA"` n'en est pas une
    /// — un attaquant capable d'atteindre ce point d'entrée active les capacités
    /// qu'il veut.
    ///
    /// **Correction retenue.** La vérification passe par
    /// `FinancialSignatureVerifying`, comme les objets financiers, sur un contenu
    /// canonique qui inclut le nom du drapeau et sa valeur. Tant qu'aucun
    /// vérificateur n'est installé, `setFlagFromBackend` **refuse** — au lieu
    /// d'accepter. C'est le sens sûr : aucun drapeau installé signifie aucune
    /// capacité financière ouverte, ce qui est exactement l'état voulu avant
    /// livraison du contrat.
    ///
    /// **BACKEND CONTRACT REQUIRED** — contrat #5 : forme canonique signée du
    /// catalogue de drapeaux, et clé de vérification.
    private func verifyBackendSignature(name: String, enabled: Bool, signature: String) async throws -> Bool {
        guard !signature.isEmpty else { return false }

        guard let verifier else {
            // Pas de vérificateur : on refuse. L'ancien comportement acceptait.
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: [
                    "violation": "feature_flag_unverifiable",
                    "flag": name
                ]
            )
            return false
        }

        // Contenu canonique : le nom et la valeur en font partie, sans quoi une
        // signature valide pour un drapeau vaudrait pour tous les autres.
        let payload = FinancialSignaturePayload(
            objectType: .payment,
            objectID: "feature-flag:\(name)",
            version: 0,
            amount: 0,
            currency: "-",
            status: enabled ? .confirmed : .cancelled,
            idempotencyKey: name
        )

        switch await verifier.verify(signature: signature, over: payload) {
        case .authentic:
            return true
        case .forged, .unverifiable:
            return false
        }
    }
    
    // MARK: - Types
    
    public struct FeatureFlag {
        public let name: String
        public let enabled: Bool
        public let source: FlagSource
        public let signature: String
        public let metadata: [String: String]
        public let updatedAt: Date
    }
    
    public enum FlagSource: String {
        case backend
        case local // Not allowed
    }
    
    public struct OverrideAttempt {
        public let flagName: String
        public let attemptedValue: Bool
        public let timestamp: Date
        public let blocked: Bool
    }
    
    public enum FeatureFlagError: Error, LocalizedError {
        case invalidBackendSignature
        case localOverrideNotAllowed(flag: String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidBackendSignature:
                return "Feature flag backend signature is invalid"
            case .localOverrideNotAllowed(let flag):
                return "Local override not allowed for feature flag: \(flag). Flags are sovereign (backend-controlled only)."
            }
        }
    }
}
