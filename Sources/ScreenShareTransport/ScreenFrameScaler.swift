//
//  ScreenFrameScaler.swift
//  ScreenShareTransport
//
//  vImage NV12 downscale. vImage is used rather than CoreImage because a
//  CIContext costs far more memory than a broadcast extension's 50 MB allows.
//

import Foundation
import CoreVideo
import CoreGraphics
import Accelerate

public enum ScreenFrameScalerError: Error, Equatable {
    case scaleFailed(vImage_Error)
}

public struct ScreenFrameScaler {

    private let maxLongEdge: Int

    public init(maxLongEdge: Int = 1280) {
        precondition(maxLongEdge > 0, "maxLongEdge must be positive")
        self.maxLongEdge = maxLongEdge
    }

    /// Aspect-preserving, never upscaling, always even — NV12 chroma is
    /// half-resolution in both axes, so an odd edge corrupts the plane.
    public func targetSize(for source: CGSize) -> CGSize {
        let longEdge = max(source.width, source.height)
        guard longEdge > CGFloat(maxLongEdge) else {
            return CGSize(width: roundToEven(source.width), height: roundToEven(source.height))
        }
        let scale = CGFloat(maxLongEdge) / longEdge
        return CGSize(
            width: roundToEven(source.width * scale),
            height: roundToEven(source.height * scale)
        )
    }

    public func scale(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let target = targetSize(for: CGSize(width: sourceWidth, height: sourceHeight))
        let targetWidth = Int(target.width)
        let targetHeight = Int(target.height)

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            throw ScreenFramePackerError.lockFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, targetWidth, targetHeight,
            ScreenFramePacker.pixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &destination
        )
        guard status == kCVReturnSuccess, let output = destination else {
            throw ScreenFramePackerError.allocationFailed(status)
        }

        guard CVPixelBufferLockBaseAddress(output, []) == kCVReturnSuccess else {
            throw ScreenFramePackerError.lockFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        // Plane 0: 8-bit luma at full resolution.
        var sourceLuma = try buffer(pixelBuffer, plane: 0, width: sourceWidth, height: sourceHeight)
        var targetLuma = try buffer(output, plane: 0, width: targetWidth, height: targetHeight)
        let lumaError = vImageScale_Planar8(
            &sourceLuma, &targetLuma, nil, vImage_Flags(kvImageHighQualityResampling)
        )
        guard lumaError == kvImageNoError else {
            throw ScreenFrameScalerError.scaleFailed(lumaError)
        }

        // Plane 1: interleaved Cb/Cr at half resolution in both axes. Widths are
        // halved because vImageScale_CbCr8 counts pixel pairs, not bytes.
        var sourceChroma = try buffer(
            pixelBuffer, plane: 1, width: sourceWidth / 2, height: sourceHeight / 2
        )
        var targetChroma = try buffer(
            output, plane: 1, width: targetWidth / 2, height: targetHeight / 2
        )
        let chromaError = vImageScale_CbCr8(
            &sourceChroma, &targetChroma, nil, vImage_Flags(kvImageHighQualityResampling)
        )
        guard chromaError == kvImageNoError else {
            throw ScreenFrameScalerError.scaleFailed(chromaError)
        }

        return output
    }

    private func buffer(
        _ pixelBuffer: CVPixelBuffer,
        plane: Int,
        width: Int,
        height: Int
    ) throws -> vImage_Buffer {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
            throw ScreenFramePackerError.planeMissing
        }
        return vImage_Buffer(
            data: base,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
        )
    }

    /// Nearest *even* value, not "nearest integer then round down".
    ///
    /// For a 1170×2532 screen the scaled width is 591.4: truncating down to even
    /// gives 590 and distorts the aspect by 1.4px, while the nearest even is 592
    /// and distorts by 0.6. Both are even — only one keeps the picture square.
    private func roundToEven(_ value: CGFloat) -> CGFloat {
        (value / 2).rounded() * 2
    }
}
