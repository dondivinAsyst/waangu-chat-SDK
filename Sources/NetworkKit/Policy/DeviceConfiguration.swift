// MARK: - NetworkKit/Policy/DeviceConfiguration.swift
//
// Configuration réseau runtime calculée depuis DeviceTier + snapshots dynamiques.
// Strictement réseau — ImageQuality et AnimationQuality ont été extraits dans
// App/Configuration/UIConfiguration.swift (configs UI, pas réseau).
//
// isConnectedToNetwork supprimé : lu dynamiquement via NetworkMonitor à chaque
// requête dans APIClient — jamais figé dans un struct.

import Foundation

public struct DeviceConfiguration: Sendable {

    // MARK: - Réseau
    /// Nombre max de requêtes HTTP concurrentes.
    public var maxConcurrentRequests: Int

    /// Taille du cache HTTP en MB.
    public var cacheSizeMB: Int

    /// Active ou désactive les mises à jour en background.
    public var backgroundUpdates: Bool

    // MARK: - Retry
    /// Profil de retry sélectionné par AdaptivePolicyResolver.
    public var retryProfile: RetryProfile

    // MARK: - Timeout
    /// Multiplicateur appliqué au baseTimeout de chaque endpoint.
    /// Ex : 1.5 → timeout × 1.5 sur les devices lents ou réseau contraint.
    public var timeoutMultiplier: Double

    /// Timeout minimum absolu — jamais en dessous, même après multiplication.
    public var minTimeout: TimeInterval

    /// Timeout maximum absolu — jamais au dessus, même après multiplication.
    public var maxTimeout: TimeInterval

    public init(
        maxConcurrentRequests: Int,
        cacheSizeMB: Int,
        backgroundUpdates: Bool,
        retryProfile: RetryProfile,
        timeoutMultiplier: Double,
        minTimeout: TimeInterval,
        maxTimeout: TimeInterval
    ) {
        self.maxConcurrentRequests = maxConcurrentRequests
        self.cacheSizeMB = cacheSizeMB
        self.backgroundUpdates = backgroundUpdates
        self.retryProfile = retryProfile
        self.timeoutMultiplier = timeoutMultiplier
        self.minTimeout = minTimeout
        self.maxTimeout = maxTimeout
    }
}
