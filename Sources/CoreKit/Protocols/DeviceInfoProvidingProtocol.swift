//
//  DeviceInfoProvidingProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

//
// Protocole et types de capture d'informations device.
// L'implémentation concrète (DeviceInfoProviding) vit dans DeviceKit.
// Les types de données (DeviceInfoSnapshot, DeviceContext) restent dans CoreKit
// car ils sont partagés entre CoreKit (FeatureDependencies) et DeviceKit.

import Foundation

// MARK: - DeviceInfoSnapshot

/// Snapshot hardware utilisé pour calculer le DeviceTier.
/// Capturé une seule fois au lancement — immuable.
public struct DeviceInfoSnapshot: Sendable {
    public let processorCount: Int
    public let physicalMemoryMB: Int
    public let modelIdentifier: String
    public let systemVersion: String

    public init(
        processorCount: Int,
        physicalMemoryMB: Int,
        modelIdentifier: String,
        systemVersion: String
    ) {
        self.processorCount = processorCount
        self.physicalMemoryMB = physicalMemoryMB
        self.modelIdentifier = modelIdentifier
        self.systemVersion = systemVersion
    }
}

// MARK: - DeviceContext

/// Contexte device enrichi pour les appels API (device info, app version...).
/// Envoyé au serveur pour le tracking et le support.
public struct DeviceContext: Sendable {
    public let deviceId: String
    public let deviceModel: String
    public let brandName: String
    public let manufacturer: String
    public let osVersion: String
    public let appVersion: String
    public let buildNumber: String

    // MARK: Fix — `platformOS` en camelCase strict (PlatformOS → platformOS)
    public let platformOS: String

    /// Token Firebase pour les notifications push.
    /// `nil` si non encore enregistré — ne pas forcer une valeur par défaut.
    public let firebaseToken: String?

    public init(
        deviceId: String,
        deviceModel: String,
        brandName: String,
        manufacturer: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String,
        platformOS: String,
        firebaseToken: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceModel = deviceModel
        self.brandName = brandName
        self.manufacturer = manufacturer
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.platformOS = platformOS
        self.firebaseToken = firebaseToken
    }
}

// MARK: - DeviceInfoProvidingProtocol

/// Contrat de capture des informations device.
///
/// `nonisolated` sur les deux méthodes : la capture est synchrone
/// et thread-safe — pas besoin d'isolation d'acteur.
public protocol DeviceInfoProvidingProtocol: Sendable {

    /// Capture les données hardware pour calcul du DeviceTier.
    /// Appelé une seule fois au bootstrap.
    nonisolated func captureSnapshot() -> DeviceInfoSnapshot

    /// Capture le contexte device complet pour les appels API.
    /// Appelé à chaque envoi d'informations device au serveur.
    nonisolated func captureDeviceContext() -> DeviceContext
}
