import Foundation

public actor AmbiguousSuccessGuard {
    
    public static let shared = AmbiguousSuccessGuard()
    
    private var finalStates: [String: FinalState] = [:]
    
    private init() {}
    
    public func validateFinalState(_ state: String, operationId: String) throws {
        let knownFinalStates = ["COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "REJECTED"]
        
        guard knownFinalStates.contains(state.uppercased()) else {
            throw AmbiguousStateError.unknownFinalState(state: state, operationId: operationId)
        }
        
        finalStates[operationId] = FinalState(state: state, timestamp: Date())
    }
    
    public func isFinalStateAmbiguous(_ state: String) -> Bool {
        let ambiguousStates = ["PENDING", "PROCESSING", "WAITING", "UNKNOWN", ""]
        return ambiguousStates.contains(state.uppercased())
    }
    
    public func getFinalState(_ operationId: String) -> FinalState? {
        finalStates[operationId]
    }
}

public struct FinalState: Sendable {
    public let state: String
    public let timestamp: Date
}

public enum AmbiguousStateError: Error {
    case unknownFinalState(state: String, operationId: String)
}
