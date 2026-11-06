import Foundation

/// Verifies platform parity between iOS, Android, and Web
/// Ensures consistent behavior and features across platforms
public actor PlatformParityChecker {
    
    public static let shared = PlatformParityChecker()
    
    private var platformFeatures: [Platform: Set<String>] = [:]
    private var parityChecks: [ParityCheck] = []
    
    private init() {}
    
    public enum Platform: String, Sendable {
        case ios = "iOS"
        case android = "Android"
        case web = "Web"
    }
    
    public struct ParityCheck: Sendable {
        public let feature: String
        public let platforms: [Platform]
        public let status: ParityStatus
        public let timestamp: Date
    }
    
    public enum ParityStatus: String, Sendable {
        case aligned = "ALIGNED"
        case misaligned = "MISALIGNED"
        case platformSpecific = "PLATFORM_SPECIFIC"
    }
    
    /// Registers a feature for a platform
    public func registerFeature(_ feature: String, for platform: Platform) {
        if platformFeatures[platform] == nil {
            platformFeatures[platform] = Set()
        }
        platformFeatures[platform]?.insert(feature)
    }
    
    /// Checks if a feature is available on all platforms
    public func checkFeatureParity(_ feature: String) -> ParityCheck {
        let platforms = Platform.allCases
        let availablePlatforms = platforms.filter { platform in
            platformFeatures[platform]?.contains(feature) ?? false
        }
        
        let status: ParityStatus
        if availablePlatforms.count == platforms.count {
            status = .aligned
        } else if availablePlatforms.isEmpty {
            status = .misaligned
        } else {
            status = .platformSpecific
        }
        
        let check = ParityCheck(
            feature: feature,
            platforms: availablePlatforms,
            status: status,
            timestamp: Date()
        )
        
        parityChecks.append(check)
        return check
    }
    
    /// Gets all features for a platform
    public func getFeaturesForPlatform(_ platform: Platform) -> [String] {
        Array(platformFeatures[platform] ?? [])
    }
    
    /// Generates parity report
    public func generateParityReport() -> ParityReport {
        var alignedFeatures: [String] = []
        var misalignedFeatures: [String] = []
        var platformSpecificFeatures: [String] = []
        
        let allFeatures = Set(platformFeatures.values.flatMap { $0 })
        
        for feature in allFeatures {
            let check = checkFeatureParity(feature)
            switch check.status {
            case .aligned:
                alignedFeatures.append(feature)
            case .misaligned:
                misalignedFeatures.append(feature)
            case .platformSpecific:
                platformSpecificFeatures.append(feature)
            }
        }
        
        return ParityReport(
            totalFeatures: allFeatures.count,
            alignedFeatures: alignedFeatures,
            misalignedFeatures: misalignedFeatures,
            platformSpecificFeatures: platformSpecificFeatures,
            parityPercentage: allFeatures.isEmpty ? 0 : Double(alignedFeatures.count) / Double(allFeatures.count) * 100,
            generatedAt: Date()
        )
    }
    
    /// Exports parity data as JSON
    public func exportAsJSON() throws -> Data {
        let report = generateParityReport()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}

public struct ParityReport: Codable, Sendable {
    public let totalFeatures: Int
    public let alignedFeatures: [String]
    public let misalignedFeatures: [String]
    public let platformSpecificFeatures: [String]
    public let parityPercentage: Double
    public let generatedAt: Date
}

extension PlatformParityChecker.Platform: CaseIterable {
    public static var allCases: [PlatformParityChecker.Platform] {
        [.ios, .android, .web]
    }
}
