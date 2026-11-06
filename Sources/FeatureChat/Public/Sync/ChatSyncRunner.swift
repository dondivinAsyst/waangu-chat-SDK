//
//  ChatSyncRunner.swift
//  FeatureChat
//
//  Point d'entrée de la synchro en arrière-plan pour une application hôte.
//

import WaanguCoreKit

/// Lance la synchro du Chat depuis le cycle de vie de l'hôte : connexion, retour au
/// premier plan, déconnexion ou passage en arrière-plan.
///
/// `syncNow()` envoie les actions en attente puis relit les événements manqués. Il ne
/// démarre pas de flux live : `ChatFeature` garde le sien, et l'hôte construit son moteur
/// avec `liveUpdates: false` pour qu'un événement ne soit pas appliqué deux fois.
///
/// L'hôte fournit le moteur (`FeatureSyncEngine<ChatSyncDelegate>`) : l'outbox qui envoie
/// et le client API vivent dans son conteneur de dépendances.
public actor ChatSyncRunner {

    private let sync: any FeatureSyncProtocol
    private var isRunning = false

    public init(sync: any FeatureSyncProtocol) {
        self.sync = sync
    }

    /// Une synchro à la fois : un appel pendant qu'une autre tourne est ignoré, pas mis en
    /// file (le prochain retour au premier plan en relancera une).
    public func syncNow() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        await sync.flushOutbox()
        guard !Task.isCancelled else { return }
        await sync.pullMissedEvents()
    }

    /// Vrai quand la synchro bute depuis plusieurs passages sur le même événement : l'hôte peut
    /// le signaler à l'utilisateur ou à son support. Lecture seule, sans effet sur la synchro.
    public func isDegraded() async -> Bool {
        await sync.isDegraded()
    }

    /// Annule la synchro en cours (déconnexion, arrière-plan).
    public func stop() async {
        await sync.stopSync()
    }
}
