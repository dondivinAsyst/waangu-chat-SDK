import Foundation
import WaanguCoreKit

public struct RetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    
    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 10.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }
    
    /// Execute operation with exponential backoff retry
    public func execute<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry on last attempt
                if attempt == maxAttempts {
                    break
                }
                
                // Calculate delay with exponential backoff
                let delay = min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                
                debugLog("⚠️ Retry attempt \(attempt)/\(maxAttempts) after \(delay)s delay. Error: \(error)")
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? NSError(domain: "RetryPolicy", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "All retry attempts failed"
        ])
    }
}
