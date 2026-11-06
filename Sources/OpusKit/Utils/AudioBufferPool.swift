import Foundation

/// Pool for reusing audio buffers to reduce allocations
actor AudioBufferPool {
    private var buffers: [Data] = []
    private let maxPoolSize: Int
    private let bufferSize: Int
    
    init(bufferSize: Int = OpusConstants.defaultBufferSize, maxPoolSize: Int = OpusConstants.maxBufferPoolSize) {
        self.bufferSize = bufferSize
        self.maxPoolSize = maxPoolSize
    }
    
    /// Get a buffer from the pool or create a new one
    func acquire() -> Data {
        if let buffer = buffers.popLast() {
            return buffer
        }
        return Data(count: bufferSize)
    }
    
    /// Return a buffer to the pool
    func release(_ buffer: Data) {
        guard buffers.count < maxPoolSize else { return }
        buffers.append(buffer)
    }
    
    /// Clear all buffers from the pool
    func clear() {
        buffers.removeAll()
    }
    
    /// Get current pool size
    var count: Int {
        buffers.count
    }
}
