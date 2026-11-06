
//
//  EventBus.swift
//  AppModules
//
//  CoreKit/Sources/Events
//

import Foundation
import OSLog

public actor EventBus: EventBusProtocol {

    // MARK: - Singleton

    public static let shared = EventBus()
    private init() {}

    // MARK: - Storage

    /// Listeners par type d'événement, type-erasé via `ListenerBox`.
    private var listenersByEvent: [ObjectIdentifier: Any] = [:]

    /// Cache du dernier événement publié pour les types `ReplayableDomainEvent`.
    private var replayCache: [ObjectIdentifier: Any] = [:]

    private static let maxBufferSize = 64

    private let logger = Logger(subsystem: "com.waangu.eventbus", category: "EventBus")

    // MARK: - Publish

    public func publish<E: DomainEvent>(_ event: E) async {
        let key = ObjectIdentifier(E.self)

        // Mise en cache si replayable
        if event is any ReplayableDomainEvent {
            replayCache[key] = event
        }

        guard let box = listenersByEvent[key] as? ListenerBox<E>,
              !box.handlers.isEmpty else {
            logger.debug("No listeners for \(event.description, privacy: .public)")
            return
        }

        for handler in box.handlers.values {
            handler(event)
        }
    }

    // MARK: - Stream (typed)

    public nonisolated func stream<E: DomainEvent>(for type: E.Type) -> AsyncStream<E> {
        AsyncStream(bufferingPolicy: .bufferingNewest(Self.maxBufferSize)) { continuation in
            let id = UUID()

            let task = Task {
                await self.register(id: id, type: type, continuation: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.unregister(id: id, type: type) }
            }
        }
    }

    // MARK: - on(_:) — filter par valeur exacte

    public nonisolated func on<E: MatchableDomainEvent>(_ target: E) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(Self.maxBufferSize)) { continuation in
            let id = UUID()

            let task = Task {
                await self.registerFiltered(
                    id: id,
                    target: target,
                    continuation: continuation
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.unregister(id: id, type: E.self) }
            }
        }
    }

    // MARK: - Registration internals

    /// Enregistre un listener typé et rejoue le dernier événement si `E` est `ReplayableDomainEvent`.
    private func register<E: DomainEvent>(
        id: UUID,
        type: E.Type,
        continuation: AsyncStream<E>.Continuation
    ) {
        let key = ObjectIdentifier(E.self)
        var box = listenersByEvent[key] as? ListenerBox<E> ?? ListenerBox()

        box.handlers[id] = { event in continuation.yield(event) }
        listenersByEvent[key] = box

        // Replay immédiat pour les nouveaux abonnés
        if let cached = replayCache[key] as? E {
            continuation.yield(cached)
        }
    }

    /// Enregistre un listener filtré par valeur (pour `on(_:)`).
    /// Évite de créer un stream intermédiaire → pas de double pipeline.
    private func registerFiltered<E: MatchableDomainEvent>(
        id: UUID,
        target: E,
        continuation: AsyncStream<Void>.Continuation
    ) {
        let key = ObjectIdentifier(E.self)
        var box = listenersByEvent[key] as? ListenerBox<E> ?? ListenerBox()

        box.handlers[id] = { event in
            if event == target {
                continuation.yield(())
            }
        }
        listenersByEvent[key] = box

        // Replay filtré
        if let cached = replayCache[key] as? E, cached == target {
            continuation.yield(())
        }
    }

    private func unregister<E: DomainEvent>(id: UUID, type: E.Type) {
        let key = ObjectIdentifier(type)
        guard var box = listenersByEvent[key] as? ListenerBox<E> else { return }
        box.handlers.removeValue(forKey: id)
        listenersByEvent[key] = box.handlers.isEmpty ? nil : box
    }

    // MARK: - Testing support

    #if DEBUG
    /// Réinitialise tout l'état. Usage : tests uniquement.
    public func reset() {
        listenersByEvent.removeAll()
        replayCache.removeAll()
    }

    /// Nombre de listeners inscrits pour un type donné.
    public func listenerCount<E: DomainEvent>(for type: E.Type) -> Int {
        let key = ObjectIdentifier(E.self)
        guard let box = listenersByEvent[key] as? ListenerBox<E> else { return 0 }
        return box.handlers.count
    }

    /// Dernier événement replayable en cache pour un type donné.
    public func cachedEvent<E: DomainEvent>(for type: E.Type) -> E? {
        replayCache[ObjectIdentifier(E.self)] as? E
    }
    #endif
}

// MARK: - ListenerBox

/// Conteneur typé pour les closures de listeners.
/// Centralise le cast `Any ↔ ListenerBox<E>` au lieu de le répéter à chaque accès.
private struct ListenerBox<E: DomainEvent>: Sendable {
    var handlers: [UUID: @Sendable (E) -> Void] = [:]
}
