//
//  ScreenFrameHeader.swift
//  ScreenShareTransport
//
//  Fixed-size, little-endian frame header written ahead of every NV12 payload.
//

import Foundation

/// Display rotation carried as quarter-turns.
///
/// Deliberately not `RTCVideoRotation`: this module is linked by the broadcast
/// extension, which must never pull in WebRTC. `CallMediaKit` maps this across.
public enum ScreenFrameRotation: UInt8, Sendable, CaseIterable {
    case none = 0
    case quarter = 1
    case half = 2
    case threeQuarter = 3

    public var degrees: Int { Int(rawValue) * 90 }
}

public enum ScreenFrameProtocolError: Error, Equatable {
    case truncated
    case badMagic
    case unsupportedVersion(UInt8)
    case badRotation(UInt8)
}

public struct ScreenFrameHeader: Equatable, Sendable {

    /// "WANG" — guards against reading a partially-written or foreign stream.
    public static let magic: UInt32 = 0x5741_4E47
    public static let version: UInt8 = 1
    public static let byteCount = 32

    /// 0 = NV12 (`kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`). The only
    /// format v1 emits; the byte exists so a second one never needs a v2 header.
    public static let pixelFormatNV12: UInt8 = 0

    public let width: UInt32
    public let height: UInt32
    public let rotation: ScreenFrameRotation
    public let lumaByteCount: UInt32
    public let chromaByteCount: UInt32
    public let timestampNanos: UInt64

    public var payloadByteCount: Int { Int(lumaByteCount) + Int(chromaByteCount) }

    public init(
        width: UInt32,
        height: UInt32,
        rotation: ScreenFrameRotation,
        lumaByteCount: UInt32,
        chromaByteCount: UInt32,
        timestampNanos: UInt64
    ) {
        self.width = width
        self.height = height
        self.rotation = rotation
        self.lumaByteCount = lumaByteCount
        self.chromaByteCount = chromaByteCount
        self.timestampNanos = timestampNanos
    }

    public func encoded() -> Data {
        var data = Data(capacity: Self.byteCount)
        data.appendLittleEndian(Self.magic)
        data.append(Self.version)
        data.append(rotation.rawValue)
        data.append(Self.pixelFormatNV12)
        data.append(0) // reserved
        data.appendLittleEndian(width)
        data.appendLittleEndian(height)
        data.appendLittleEndian(lumaByteCount)
        data.appendLittleEndian(chromaByteCount)
        data.appendLittleEndian(timestampNanos)
        return data
    }

    public static func decode(_ data: Data) throws -> ScreenFrameHeader {
        guard data.count >= byteCount else { throw ScreenFrameProtocolError.truncated }
        var reader = ByteReader(data)

        guard reader.readUInt32() == magic else { throw ScreenFrameProtocolError.badMagic }

        let fileVersion = reader.readUInt8()
        guard fileVersion == version else {
            throw ScreenFrameProtocolError.unsupportedVersion(fileVersion)
        }

        let rotationRaw = reader.readUInt8()
        guard let rotation = ScreenFrameRotation(rawValue: rotationRaw) else {
            throw ScreenFrameProtocolError.badRotation(rotationRaw)
        }

        _ = reader.readUInt8() // pixelFormat — only NV12 exists in v1
        _ = reader.readUInt8() // reserved

        return ScreenFrameHeader(
            width: reader.readUInt32(),
            height: reader.readUInt32(),
            rotation: rotation,
            lumaByteCount: reader.readUInt32(),
            chromaByteCount: reader.readUInt32(),
            timestampNanos: reader.readUInt64()
        )
    }
}

// MARK: - Little-endian primitives

private extension Data {
    /// Byte-at-a-time on purpose: inside a `Data` extension the global
    /// `withUnsafeBytes(of:_:)` is shadowed by `Data.withUnsafeBytes`, and
    /// spelling the shifts out mirrors `ByteReader` on the decode side.
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: 0, to: T.bitWidth, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> T(shift)))
        }
    }
}

/// Sequential little-endian reader. Bounds are checked once by the caller
/// before construction, so reads here are total.
private struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) { self.bytes = [UInt8](data) }

    mutating func readUInt8() -> UInt8 {
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt32() -> UInt32 {
        defer { offset += 4 }
        return (0..<4).reduce(UInt32(0)) { acc, i in
            acc | (UInt32(bytes[offset + i]) << (8 * UInt32(i)))
        }
    }

    mutating func readUInt64() -> UInt64 {
        defer { offset += 8 }
        return (0..<8).reduce(UInt64(0)) { acc, i in
            acc | (UInt64(bytes[offset + i]) << (8 * UInt64(i)))
        }
    }
}
