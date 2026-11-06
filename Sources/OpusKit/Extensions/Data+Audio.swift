import Foundation

extension Data {
    /// Convert PCM Int16 data to Float32
    func pcmInt16ToFloat32() -> Data {
        var floatData = Data(count: self.count * 2)
        
        self.withUnsafeBytes { (int16Ptr: UnsafeRawBufferPointer) in
            floatData.withUnsafeMutableBytes { (floatPtr: UnsafeMutableRawBufferPointer) in
                let int16Buffer = int16Ptr.bindMemory(to: Int16.self)
                let floatBuffer = floatPtr.bindMemory(to: Float.self)
                
                for i in 0..<int16Buffer.count {
                    floatBuffer[i] = Float(int16Buffer[i]) / Float(Int16.max)
                }
            }
        }
        
        return floatData
    }
    
    /// Convert PCM Float32 data to Int16
    func pcmFloat32ToInt16() -> Data {
        var int16Data = Data(count: self.count / 2)
        
        self.withUnsafeBytes { (floatPtr: UnsafeRawBufferPointer) in
            int16Data.withUnsafeMutableBytes { (int16Ptr: UnsafeMutableRawBufferPointer) in
                let floatBuffer = floatPtr.bindMemory(to: Float.self)
                let int16Buffer = int16Ptr.bindMemory(to: Int16.self)
                
                for i in 0..<floatBuffer.count {
                    let sample = Swift.max(-1.0, Swift.min(1.0, floatBuffer[i]))
                    int16Buffer[i] = Int16(sample * Float(Int16.max))
                }
            }
        }
        
        return int16Data
    }
    
    /// Get audio level (RMS) from PCM data
    func audioLevel() -> Float {
        guard !self.isEmpty else { return 0.0 }
        
        var sum: Float = 0.0
        var count = 0
        
        self.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let int16Buffer = ptr.bindMemory(to: Int16.self)
            for sample in int16Buffer {
                let normalized = Float(sample) / Float(Int16.max)
                sum += normalized * normalized
                count += 1
            }
        }
        
        guard count > 0 else { return 0.0 }
        return sqrt(sum / Float(count))
    }
}
