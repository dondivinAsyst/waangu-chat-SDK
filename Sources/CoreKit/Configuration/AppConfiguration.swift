//
//  AppConfiguration.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

import Foundation

// MARK: - AppEnvironment

public enum AppEnvironment: String, Sendable {
    case development
    case staging
    case production
}

// MARK: - AppConfigurationProviding

public protocol AppConfigurationProviding: Sendable {

    var environment: AppEnvironment { get }

    // HTTP
    var baseURL: String { get }
    var basicAuthToken: String { get }
    var chatUrl: String { get }
    var chatUploadUrl: String { get }
    

    // Realtime — transport-agnostique
    var realtimeHost: String { get }
    var realtimePort: UInt16 { get }
    var realtimeUsesTLS: Bool { get }
    /// Optional specialized backend URL for DoctorConsult services.
    var doctorBaseURL: String { get }
    var insuranceUrl: String { get }
    
    var sentryDSN: String { get }
}


public extension AppConfigurationProviding {
    var isDevelopment: Bool { environment == .development }
    var isStaging: Bool     { environment == .staging }
    var isProduction: Bool  { environment == .production }
    /// By default `doctorBaseURL` falls back to `baseURL`.
    var doctorBaseURL: String { baseURL }
}

