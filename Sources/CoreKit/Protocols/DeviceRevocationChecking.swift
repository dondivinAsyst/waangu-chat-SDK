//
//  DeviceRevocationChecking.swift
//  CoreKit
//
//  Bloc 8, §33 — invariant REVOKED_DEVICE_CANNOT_SYNC_SENSITIVE_DATA.
//

import Foundation

/// Vérifie qu'un appareil n'est pas révoqué avant de lui laisser synchroniser
/// des données sensibles.
///
/// Déclaré ici, et non dans `SecurityKit`, parce que l'appelant est une feature :
/// `DeviceRevocationGuard` vit dans `SecurityKit`, dont `FeatureChat` ne dépend
/// pas et ne doit pas dépendre. Le §33 était donc **inapplicable** — le garde
/// existait sans qu'aucun chemin de synchronisation puisse l'interroger.
/// CoreKit est le lieu des contrats partagés entre modules ; la porte se déclare
/// ici, et `SecurityKit` s'y conforme.
public protocol DeviceRevocationChecking: Sendable {

    /// Lève si l'appareil est révoqué.
    ///
    /// Lève plutôt que de rendre un `Bool` : un appelant qui ignore un booléen
    /// compile, et l'invariant se perd en silence.
    func validateNotRevoked(deviceId: String) async throws
}

/// N'interdit rien.
///
/// Défaut explicite pour les chemins qui ne portent pas de données sensibles,
/// et pour les tests. Un optionnel obligerait chaque appelant à écrire
/// `try await guard?.validate(...)`, qu'on finit par oublier.
public struct AllowAllDeviceRevocation: DeviceRevocationChecking {
    public init() {}
    public func validateNotRevoked(deviceId: String) async throws {}
}
