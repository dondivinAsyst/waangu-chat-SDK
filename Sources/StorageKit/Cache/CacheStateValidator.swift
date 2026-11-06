import Foundation

public actor CacheStateValidator {
    
    public static let shared = CacheStateValidator()
    
    private var validFinalStates: Set<String> = ["COMPLETED", "FAILED", "CANCELLED"]
    
    private init() {}
    
    public func validateCacheState(_ state: String) throws {
        guard validFinalStates.contains(state.uppercased()) else {
            throw CacheStateError.invalidFinalState(state: state)
        }
    }
    
    public func canBeFinalState(_ state: String) -> Bool {
        validFinalStates.contains(state.uppercased())
    }
}

public enum CacheStateError: Error {
    case invalidFinalState(state: String)
}
