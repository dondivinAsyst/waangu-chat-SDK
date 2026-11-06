//
//  SyncPage.swift
//  AppModules
//
//  Created by Asyst on 6/18/26.
//

import Foundation

// MARK: - Sync Page

/// Résultat d'une page de synchro descendante.
/// Retourné par `SyncDelegate.fetchPage(...)`.
///
/// Le sync engine consomme ce type pour piloter la boucle de pagination :
///   - `events` → délégués à `processEvent` un par un
///   - `nextCursor` → passé au prochain `fetchPage` (nil = dernière page)
///   - `hasMore` → décide si on continue ou on s'arrête
public struct SyncPage<Event: Codable & Sendable>: Codable, Sendable {

    /// Événements de cette page.
    public let events: [Event]

    /// Cursor pour la page suivante. `nil` si c'est la dernière.
    public let nextCursor: String?

    /// `true` s'il reste des pages après celle-ci.
    public let hasMore: Bool

    public init(events: [Event], nextCursor: String?, hasMore: Bool) {
        self.events = events
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}
