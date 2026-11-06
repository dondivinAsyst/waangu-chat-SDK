//
//  CapabilityNegotiator.swift
//  CoreKit
//
//  Negotiates capabilities between client and server with version compatibility

import Foundation

public actor CapabilityNegotiator {
    
    public static let shared = CapabilityNegotiator()
    
    private var serverCapabilities: ServerCapabilities?
    private var negotiatedFeatures: Set<Feature> = []
    private var featureFlags: [String: Bool] = [:]
    
    private init() {}
    
    // MARK: - Negotiation
    
    public func negotiate(
        clientVersion: String,
        serverCapabilities: ServerCapabilities
    ) async -> NegotiationResult {
        
        self.serverCapabilities = serverCapabilities
        
        // Parse versions
        guard let clientVer = parseVersion(clientVersion),
              let serverVer = parseVersion(serverCapabilities.minClientVersion) else {
            return NegotiationResult(
                compatible: false,
                availableFeatures: [],
                degradedFeatures: [],
                reason: "Invalid version format"
            )
        }
        
        // Check compatibility
        guard clientVer >= serverVer else {
            return NegotiationResult(
                compatible: false,
                availableFeatures: [],
                degradedFeatures: [],
                reason: "Client version \(clientVersion) is below minimum required \(serverCapabilities.minClientVersion)"
            )
        }
        
        // Negotiate features
        var available: Set<Feature> = []
        var degraded: Set<Feature> = []
        
        for feature in Feature.allCases {
            let requirement = getFeatureRequirement(feature)
            
            if serverCapabilities.supportedFeatures.contains(feature.rawValue) {
                if clientVer >= requirement.minVersion {
                    available.insert(feature)
                } else {
                    degraded.insert(feature)
                }
            }
        }
        
        negotiatedFeatures = available
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "capability_negotiation",
                "client_version": clientVersion,
                "server_version": serverCapabilities.version,
                "available_features": String(available.count),
                "degraded_features": String(degraded.count)
            ],
            severity: .info
        )
        
        return NegotiationResult(
            compatible: true,
            availableFeatures: Array(available),
            degradedFeatures: Array(degraded),
            reason: nil
        )
    }
    
    // MARK: - Feature Checks
    
    public func isFeatureAvailable(_ feature: Feature) -> Bool {
        negotiatedFeatures.contains(feature)
    }
    
    public func requireFeature(_ feature: Feature) throws {
        guard negotiatedFeatures.contains(feature) else {
            throw CapabilityError.featureNotAvailable(feature: feature)
        }
    }
    
    public func getAvailableFeatures() -> Set<Feature> {
        negotiatedFeatures
    }
    
    // MARK: - Feature Flags
    
    public func setFeatureFlag(_ flag: String, enabled: Bool) {
        featureFlags[flag] = enabled
    }
    
    public func isFeatureFlagEnabled(_ flag: String) -> Bool {
        featureFlags[flag] ?? false
    }
    
    // MARK: - Graceful Degradation
    
    public func getFallbackStrategy(for feature: Feature) -> FallbackStrategy {
        switch feature {
        case .voiceMessages:
            return .disable(message: "Voice messages not supported. Please update the app.")
            
        case .endToEndEncryption:
            return .warn(message: "End-to-end encryption not available. Messages will be less secure.")
            
        case .multiDeviceSync:
            return .disable(message: "Multi-device sync not supported. Please update the app.")
            
        case .aiTranslation:
            return .fallback(
                alternative: .basicTranslation,
                message: "AI translation not available. Using basic translation."
            )
            
        case .basicTranslation:
            return .disable(message: "Translation not supported. Please update the app.")
            
        case .stories:
            return .disable(message: "Stories feature not supported. Please update the app.")
            
        case .videoCalls:
            return .fallback(
                alternative: .voiceCalls,
                message: "Video calls not available. Voice calls only."
            )
            
        case .voiceCalls:
            return .disable(message: "Voice calls not supported. Please update the app.")
            
        case .groupCalls:
            return .disable(message: "Group calls not supported. Please update the app.")
            
        case .liveLocation:
            return .fallback(
                alternative: .staticLocation,
                message: "Live location not available. Sending static location."
            )
            
        case .staticLocation:
            return .disable(message: "Location sharing not supported. Please update the app.")
            
        case .messageReactions:
            return .disable(message: "Message reactions not supported.")
            
        case .polls:
            return .disable(message: "Polls not supported. Please update the app.")
        }
    }
    
    // MARK: - Version Compatibility
    
    private func parseVersion(_ version: String) -> Version? {
        let components = version.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }
        
        return Version(
            major: components[0],
            minor: components[1],
            patch: components.count > 2 ? components[2] : 0
        )
    }
    
    private func getFeatureRequirement(_ feature: Feature) -> FeatureRequirement {
        switch feature {
        case .voiceMessages:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 0, patch: 0))
        case .endToEndEncryption:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 1, patch: 0))
        case .multiDeviceSync:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 2, patch: 0))
        case .aiTranslation:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 3, patch: 0))
        case .basicTranslation:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 0, patch: 0))
        case .stories:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 0, patch: 0))
        case .videoCalls:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 1, patch: 0))
        case .voiceCalls:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 0, patch: 0))
        case .groupCalls:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 2, patch: 0))
        case .liveLocation:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 1, patch: 0))
        case .staticLocation:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 0, patch: 0))
        case .messageReactions:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 0, patch: 0))
        case .polls:
            return FeatureRequirement(minVersion: Version(major: 1, minor: 2, patch: 0))
        }
    }
    
    // MARK: - Types
    
    public struct Version: Comparable {
        let major: Int
        let minor: Int
        let patch: Int
        
        public static func < (lhs: Version, rhs: Version) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }
    
    public struct ServerCapabilities: Codable {
        public let version: String
        public let minClientVersion: String
        public let supportedFeatures: [String]
        public let experimentalFeatures: [String]
        
        public init(version: String, minClientVersion: String, supportedFeatures: [String], experimentalFeatures: [String] = []) {
            self.version = version
            self.minClientVersion = minClientVersion
            self.supportedFeatures = supportedFeatures
            self.experimentalFeatures = experimentalFeatures
        }
    }
    
    public enum Feature: String, CaseIterable, Codable {
        case voiceMessages
        case endToEndEncryption
        case multiDeviceSync
        case aiTranslation
        case basicTranslation
        case stories
        case videoCalls
        case voiceCalls
        case groupCalls
        case liveLocation
        case staticLocation
        case messageReactions
        case polls
    }
    
    public struct FeatureRequirement {
        let minVersion: Version
    }
    
    public struct NegotiationResult {
        public let compatible: Bool
        public let availableFeatures: [Feature]
        public let degradedFeatures: [Feature]
        public let reason: String?
    }
    
    public enum FallbackStrategy {
        case disable(message: String)
        case warn(message: String)
        case fallback(alternative: Feature, message: String)
        
        case basicTranslation
        case voiceCalls
        case staticLocation
    }
    
    public enum CapabilityError: Error, LocalizedError {
        case featureNotAvailable(feature: Feature)
        case incompatibleVersion(client: String, required: String)
        
        public var errorDescription: String? {
            switch self {
            case .featureNotAvailable(let feature):
                return "Feature not available: \(feature.rawValue)"
            case .incompatibleVersion(let client, let required):
                return "Incompatible version: \(client) (required: \(required))"
            }
        }
    }
}
