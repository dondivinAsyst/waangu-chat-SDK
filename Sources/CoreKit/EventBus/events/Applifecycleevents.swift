//
//  Applifecycleevents.swift
//  AppModules
//
//  Created by Asyst on 6/17/26.
//

//
//  AppLifecycleEvents.swift
//  AppModules
//
//  CoreKit/Sources/Events
//

import Foundation

/// L'app est passée au premier plan (active).
/// Publié par WaanguApp lors du changement de scenePhase → .active
public struct AppDidEnterForegroundEvent: DomainEvent {
    public let timestamp: Date

    public init(timestamp: Date = .now) {
        self.timestamp = timestamp
    }

    public var description: String { "AppDidEnterForegroundEvent" }
}

/// L'app est passée en arrière-plan.
/// Publié par WaanguApp lors du changement de scenePhase → .background
public struct AppDidEnterBackgroundEvent: DomainEvent {
    public let timestamp: Date

    public init(timestamp: Date = .now) {
        self.timestamp = timestamp
    }

    public var description: String { "AppDidEnterBackgroundEvent" }
}
