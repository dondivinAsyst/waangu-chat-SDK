import Foundation
import ogg

/// Reads Opus packets from an Ogg container format
/// Extracts raw Opus audio packets from .opus files for decoding
public class OggOpusReader {
    
    private var syncState: ogg_sync_state
    private var streamState: ogg_stream_state
    private var page: ogg_page
    private var packet: ogg_packet
    
    private var isStreamInitialized = false
    private var streamSerialNumber: Int32 = 0
    
    // MARK: - Initialization
    
    public init() {
        self.syncState = ogg_sync_state()
        self.streamState = ogg_stream_state()
        self.page = ogg_page()
        self.packet = ogg_packet()
        
        ogg_sync_init(&syncState)
    }
    
    deinit {
        if isStreamInitialized {
            ogg_stream_clear(&streamState)
        }
        ogg_sync_clear(&syncState)
    }
    
    // MARK: - Public Methods
    
    /// Read all Opus packets from an Ogg file
    /// Returns array of raw Opus packet data (excluding OpusHead and OpusTags)
    public func readPackets(from fileURL: URL) throws -> [Data] {
        let fileData = try Data(contentsOf: fileURL)
        return try readPackets(from: fileData)
    }
    
    /// Read all Opus packets from Ogg data
    /// Returns array of raw Opus packet data (excluding OpusHead and OpusTags)
    public func readPackets(from oggData: Data) throws -> [Data] {
        var packets: [Data] = []
        var headerPacketCount = 0
        
        // Feed all data to sync state
        try oggData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                throw OpusError.decodingFailed(reason: "Failed to get data pointer")
            }
            
            let buffer = ogg_sync_buffer(&syncState, oggData.count)
            memcpy(buffer, baseAddress, oggData.count)
            let result = ogg_sync_wrote(&syncState, oggData.count)
            
            guard result == 0 else {
                throw OpusError.decodingFailed(reason: "Failed to write to sync buffer")
            }
        }
        
        // Extract all pages and packets
        while ogg_sync_pageout(&syncState, &page) == 1 {
            // Initialize stream on first page
            if !isStreamInitialized {
                streamSerialNumber = ogg_page_serialno(&page)
                let result = ogg_stream_init(&streamState, streamSerialNumber)
                guard result == 0 else {
                    throw OpusError.decodingFailed(reason: "Failed to initialize stream")
                }
                isStreamInitialized = true
            }
            
            // Submit page to stream
            let result = ogg_stream_pagein(&streamState, &page)
            guard result == 0 else {
                throw OpusError.decodingFailed(reason: "Failed to submit page to stream")
            }
            
            // Extract packets from page
            while ogg_stream_packetout(&streamState, &packet) == 1 {
                // Skip header packets (OpusHead and OpusTags)
                if headerPacketCount < 2 {
                    headerPacketCount += 1
                    continue
                }
                
                // Extract raw Opus packet data
                if let packetData = packet.packet {
                    let data = Data(bytes: packetData, count: packet.bytes)
                    packets.append(data)
                }
            }
        }
        
        guard !packets.isEmpty else {
            throw OpusError.decodingFailed(reason: "No Opus packets found in file (found \(headerPacketCount) header packets)")
        }
        
        return packets
    }
    
    /// Extract metadata from Ogg Opus file
    public func readMetadata(from fileURL: URL) throws -> OggOpusMetadata {
        let fileData = try Data(contentsOf: fileURL)
        return try readMetadata(from: fileData)
    }
    
    /// Extract metadata from Ogg Opus data
    public func readMetadata(from oggData: Data) throws -> OggOpusMetadata {
        // Create a fresh sync/stream state for metadata reading
        var metaSyncState = ogg_sync_state()
        var metaStreamState = ogg_stream_state()
        var metaPage = ogg_page()
        var metaPacket = ogg_packet()
        var metaStreamInitialized = false
        
        ogg_sync_init(&metaSyncState)
        
        defer {
            if metaStreamInitialized {
                ogg_stream_clear(&metaStreamState)
            }
            ogg_sync_clear(&metaSyncState)
        }
        
        var metadata = OggOpusMetadata()
        var headerFound = false
        
        // Feed all data to sync state
        try oggData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                throw OpusError.decodingFailed(reason: "Failed to get data pointer")
            }
            
            let buffer = ogg_sync_buffer(&metaSyncState, oggData.count)
            memcpy(buffer, baseAddress, oggData.count)
            _ = ogg_sync_wrote(&metaSyncState, oggData.count)
        }
        
        // Get first page
        if ogg_sync_pageout(&metaSyncState, &metaPage) == 1 {
            let serialNo = ogg_page_serialno(&metaPage)
            let result = ogg_stream_init(&metaStreamState, serialNo)
            guard result == 0 else {
                throw OpusError.decodingFailed(reason: "Failed to initialize metadata stream")
            }
            metaStreamInitialized = true
            
            _ = ogg_stream_pagein(&metaStreamState, &metaPage)
            
            // Get OpusHead packet
            if ogg_stream_packetout(&metaStreamState, &metaPacket) == 1 {
                if let packetData = metaPacket.packet {
                    let data = Data(bytes: packetData, count: metaPacket.bytes)
                    
                    // Parse OpusHead
                    if data.count >= 19 {
                        let signature = String(data: data.subdata(in: 0..<8), encoding: .utf8)
                        if signature == "OpusHead" {
                            metadata.version = data[8]
                            metadata.channels = Int(data[9])
                            
                            let preSkip = UInt16(data[10]) | (UInt16(data[11]) << 8)
                            metadata.preSkip = Int(preSkip)
                            
                            let sampleRate = UInt32(data[12]) | (UInt32(data[13]) << 8) | 
                                           (UInt32(data[14]) << 16) | (UInt32(data[15]) << 24)
                            metadata.sampleRate = Int(sampleRate)
                            
                            headerFound = true
                        }
                    }
                }
            }
        }
        
        guard headerFound else {
            throw OpusError.decodingFailed(reason: "Invalid Ogg Opus file - OpusHead not found (file size: \(oggData.count) bytes)")
        }
        
        return metadata
    }
}

// MARK: - Metadata Structure

public struct OggOpusMetadata {
    public var version: UInt8 = 0
    public var channels: Int = 1
    public var preSkip: Int = 0
    public var sampleRate: Int = 48000
    public var outputGain: Int16 = 0
    public var channelMappingFamily: UInt8 = 0
}
