//
//  ChatSessionLifecycle.swift
//  FeatureChat
//
//  Plan SDK, étape 1.8 — ce que le Chat fait quand la session de l'application change :
//  connexion, retour au premier plan, arrière-plan, déconnexion.
//

import WaanguCoreKit

/// Le temps réel et la synchro du Chat suivent la session de l'hôte.
///
/// Ces quatre réactions vivaient dans le `SessionManager` de l'application Waangu : chaque
/// nouvelle application devait les réécrire. L'hôte appelle maintenant une méthode par
/// événement et garde pour lui ce qui est à lui (analytique, rapport de plantage, synchro
/// de ses autres fonctions).
///
/// L'ordre et les cas limites sont ceux du code remplacé :
/// - le temps réel ne se connecte que si un jeton de chat, d'accès ou de rafraîchissement,
///   est encore valable ; la synchro est demandée dans tous les cas ;
/// - un échec de connexion est journalisé, jamais remonté ;
/// - en arrière-plan, le temps réel reste connecté tant qu'un appel sonne ou court : CallKit
///   peut répondre depuis l'écran verrouillé, et sans MQTT `call-join` ne part pas ;
/// - à la déconnexion, la synchro s'arrête avant que le temps réel ne soit coupé.
public actor ChatSessionLifecycle {

    private let realtime: any RealtimeClientProtocol
    private let sync: ChatSyncRunner
    private let chatTokenManager: any ChatTokenManagerProtocol
    private let logger: any AppLoggerProtocol
    private let retainsRealtimeInBackground: @Sendable () async -> Bool

    public init(
        realtime: any RealtimeClientProtocol,
        sync: ChatSyncRunner,
        chatTokenManager: any ChatTokenManagerProtocol,
        logger: any AppLoggerProtocol = AppLogger.shared,
        retainsRealtimeInBackground: @escaping @Sendable () async -> Bool = {
            await MainActor.run { ChatCallLifecycle.shouldRetainRealtimeConnection }
        }
    ) {
        self.realtime = realtime
        self.sync = sync
        self.chatTokenManager = chatTokenManager
        self.logger = logger
        self.retainsRealtimeInBackground = retainsRealtimeInBackground
    }

    /// L'utilisateur vient de se connecter, ou une session valide a été retrouvée au lancement.
    public func userDidSignIn() async {
        await resume()
    }

    /// L'application revient au premier plan.
    public func appDidEnterForeground() async {
        await resume()
    }

    /// L'application passe en arrière-plan.
    public func appDidEnterBackground() async {
        if await retainsRealtimeInBackground() {
            await logger.log("Keeping realtime in background — call in progress", level: .info)
            return
        }
        try? await realtime.disconnect(reason: .backgroundSuspended, flushQueue: true)
    }

    /// La session se termine.
    public func userDidSignOut() async {
        await sync.stop()
        try? await realtime.disconnect(reason: .userInitiated, flushQueue: true)
    }

    // MARK: - Private

    private func resume() async {
        await connectRealtimeIfAuthenticated()
        // Sans attendre : la synchro peut durer, et la connexion est déjà faite.
        Task { [sync] in await sync.syncNow() }
    }

    private func connectRealtimeIfAuthenticated() async {
        let hasAccess = await chatTokenManager.hasValidAccessToken()
        let hasRefresh = await chatTokenManager.hasValidRefreshToken()
        guard hasAccess || hasRefresh else { return }
        do {
            try await realtime.connect()
        } catch {
            await logger.log("Realtime connect failed: \(error)", level: .warning)
        }
    }
}
