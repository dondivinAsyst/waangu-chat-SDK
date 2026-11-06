//
//  EventBusProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

import Foundation

/// Contrat public du bus d'événements.
/// Toujours injecter ce protocole — jamais `EventBus` directement.
// MARK: - EventBus Contract

public protocol EventBusProtocol: Sendable {

    func publish<E: DomainEvent>(_ event: E) async

    func stream<E: DomainEvent>(for type: E.Type) -> AsyncStream<E>

    /// Alias sémantique pour `stream(for:)`.
    /// Déclaré comme requirement (pas juste extension) pour
    /// fonctionner avec `any EventBusProtocol`.
    func subscribe<E: DomainEvent>(to type: E.Type) -> AsyncStream<E>

    func on<E: MatchableDomainEvent>(_ target: E) -> AsyncStream<Void>
}

// MARK: - Default Implementation

public extension EventBusProtocol {

    func subscribe<E: DomainEvent>(to type: E.Type) -> AsyncStream<E> {
        stream(for: type)
    }
}
