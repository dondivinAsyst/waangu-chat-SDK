
//
//  SyncState.swift
//  AppModules
//
//  CoreKit/Sources/Sync
//

import Foundation

// MARK: - Sync State

public struct SyncState: Storable {

    public static let namespace = "sync"

    public var id: String
    public var lastSyncTimestamp: Date?
    public var currentCursor: String?
    public var isSyncing: Bool

    /// Événement que le pull n'arrive pas à écrire : page de départ + rang dans la page.
    /// Optionnels pour que les états enregistrés avant ce champ se relisent.
    public var blockedEventKey: String?
    /// Passages consécutifs échoués sur `blockedEventKey` (le compteur survit au relancement).
    public var blockedAttempts: Int?
    /// Dernière raison donnée par le délégué.
    public var blockedReason: String?

    /// Vrai quand le pull bute sur le même événement depuis `SyncState.maxBlockedAttempts`
    /// passages : la synchro est dégradée, l'hôte peut le lire dans le namespace `sync`.
    public var isDegraded: Bool { (blockedAttempts ?? 0) >= Self.maxBlockedAttempts }

    public static let maxBlockedAttempts = 3

    public init(feature: String) {
        self.id = feature
        self.lastSyncTimestamp = nil
        self.currentCursor = nil
        self.isSyncing = false
    }
}
