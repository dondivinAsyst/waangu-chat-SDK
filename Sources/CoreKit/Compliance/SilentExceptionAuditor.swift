import Foundation

/// Audits and prevents silent exception handling (try?, silent catch blocks)
/// Ensures all errors are properly logged and handled
public actor SilentExceptionAuditor {
    
    public static let shared = SilentExceptionAuditor()
    
    private var silentExceptions: [SilentException] = []
    private let maxStoredExceptions = 1000
    
    private init() {}
    
    public struct SilentException: Sendable {
        public let location: String
        public let errorDescription: String
        public let timestamp: Date
        public let stackTrace: String
    }
    
    /// Records a silent exception that should have been handled
    public func recordSilentException(
        location: String,
        error: Error,
        stackTrace: String = ""
    ) {
        let exception = SilentException(
            location: location,
            errorDescription: error.localizedDescription,
            timestamp: Date(),
            stackTrace: stackTrace
        )
        
        silentExceptions.append(exception)
        
        // Keep only recent exceptions
        if silentExceptions.count > maxStoredExceptions {
            silentExceptions.removeFirst()
        }
    }
    
    /// Validates that a code path doesn't use try?
    public func validateNoTryOptional(in code: String) -> [String] {
        var violations: [String] = []
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("try?") {
                violations.append("Line \(index + 1): Found 'try?' - use explicit error handling")
            }
        }
        
        return violations
    }
    
    /// Validates that catch blocks are not silent
    public func validateNoCatchSilence(in code: String) -> [String] {
        var violations: [String] = []
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        
        var inCatchBlock = false
        var catchLineNumber = 0
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.starts(with: "catch") {
                inCatchBlock = true
                catchLineNumber = index + 1
            }
            
            if inCatchBlock {
                // Check for empty catch or catch with only comments
                if trimmed == "}" || trimmed.starts(with: "}") {
                    violations.append("Line \(catchLineNumber): Silent catch block - must log or handle error")
                    inCatchBlock = false
                } else if trimmed.starts(with: "//") || trimmed.isEmpty {
                    // Continue checking
                    continue
                } else if !trimmed.contains("print") && 
                          !trimmed.contains("log") && 
                          !trimmed.contains("throw") &&
                          !trimmed.contains("return") {
                    // Catch block exists but might be silent
                    continue
                }
            }
        }
        
        return violations
    }
    
    /// Get all recorded silent exceptions
    public func getAllSilentExceptions() -> [SilentException] {
        silentExceptions
    }
    
    /// Clear audit history
    public func clearHistory() {
        silentExceptions.removeAll()
    }
}
