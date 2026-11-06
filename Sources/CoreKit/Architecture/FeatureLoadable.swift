//
//  FeatureLoadable.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

import Foundation

public enum FeatureLoadPriority: Sendable {
    case critical   
    case standard
    case onDemand
}

/// Contrat minimal de chaque feature.
/// `load()` est static et async — construction off main thread.
public protocol FeatureLoadable: Sendable {
    associatedtype Dependencies

    static var loadPriority: FeatureLoadPriority { get }

    static func load(dependencies: Dependencies) async throws -> Self
}
