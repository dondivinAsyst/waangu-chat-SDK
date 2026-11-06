import Foundation

public actor AllowedHostsPolicy {
    
    public static let shared = AllowedHostsPolicy()
    
    private var allowedHosts: Set<String> = []
    private let failClosed = true
    
    private init() {}
    
    public func setAllowedHosts(_ hosts: [String]) {
        allowedHosts = Set(hosts)
    }
    
    public func isHostAllowed(_ host: String) throws -> Bool {
        guard !failClosed || !allowedHosts.isEmpty else {
            throw HostPolicyError.noAllowedHostsConfigured
        }
        
        guard allowedHosts.contains(host) else {
            throw HostPolicyError.hostNotAllowed(host: host)
        }
        
        return true
    }
    
    public func validateURL(_ urlString: String) throws {
        guard let url = URL(string: urlString),
              let host = url.host else {
            throw HostPolicyError.invalidURL(url: urlString)
        }
        
        _ = try isHostAllowed(host)
    }
}

public enum HostPolicyError: Error {
    case noAllowedHostsConfigured
    case hostNotAllowed(host: String)
    case invalidURL(url: String)
}
