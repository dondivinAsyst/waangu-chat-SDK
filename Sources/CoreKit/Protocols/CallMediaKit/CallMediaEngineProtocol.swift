//
//  CallMediaEngineProtocol.swift
//  CoreKit
//
//  The contract between a feature that runs calls and whatever ships the media.
//  CallMediaKit implements it on top of Mediasoup/WebRTC; the feature never
//  imports either — same isolation rule as GRDB behind StorageKit.
//
//  Everything the SFU exchanges is raw JSON (ICE parameters, DTLS parameters,
//  RTP parameters). It stays as `String` all the way through: the client library
//  parses it, and re-modelling it here would only add a lossy round trip.
//

import Foundation
import CoreVideo
#if canImport(UIKit)
import UIKit
#endif

// ─────────────────────────────────────────────────────────────
// MARK: Value types
// ─────────────────────────────────────────────────────────────

public enum CallMediaKind: String, Sendable, Hashable {
    case audio
    case video
}

/// What a track *is*, as opposed to how the SFU routes it.
///
/// `CallMediaKind` stays `.video` for a screen share — the SFU must treat it as
/// a video track — while this tells peers it is a screen. `CALL-INTEGRATION.md`
/// §9.2 (:634-637) defines the three values the server understands.
public enum CallMediaType: String, Sendable, Hashable {
    case audio
    case video
    case screen
}

/// One transport as the server describes it in `sendTransportOptions` /
/// `recvTransportOptions`.
public struct CallTransportOptions: Sendable, Hashable {
    public let id: String
    /// JSON object.
    public let iceParameters: String
    /// JSON array.
    public let iceCandidates: String
    /// JSON object.
    public let dtlsParameters: String
    /// JSON object. Absent when the room carries no data channels.
    public let sctpParameters: String?

    public init(
        id: String,
        iceParameters: String,
        iceCandidates: String,
        dtlsParameters: String,
        sctpParameters: String? = nil
    ) {
        self.id = id
        self.iceParameters = iceParameters
        self.iceCandidates = iceCandidates
        self.dtlsParameters = dtlsParameters
        self.sctpParameters = sctpParameters
    }
}

/// The payload of `CALL_OFFER_MEDIA` (initiator) or `CALL_MEDIA_ANSWER`
/// (joiner). Both carry the same three things.
public struct CallMediaSetup: Sendable, Hashable {
    /// JSON object — the router's RTP capabilities.
    public let routerRtpCapabilities: String
    public let sendTransport: CallTransportOptions
    public let recvTransport: CallTransportOptions

    public init(
        routerRtpCapabilities: String,
        sendTransport: CallTransportOptions,
        recvTransport: CallTransportOptions
    ) {
        self.routerRtpCapabilities = routerRtpCapabilities
        self.sendTransport = sendTransport
        self.recvTransport = recvTransport
    }
}

/// The payload of `CALL_CONSUMER_CREATED`, answering a `call-consume`.
public struct CallConsumerParameters: Sendable, Hashable {
    public let consumerId: String
    public let producerId: String
    public let kind: CallMediaKind
    /// JSON object.
    public let rtpParameters: String
    /// Whose media this is, when the server names it.
    public let peerId: String?

    public init(
        consumerId: String,
        producerId: String,
        kind: CallMediaKind,
        rtpParameters: String,
        peerId: String? = nil
    ) {
        self.consumerId = consumerId
        self.producerId = producerId
        self.kind = kind
        self.rtpParameters = rtpParameters
        self.peerId = peerId
    }
}

public enum CallMediaError: LocalizedError, Sendable {
    case notStarted
    case alreadyStarted
    case deviceLoadFailed(String)
    case transportCreationFailed(String)
    case produceFailed(String)
    case consumeFailed(String)
    case microphoneUnavailable
    case cameraUnavailable
    case screenShareAlreadyRunning
    case screenShareNotRunning

    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "The media engine is not running."
        case .alreadyStarted:
            return "The media engine is already running."
        case .deviceLoadFailed(let detail):
            return "Could not load the media device: \(detail)"
        case .transportCreationFailed(let detail):
            return "Could not create a media transport: \(detail)"
        case .produceFailed(let detail):
            return "Could not publish media: \(detail)"
        case .consumeFailed(let detail):
            return "Could not receive media: \(detail)"
        case .microphoneUnavailable:
            return "The microphone is unavailable."
        case .cameraUnavailable:
            return "The camera is unavailable."
        case .screenShareAlreadyRunning:
            return "A screen share is already running."
        case .screenShareNotRunning:
            return "No screen share is running."
        }
    }
}

/// An opaque handle on a video track. The feature passes it back to the
/// renderer factory and otherwise treats it as a token.
public protocol CallVideoTrackProtocol: AnyObject, Sendable {
    var trackId: String { get }
    var isEnabled: Bool { get }
}

/// What the engine reports while a call runs.
public enum CallMediaEvent: Sendable {
    /// A remote peer's video became available.
    case remoteVideoTrackAdded(peerId: String?, consumerId: String)
    case remoteVideoTrackRemoved(consumerId: String)
    /// The local camera track was (re)created — the preview should refresh.
    case localVideoTrackChanged
    /// A video call started, or continued, without a camera. The call is live on
    /// audio; the UI should stop showing a self preview that will never fill.
    case localVideoUnavailable
    /// A transport moved to `failed` or `disconnected`; the caller decides
    /// whether to run the `call-reconnect` sequence.
    case transportFailed(transportId: String)
}

// ─────────────────────────────────────────────────────────────
// MARK: Signaling bridge
// ─────────────────────────────────────────────────────────────

/// Two things the SFU client can only get by asking the server mid-handshake.
/// The feature owns the MQTT topics, so it answers on the engine's behalf.
public protocol CallMediaSignalingDelegate: AnyObject, Sendable {

    /// `call-ice` — hand the transport's DTLS parameters to the server and wait
    /// for `CALL_ICE_ANSWER`.
    func connectTransport(id: String, dtlsParameters: String) async throws

    /// `call-produce` — announce a local track. Returns the server-assigned
    /// producer id, which the client library needs to finish `createProducer`.
    ///
    /// `mediaType` is carried separately from `kind` because a screen share is a
    /// video track that peers must render differently (§9.2 :634-637).
    func produce(
        transportId: String,
        kind: CallMediaKind,
        mediaType: CallMediaType,
        rtpParameters: String
    ) async throws -> String
}

// ─────────────────────────────────────────────────────────────
// MARK: Engine
// ─────────────────────────────────────────────────────────────

/// Deliberately *not* main-actor bound.
///
/// Publishing a track is a synchronous call in the SFU client that blocks its
/// calling thread until `CallMediaSignalingDelegate.produce` answers with a
/// producer id. Driving that from the main actor would deadlock the app, so the
/// engine owns its own serial execution context and every entry point is async.
public protocol CallMediaEngineProtocol: AnyObject, Sendable {

    /// Reports what the engine is doing while a call runs. A single consumer is
    /// assumed — the stream is created once, with the engine.
    var events: AsyncStream<CallMediaEvent> { get }

    /// RTP capabilities of this device, needed in every `call-consume`.
    /// Throws while the device has not been loaded by `start`.
    func rtpCapabilities() async throws -> String

    func localVideoTrack() async -> (any CallVideoTrackProtocol)?

    func videoTrack(forConsumer consumerId: String) async -> (any CallVideoTrackProtocol)?

    /// Opens the local camera for preview before SFU `start`. When the capturer
    /// is already running, `start` reuses it instead of opening the device again.
    func prepareLocalVideoPreview() async throws -> (any CallVideoTrackProtocol)?

    /// Loads the device, creates both transports and publishes the microphone
    /// (plus the camera when `isVideo`).
    func start(
        setup: CallMediaSetup,
        isVideo: Bool,
        signaling: any CallMediaSignalingDelegate
    ) async throws

    /// Attaches a consumer created by the server in response to `call-consume`.
    func receive(consumer: CallConsumerParameters) async throws

    /// How loudly each remote peer is currently speaking, keyed by consumer id.
    ///
    /// Read from the receiver's own RTP statistics, so it reflects the audio
    /// actually arriving rather than anything the UI infers. Values are `0…1`;
    /// a consumer that reports no level is absent rather than zero, so callers
    /// can tell "silent" from "not measured yet".
    ///
    /// Polled — there is no callback for this in the SFU client — so callers
    /// should ask at a rate they are willing to pay for.
    func remoteAudioLevels() async -> [String: Float]

    /// How loudly this device is speaking, `0…1`, or nil when not measured.
    func localAudioLevel() async -> Float?

    /// Cumulative bytes received on each open consumer, keyed by consumer id.
    ///
    /// The only way to tell a peer whose media has stalled from one who is
    /// simply silent or still: a peer that loses the network keeps its consumer,
    /// its track and its last decoded frame, so nothing in the media graph
    /// changes and no event fires — but this counter stops advancing.
    ///
    /// Monotonic per consumer for as long as it stays open. A consumer that is
    /// closed or that reports no counter is absent rather than zero, so callers
    /// can tell "no bytes yet" from "gone".
    ///
    /// Polled, like `remoteAudioLevels()` — the SFU client offers no callback.
    func remoteInboundBytes() async -> [String: UInt64]

    /// Creates the screen video track and produces it as `mediaType: .screen`.
    /// Throws `CallMediaError.screenShareAlreadyRunning` if one is live.
    func startScreenShare() async throws

    /// Closes the screen producer and releases its track. Safe to call when no
    /// share is running — teardown paths call it unconditionally.
    func stopScreenShare() async

    /// Feeds one relayed frame into the screen source. Dropped silently when no
    /// share is running: frames and lifecycle arrive on different channels and
    /// can legitimately race at the edges.
    func submitScreenFrame(
        _ pixelBuffer: CVPixelBuffer,
        rotation: Int,
        timestampNanos: UInt64
    ) async

    /// Forwarded from CallKit's `didActivate` / `didDeactivate` audio session.
    /// CallKit owns the session during a call; the media stack must be told
    /// rather than configuring the session behind its back.
    func setAudioSessionActivated(_ isActivated: Bool) async

    /// Speaker on, or back to the earpiece.
    ///
    /// The engine owns this rather than the feature because the output override
    /// has to be taken under the same lock as the rest of the media stack's
    /// audio configuration; setting it on `AVAudioSession` directly races the
    /// audio unit and is silently dropped.
    func setSpeakerEnabled(_ isEnabled: Bool) async throws

    func setMicrophoneEnabled(_ isEnabled: Bool) async

    /// Starts capture the first time it is enabled — an audio call upgraded to
    /// video has no camera track yet.
    func setCameraEnabled(_ isEnabled: Bool) async throws

    func switchCamera() async throws

    /// Closes producers, consumers and transports and releases the capture
    /// devices. Safe to call more than once.
    func stop() async
}

// ─────────────────────────────────────────────────────────────
// MARK: Rendering
// ─────────────────────────────────────────────────────────────

#if canImport(UIKit)
/// Builds the platform view for a track. Lives behind a protocol so the feature
/// can render video without linking WebRTC.
@MainActor
public protocol CallVideoRendererFactoryProtocol {
    /// - Parameters:
    ///   - mirrored: true for the local front camera preview.
    ///   - fillsBounds: aspect-fill when true, aspect-fit when false.
    func makeVideoView(
        for track: any CallVideoTrackProtocol,
        mirrored: Bool,
        fillsBounds: Bool
    ) -> UIView

    /// A surface that keeps rendering while the app is backgrounded.
    ///
    /// `makeVideoView` returns a Metal-backed view, and iOS suspends Metal
    /// rendering for a backgrounded app — so it freezes on its last frame
    /// exactly when Picture-in-Picture is the only thing on screen. This one is
    /// composited by the system instead, which is what PiP requires.
    ///
    /// Only for PiP: it is heavier than the inline view, which stays correct and
    /// faster in the foreground.
    func makePictureInPictureView(
        for track: any CallVideoTrackProtocol
    ) -> UIView
}
#endif
