//
//  CallMediaSignalingBridge.swift
//  FeatureChat
//
//  The media engine knows nothing about MQTT, and the signaling repository knows
//  nothing about transports. This binds the two for the lifetime of one room.
//

import Foundation
import WaanguCoreKit

/// Immutable and therefore safe to hand to the engine, which calls back from
/// WebRTC's own threads.
final class CallMediaSignalingBridge: CallMediaSignalingDelegate {

    private let roomId: String
    private let signaling: any CallSignalingRepositoryProtocol

    init(roomId: String, signaling: any CallSignalingRepositoryProtocol) {
        self.roomId = roomId
        self.signaling = signaling
    }

    func connectTransport(id: String, dtlsParameters: String) async throws {
        try await signaling.sendIce(
            roomId: roomId,
            transportId: id,
            dtlsParameters: dtlsParameters
        )
    }

    func produce(
        transportId: String,
        kind: CallMediaKind,
        mediaType: CallMediaType,
        rtpParameters: String
    ) async throws -> String {
        try await signaling.sendProduce(
            roomId: roomId,
            transportId: transportId,
            kind: kind,
            mediaType: mediaType,
            rtpParameters: rtpParameters
        )
    }
}
