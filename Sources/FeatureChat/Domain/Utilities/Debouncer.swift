import Foundation

@MainActor
public final class Debouncer {
    private var task: Task<Void, Never>?
    private let delay: TimeInterval
    
    public init(delay: TimeInterval = 2.0) {
        self.delay = delay
    }
    
    /// Debounce an async operation
    public func debounce(operation: @escaping () async -> Void) {
        // Cancel previous task
        task?.cancel()
        
        // Create new task
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Check if cancelled
            guard !Task.isCancelled else { return }
            
            // Execute operation
            await operation()
        }
    }
    
    /// Cancel pending operation
    public func cancel() {
        task?.cancel()
        task = nil
    }
}
