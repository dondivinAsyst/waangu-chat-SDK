//
//  ScreenFramePacker.swift
//  ScreenShareTransport
//
//  CVPixelBuffer ⇄ wire bytes. Planes are copied row by row because ReplayKit
//  hands back row-padded buffers and the padding must not cross the socket.
//

import Foundation
import CoreVideo

public enum ScreenFramePackerError: Error, Equatable {
    case unsupportedPixelFormat(OSType)
    case lockFailed
    case planeMissing
    case payloadSizeMismatch(expected: Int, actual: Int)
    case allocationFailed(OSStatus)
}

public enum ScreenFramePacker {

    public static let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

    public static func pack(
        _ pixelBuffer: CVPixelBuffer,
        rotation: ScreenFrameRotation,
        timestampNanos: UInt64
    ) throws -> Data {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == pixelFormat else {
            throw ScreenFramePackerError.unsupportedPixelFormat(format)
        }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            throw ScreenFramePackerError.lockFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let luma = try copyPlane(pixelBuffer, index: 0, tightBytesPerRow: width, rows: height)
        let chroma = try copyPlane(pixelBuffer, index: 1, tightBytesPerRow: width, rows: height / 2)

        let header = ScreenFrameHeader(
            width: UInt32(width),
            height: UInt32(height),
            rotation: rotation,
            lumaByteCount: UInt32(luma.count),
            chromaByteCount: UInt32(chroma.count),
            timestampNanos: timestampNanos
        )

        var data = header.encoded()
        data.append(luma)
        data.append(chroma)
        return data
    }

    public static func unpack(header: ScreenFrameHeader, payload: Data) throws -> CVPixelBuffer {
        guard payload.count == header.payloadByteCount else {
            throw ScreenFramePackerError.payloadSizeMismatch(
                expected: header.payloadByteCount,
                actual: payload.count
            )
        }

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(header.width),
            Int(header.height),
            pixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw ScreenFramePackerError.allocationFailed(status)
        }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            throw ScreenFramePackerError.lockFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = Int(header.width)
        try payload.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw ScreenFramePackerError.planeMissing
            }
            try writePlane(
                pixelBuffer, index: 0, from: base,
                tightBytesPerRow: width, rows: Int(header.height)
            )
            try writePlane(
                pixelBuffer, index: 1, from: base + Int(header.lumaByteCount),
                tightBytesPerRow: width, rows: Int(header.height) / 2
            )
        }
        return pixelBuffer
    }

    // MARK: - Plane copies

    private static func copyPlane(
        _ pixelBuffer: CVPixelBuffer,
        index: Int,
        tightBytesPerRow: Int,
        rows: Int
    ) throws -> Data {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, index) else {
            throw ScreenFramePackerError.planeMissing
        }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, index)
        let source = base.assumingMemoryBound(to: UInt8.self)

        var plane = Data(count: tightBytesPerRow * rows)
        plane.withUnsafeMutableBytes { raw in
            guard let destination = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for row in 0..<rows {
                memcpy(
                    destination + row * tightBytesPerRow,
                    source + row * stride,
                    tightBytesPerRow
                )
            }
        }
        return plane
    }

    private static func writePlane(
        _ pixelBuffer: CVPixelBuffer,
        index: Int,
        from source: UnsafePointer<UInt8>,
        tightBytesPerRow: Int,
        rows: Int
    ) throws {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, index) else {
            throw ScreenFramePackerError.planeMissing
        }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, index)
        let destination = base.assumingMemoryBound(to: UInt8.self)
        // Destination advances by its own stride (CoreVideo may pad the rows it
        // just allocated); source advances tightly, because that is how the wire
        // format packs it. Using one for both silently skews the image.
        for row in 0..<rows {
            memcpy(
                destination + row * stride,
                source + row * tightBytesPerRow,
                tightBytesPerRow
            )
        }
    }
}
