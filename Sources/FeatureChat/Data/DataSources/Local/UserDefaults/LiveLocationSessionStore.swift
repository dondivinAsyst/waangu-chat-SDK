//
//  LiveLocationSessionStore.swift
//  FeatureChat
//

import Foundation

/// The shares this device is publishing, across launches.
///
/// Replaces a single `LiveLocationExpiryDate` key that could hold one deadline
/// for the whole app — with no share id and no conversation, a second live
/// share silently overwrote the first, and neither could be stopped by name.
///
/// `UserDefaults` rather than GRDB on purpose: this is a handful of rows that
/// must be readable the instant the app starts, before the database is opened,
/// so a share can resume without waiting on anything.
struct LiveLocationSessionStore: LiveLocationSessionStoring {

    private let defaults: UserDefaults
    private let key = "chat.liveLocation.activeShares"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every stored share, expired ones dropped.
    func load(asOf now: Date) -> [LiveLocationShareSession] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let stored = try? JSONDecoder().decode([LiveLocationShareSession].self, from: data) else {
            // Unreadable is the same as absent here: nothing is lost but a
            // resume, and leaving the bad payload in place would fail forever.
            defaults.removeObject(forKey: key)
            return []
        }
        return stored.filter { $0.isActive(asOf: now) }
    }

    func save(_ sessions: [LiveLocationShareSession]) {
        guard !sessions.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: key)
    }

    func upsert(_ session: LiveLocationShareSession) {
        var sessions = load()
        sessions.removeAll { $0.shareId == session.shareId }
        sessions.append(session)
        save(sessions)
    }

    func remove(shareId: String) {
        save(load().filter { $0.shareId != shareId })
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }
}
