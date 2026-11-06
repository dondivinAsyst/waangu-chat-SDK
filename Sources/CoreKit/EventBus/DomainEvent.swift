//
//  DomainEvent.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// MARK: - CoreKit/Events/DomainEvent.swift

//
//  DomainEvent.swift
//  AppModules
//
//  CoreKit/Sources/Events
//

import Foundation

// MARK: - Base Protocol

/// Marqueur de base pour tous les événements du domaine.
/// - `Sendable` : traversé entre acteurs et Tasks
/// - `CustomStringConvertible` : debug logging dans EventBus
public protocol DomainEvent: Sendable, CustomStringConvertible {}

// MARK: - Matchable (filtrage par valeur exacte)

/// Event filtrable par valeur exacte via `EventBus.on(_:)`.
/// Implémenter `==` manuellement sur les enums avec associated values.
public protocol MatchableDomainEvent: DomainEvent, Equatable {}

// MARK: - Replayable (dernier événement rejouable aux nouveaux abonnés)

/// Marqueur pour les événements dont le dernier état doit être
/// immédiatement livré aux nouveaux abonnés.
///
/// Usage typique : événements de cycle de vie (`UserDidLoginEvent`,
/// `UserDidLogoutEvent`, `ConnectivityChangedEvent`) où un abonné
/// tardif doit connaître l'état courant sans attendre le prochain publish.
public protocol ReplayableDomainEvent: DomainEvent {}


