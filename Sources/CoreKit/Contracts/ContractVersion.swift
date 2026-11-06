import Foundation

/// Semantic version for API contracts
/// Ensures client-server compatibility
public struct ContractVersion: Codable, Hashable, Sendable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    
    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    /// Parse version from string (e.g., "1.2.3")
    public init?(string: String) {
        let components = string.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        self.major = components[0]
        self.minor = components[1]
        self.patch = components[2]
    }
    
    /// String representation (e.g., "1.2.3")
    public var stringValue: String {
        "\(major).\(minor).\(patch)"
    }
    
    /// HTTP header name for contract version
    public static let headerName = "X-Contract-Version"
    
    /// Check if this version is compatible with another
    /// Compatible if major versions match and this minor >= other minor
    public func isCompatible(with other: ContractVersion) -> Bool {
        guard major == other.major else { return false }
        return minor >= other.minor
    }
    
    /// Check if this version is a breaking change from another
    public func isBreakingChange(from other: ContractVersion) -> Bool {
        major > other.major
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: ContractVersion, rhs: ContractVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

extension ContractVersion: CustomStringConvertible {
    public var description: String {
        stringValue
    }
}

extension ContractVersion: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let version = ContractVersion(string: value) else {
            fatalError("Invalid version string: \(value)")
        }
        self = version
    }
}

/// Protocol for versioned contracts
public protocol VersionedContract {
    static var contractVersion: ContractVersion { get }
}

/// Contract version registry for tracking supported versions
public final class ContractVersionRegistry {
    public static let shared = ContractVersionRegistry()
    
    private var supportedVersions: [String: Set<ContractVersion>] = [:]
    
    private init() {}
    
    /// Register a supported version for a contract
    public func register(contract: String, version: ContractVersion) {
        if supportedVersions[contract] == nil {
            supportedVersions[contract] = []
        }
        supportedVersions[contract]?.insert(version)
    }
    
    /// Check if a version is supported for a contract
    public func isSupported(contract: String, version: ContractVersion) -> Bool {
        guard let versions = supportedVersions[contract] else { return false }
        return versions.contains { $0.isCompatible(with: version) }
    }
    
    /// Get the latest supported version for a contract
    public func latestVersion(for contract: String) -> ContractVersion? {
        supportedVersions[contract]?.max()
    }
}

/// Current app contract versions
public enum AppContractVersions {
    public static let chat: ContractVersion = "1.0.0"
    public static let messages: ContractVersion = "1.0.0"
    public static let contacts: ContractVersion = "1.0.0"
    public static let media: ContractVersion = "1.0.0"
    public static let e2ee: ContractVersion = "1.0.0"
}
