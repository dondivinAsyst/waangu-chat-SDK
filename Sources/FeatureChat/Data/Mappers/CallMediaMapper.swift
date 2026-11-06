//
//  CallMediaMapper.swift
//  FeatureChat
//
//  Turns the SFU setup events into the CoreKit contracts the media engine
//  consumes. `CALL_OFFER_MEDIA` (initiator) and `CALL_MEDIA_ANSWER` (joiner)
//  carry the same three things, so one mapper covers both.
//

import Foundation
import WaanguCoreKit

enum CallMediaMapper {

    // MARK: - Setup

    /// Returns nil when the event is missing a transport or the router
    /// capabilities — starting the engine on half a setup would fail later and
    /// further from the cause.
    static func setup(from event: InboundCallEventDTO) -> CallMediaSetup? {
        let routerCapabilities = event.rawJSON("rtpCapabilities")
        let sendOptions = event.payload["sendTransportOptions"] as? [String: Any]
        let recvOptions = event.payload["recvTransportOptions"] as? [String: Any]
        let send = sendOptions.flatMap(transportOptions(from:))
        let receive = recvOptions.flatMap(transportOptions(from:))

        guard
            let routerCapabilities,
            let sendOptions, let recvOptions,
            let send, let receive
        else {
            #if DEBUG
            // Naming the missing piece: the three payloads are shaped alike, so
            // "setup missing" alone never said whether the server omitted a
            // field or sent it under a different name.
            print("""
            [CallMedia] setup rejected from \(event.eventType) — \
            rtpCapabilities=\(routerCapabilities != nil) \
            sendTransportOptions=\(sendOptions != nil) (readable=\(send != nil)) \
            recvTransportOptions=\(recvOptions != nil) (readable=\(receive != nil))
            """)
            #endif
            return nil
        }

        return CallMediaSetup(
            routerRtpCapabilities: routerCapabilities,
            sendTransport: send,
            recvTransport: receive
        )
    }

    static func transportOptions(from object: [String: Any]) -> CallTransportOptions? {
        guard
            let id = object["id"] as? String,
            let iceParameters = json(object["iceParameters"]),
            let iceCandidates = json(object["iceCandidates"]),
            let dtlsParameters = json(object["dtlsParameters"])
        else { return nil }

        return CallTransportOptions(
            id: id,
            iceParameters: iceParameters,
            iceCandidates: iceCandidates,
            dtlsParameters: dtlsParameters,
            // Absent whenever the room carries no data channels.
            sctpParameters: json(object["sctpParameters"])
        )
    }

    // MARK: - Consumers

    /// Reads `CALL_CONSUMER_CREATED`. The parameters may sit at the top level or
    /// under a `consumer` key depending on the event.
    static func consumerParameters(from event: InboundCallEventDTO) -> CallConsumerParameters? {
        let source: [String: Any] = (event.payload["consumer"] as? [String: Any]) ?? event.payload

        guard
            let consumerId = source["consumerId"] as? String ?? source["id"] as? String,
            let producerId = source["producerId"] as? String,
            let rtpParameters = json(source["rtpParameters"])
        else { return nil }

        // Audio is the safe default: a consumer with an unreadable kind still
        // carries sound, and mis-tagging it as video would create a track the
        // grid renders as a black tile.
        let kind: CallMediaKind = (source["kind"] as? String)?.lowercased() == "video"
            ? .video
            : .audio

        return CallConsumerParameters(
            consumerId: consumerId,
            producerId: producerId,
            kind: kind,
            rtpParameters: rtpParameters,
            peerId: source["peerId"] as? String ?? event.peerId
        )
    }

    // MARK: - Helpers

    /// Serialises a nested JSON object or array back to a string.
    private static func json(_ value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
