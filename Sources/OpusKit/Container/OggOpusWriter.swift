import Foundation
import ogg

/// Writes Opus packets into an Ogg container format
/// This creates standard .opus files that are playable by any Opus-compatible player
public class OggOpusWriter {
    
    private var streamState: ogg_stream_state
    private var page: ogg_page
    private var packet: ogg_packet
    
    private var serialNumber: Int32
    private var granulePosition: Int64 = 0
    private var packetCount: Int64 = 0
    
    private let sampleRate: Int
    private let channels: Int
    private var outputData: Data
    
    // MARK: - Initialization
    
    public init(sampleRate: Int = 48000, channels: Int = 1) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.serialNumber = Int32.random(in: 0...Int32.max)
        self.outputData = Data()
        
        // Initialize Ogg structures
        self.streamState = ogg_stream_state()
        self.page = ogg_page()
        self.packet = ogg_packet()
        
        // Initialize stream
        let result = ogg_stream_init(&streamState, serialNumber)
        guard result == 0 else {
            throw OpusError.encodingFailed(reason: "Failed to initialize Ogg stream")
        }
        
        // Write Ogg Opus header
        try writeOpusHeader()
        
        // Write Ogg Opus comment header
        try writeOpusComments()
    }
    
    deinit {
        ogg_stream_clear(&streamState)
    }
    
    // MARK: - Public Methods
    
    /// Add an Opus packet to the Ogg stream
    public func writePacket(_ opusData: Data, samples: Int) throws {
        let packetData = opusData  // Copy to avoid overlapping access
        
        try packetData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                throw OpusError.encodingFailed(reason: "Failed to get packet data pointer")
            }
            
            // Update granule position (cumulative sample count)
            granulePosition += Int64(samples)
            
            // Setup packet
            var mutablePacket = packet
            mutablePacket.packet = UnsafeMutablePointer(mutating: baseAddress.assumingMemoryBound(to: UInt8.self))
            mutablePacket.bytes = packetData.count
            mutablePacket.b_o_s = 0  // Not beginning of stream
            mutablePacket.e_o_s = 0  // Not end of stream
            mutablePacket.granulepos = granulePosition
            mutablePacket.packetno = packetCount
            
            packetCount += 1
            
            // Submit packet to stream
            let result = ogg_stream_packetin(&streamState, &mutablePacket)
            guard result == 0 else {
                throw OpusError.encodingFailed(reason: "Failed to add packet to Ogg stream")
            }
            
            // Write out pages
            try flushPages(force: false)
        }
    }
    
    /// Finalize the Ogg stream and return the complete file data
    public func finalize() throws -> Data {
        // Mark end of stream
        packet.e_o_s = 1
        
        // Flush remaining pages
        try flushPages(force: true)
        
        return outputData
    }
    
    /// Get the actual audio duration in seconds based on samples
    public func getActualDuration() -> TimeInterval {
        // Duration = total samples / sample rate
        return Double(granulePosition) / Double(sampleRate)
    }
    
    // MARK: - Private Methods
    
    private func writeOpusHeader() throws {
        // OpusHead structure (19 bytes)
        var header = Data()
        
        // Magic signature "OpusHead" (8 bytes)
        header.append(contentsOf: "OpusHead".utf8)
        
        // Version (1 byte) - must be 1
        header.append(1)
        
        // Channel count (1 byte)
        header.append(UInt8(channels))
        
        // Pre-skip (2 bytes, little-endian) - number of samples to skip at start
        let preSkip: UInt16 = 3840  // Standard pre-skip for 48kHz
        header.append(UInt8(preSkip & 0xFF))
        header.append(UInt8((preSkip >> 8) & 0xFF))
        
        // Input sample rate (4 bytes, little-endian)
        let rate = UInt32(sampleRate)
        header.append(UInt8(rate & 0xFF))
        header.append(UInt8((rate >> 8) & 0xFF))
        header.append(UInt8((rate >> 16) & 0xFF))
        header.append(UInt8((rate >> 24) & 0xFF))
        
        // Output gain (2 bytes, little-endian) - 0 dB
        header.append(0)
        header.append(0)
        
        // Channel mapping family (1 byte) - 0 for mono/stereo
        header.append(0)
        
        // Write as first packet
        let headerCopy = header  // Copy to avoid overlapping access
        try headerCopy.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                throw OpusError.encodingFailed(reason: "Failed to get header data pointer")
            }
            
            var mutablePacket = packet
            mutablePacket.packet = UnsafeMutablePointer(mutating: baseAddress.assumingMemoryBound(to: UInt8.self))
            mutablePacket.bytes = headerCopy.count
            mutablePacket.b_o_s = 1  // Beginning of stream
            mutablePacket.e_o_s = 0
            mutablePacket.granulepos = 0
            mutablePacket.packetno = 0
            
            let result = ogg_stream_packetin(&streamState, &mutablePacket)
            guard result == 0 else {
                throw OpusError.encodingFailed(reason: "Failed to write Opus header")
            }
            
            try flushPages(force: true)
        }
    }
    
    private func writeOpusComments() throws {
        // OpusTags structure
        var comments = Data()
        
        // Magic signature "OpusTags" (8 bytes)
        comments.append(contentsOf: "OpusTags".utf8)
        
        // Vendor string
        let vendor = "OpusKit"
        let vendorLength = UInt32(vendor.count)
        
        // Vendor string length (4 bytes, little-endian)
        comments.append(UInt8(vendorLength & 0xFF))
        comments.append(UInt8((vendorLength >> 8) & 0xFF))
        comments.append(UInt8((vendorLength >> 16) & 0xFF))
        comments.append(UInt8((vendorLength >> 24) & 0xFF))
        
        // Vendor string
        comments.append(contentsOf: vendor.utf8)
        
        // User comment list length (4 bytes) - 0 comments
        comments.append(0)
        comments.append(0)
        comments.append(0)
        comments.append(0)
        
        // Write as second packet
        let commentsCopy = comments  // Copy to avoid overlapping access
        try commentsCopy.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                throw OpusError.encodingFailed(reason: "Failed to get comments data pointer")
            }
            
            var mutablePacket = packet
            mutablePacket.packet = UnsafeMutablePointer(mutating: baseAddress.assumingMemoryBound(to: UInt8.self))
            mutablePacket.bytes = commentsCopy.count
            mutablePacket.b_o_s = 0
            mutablePacket.e_o_s = 0
            mutablePacket.granulepos = 0
            mutablePacket.packetno = 1
            
            let result = ogg_stream_packetin(&streamState, &mutablePacket)
            guard result == 0 else {
                throw OpusError.encodingFailed(reason: "Failed to write Opus comments")
            }
            
            try flushPages(force: true)
        }
        
        packetCount = 2  // Header and comments
    }
    
    private func flushPages(force: Bool) throws {
        while true {
            let result: Int32
            if force {
                result = ogg_stream_flush(&streamState, &page)
            } else {
                result = ogg_stream_pageout(&streamState, &page)
            }
            
            if result == 0 {
                break  // No more pages
            }
            
            // Write page header
            if let header = page.header {
                let headerData = Data(bytes: header, count: Int(page.header_len))
                outputData.append(headerData)
            }
            
            // Write page body
            if let body = page.body {
                let bodyData = Data(bytes: body, count: Int(page.body_len))
                outputData.append(bodyData)
            }
        }
    }
}
