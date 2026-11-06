import Foundation

/// BFF-only pattern enforcement
/// Ensures all backend calls go through BFF layer only, never direct to backend services
public actor BFFGateway {
    
    public static let shared = BFFGateway()
    
    private var bffURL: URL?
    private var bffHostAllowlist: Set<String> = []
    private let enforceFailClosed = true
    
    private init() {}
    
    public func configure(bffURL: URL, allowedHosts: [String] = []) throws {
        guard let host = bffURL.host else {
            throw BFFGatewayError.invalidBFFURL
        }
        
        self.bffURL = bffURL
        self.bffHostAllowlist = Set(allowedHosts)
        self.bffHostAllowlist.insert(host)
    }
    
    /// Validates that a request is destined for BFF, not direct backend
    public func validateBFFDestination(_ urlString: String) throws {
        guard let url = URL(string: urlString),
              let requestHost = url.host else {
            throw BFFGatewayError.invalidURL
        }
        
        guard bffHostAllowlist.contains(requestHost) else {
            throw BFFGatewayError.directBackendCallDetected(host: requestHost)
        }
    }
    
    /// Enforces that only BFF can proxy backend calls
    public func enforceBFFOnlyPattern(for endpoint: String) throws {
        guard !endpoint.contains("/backend/") && 
              !endpoint.contains("/service/") &&
              !endpoint.contains("/direct/") else {
            throw BFFGatewayError.directBackendCallDetected(host: endpoint)
        }
    }
    
    /// Get configured BFF URL
    public func getBFFURL() -> URL? {
        bffURL
    }
}

public enum BFFGatewayError: Error {
    case invalidBFFURL
    case invalidURL
    case directBackendCallDetected(host: String)
    case bffNotConfigured
}
