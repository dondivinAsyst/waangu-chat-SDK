//
//  MediasoupCallEngine.swift
//  CallMediaKit
//
//  The only place in the app that talks to Mediasoup and WebRTC.
//
//  Threading
//  ---------
//  `SendTransport.createProducer` is synchronous but the producer id it needs
//  comes from the server: the client library calls `onProduce` and blocks the
//  calling thread on a promise until the callback fires. So:
//
//    * every mediasoup call runs on `queue`, never on the main thread;
//    * `onProduce` answers from a detached `Task`, never on `queue`, or the
//      blocked thread would be waiting on itself.
//

import Foundation
import AVFoundation
import WaanguCoreKit
import Mediasoup
import WebRTC

public final class MediasoupCallEngine: NSObject, CallMediaEngineProtocol, @unchecked Sendable {

    // MARK: - Events

    public let events: AsyncStream<CallMediaEvent>
    private let eventSink: AsyncStream<CallMediaEvent>.Continuation

    // MARK: - Execution

    /// Serial: it both protects the state below and gives the blocking
    /// `createProducer` a thread that is not the main one.
    private let queue = DispatchQueue(label: "com.waangu.callmedia.engine")

    // MARK: - State (queue-confined)

    private let factory: RTCPeerConnectionFactory
    private var device: Device?
    private var sendTransport: SendTransport?
    private var recvTransport: ReceiveTransport?

    private var audioProducer: Producer?
    private var videoProducer: Producer?
    private var consumers: [String: Consumer] = [:]
    private var remoteVideoTracks: [String: MediasoupVideoTrack] = [:]

    private var localAudioTrackRef: RTCAudioTrack?
    private var localVideoTrackRef: RTCVideoTrack?
    private var localVideoHandle: MediasoupVideoTrack?
    private var videoSource: RTCVideoSource?
    private var capturer: RTCCameraVideoCapturer?

    // Screen share runs a second, independent video path on the same send
    // transport: its own source, track and producer. It deliberately does not
    // reuse the camera's — both must be able to exist at once during the
    // pause/produce handover.
    private var screenSource: RTCVideoSource?
    private var screenTrackRef: RTCVideoTrack?
    private var screenProducer: Producer?
    /// Reused across frames; `RTCVideoCapturer` is only an identity token to
    /// `RTCVideoSource` for externally supplied frames, so allocating one per
    /// frame at 15fps would be pure churn.
    private var screenCapturerToken: RTCVideoCapturer?
    private var cameraPosition: AVCaptureDevice.Position = .front
    private var isRunning = false

    /// Which mediaType the produce currently in flight belongs to.
    ///
    /// The transport callback reports only `kind`, and camera and screen are
    /// both `.video` — so without this the SFU cannot be told which is which.
    /// Queue-confined: set immediately before `createProducer`, read in
    /// `onProduce`, which the client library calls synchronously from inside it.
    private var pendingMediaType: CallMediaType = .video

    /// Read from delegate callbacks that arrive on WebRTC's own threads, so it
    /// gets its own lock rather than riding on `queue`.
    private let signalingLock = NSLock()
    private var _signaling: (any CallMediaSignalingDelegate)?
    private var signaling: (any CallMediaSignalingDelegate)? {
        get { signalingLock.lock(); defer { signalingLock.unlock() }; return _signaling }
        set { signalingLock.lock(); _signaling = newValue; signalingLock.unlock() }
    }

    // MARK: - Init

    public override init() {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
        (self.events, self.eventSink) = AsyncStream<CallMediaEvent>.makeStream()
        super.init()

        MediasoupClient.initialize()

        Self.installWebRTCAudioConfiguration()

        // CallKit owns the audio session during a call. Manual mode keeps WebRTC
        // from activating it on its own and fighting CallKit for the route.
        let session = RTCAudioSession.sharedInstance()
        session.useManualAudio = true
        session.isAudioEnabled = false
    }

    /// The category/mode WebRTC applies whenever it brings the VoIP audio unit
    /// up. Setting it here is what lets the rest of the app stop configuring
    /// `AVAudioSession` by hand: WebRTC and CallKit then agree on one shape for
    /// the session instead of overwriting each other's.
    ///
    /// No `.defaultToSpeaker` — a voice call belongs on the earpiece until the
    /// user asks otherwise, which `setSpeakerEnabled` handles.
    private static func installWebRTCAudioConfiguration() {
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = [
            .allowBluetooth,
            .allowBluetoothA2DP,
            .allowAirPlay
        ]
        RTCAudioSessionConfiguration.setWebRTC(configuration)
    }

    // MARK: - Queue bridging

    private func onQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func onQueue(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }

    // MARK: - Lifecycle

    public func start(
        setup: CallMediaSetup,
        isVideo: Bool,
        signaling: any CallMediaSignalingDelegate
    ) async throws {
        try await onQueue { [self] in
            guard !isRunning else { throw CallMediaError.alreadyStarted }
            self.signaling = signaling

            configureAudioSession(isVideo: isVideo)

            // The device must share the peer connection factory that creates the
            // tracks, otherwise producing them fails deep inside libwebrtc.
            let device = Device(pcFactory: factory)
            do {
                try device.load(with: setup.routerRtpCapabilities)
            } catch {
                throw CallMediaError.deviceLoadFailed(Self.describe(error))
            }
            self.device = device

            do {
                let send = try device.createSendTransport(
                    id: setup.sendTransport.id,
                    iceParameters: setup.sendTransport.iceParameters,
                    iceCandidates: setup.sendTransport.iceCandidates,
                    dtlsParameters: setup.sendTransport.dtlsParameters,
                    sctpParameters: setup.sendTransport.sctpParameters,
                    appData: nil
                )
                send.delegate = self
                self.sendTransport = send

                let receive = try device.createReceiveTransport(
                    id: setup.recvTransport.id,
                    iceParameters: setup.recvTransport.iceParameters,
                    iceCandidates: setup.recvTransport.iceCandidates,
                    dtlsParameters: setup.recvTransport.dtlsParameters,
                    sctpParameters: setup.recvTransport.sctpParameters,
                    appData: nil
                )
                receive.delegate = self
                self.recvTransport = receive
            } catch {
                throw CallMediaError.transportCreationFailed(Self.describe(error))
            }

            isRunning = true

            // Audio is the call. If the microphone cannot be published there is
            // nothing worth keeping, so this one is allowed to fail the start.
            try produceAudio()

            // Video is not. A camera that will not open — permission refused, no
            // usable format, hardware busy — used to throw out of `start` and
            // take the working audio producer with it; the caller then saw
            // `isMediaRunning == false` and stopped consuming remote tracks too,
            // so one camera failure produced a call with no media in either
            // direction. Degrade to audio instead and let the call happen.
            if isVideo {
                do {
                    if localVideoTrackRef == nil {
                        try startCapture()
                    }
                    try produceVideo()
                    eventSink.yield(.localVideoTrackChanged)
                } catch {
                    #if DEBUG
                    print("[CallMedia] video unavailable, continuing audio-only: \(Self.describe(error))")
                    #endif
                    capturer?.stopCapture()
                    capturer = nil
                    localVideoTrackRef = nil
                    localVideoHandle = nil
                    videoSource = nil
                    eventSink.yield(.localVideoUnavailable)
                }
            }

            #if DEBUG
            print("[CallMedia] SFU started send=\(setup.sendTransport.id) recv=\(setup.recvTransport.id) video=\(isVideo) audioProducer=\(audioProducer?.id ?? "nil") videoProducer=\(videoProducer?.id ?? "nil")")
            #endif
        }
    }

    public func stop() async {
        await onQueue { [self] in
            // Disable tracks first so the ADM / capturer drop hardware before
            // we tear producers down — otherwise Control Center can keep showing
            // the mic/camera privacy indicators after hangup.
            localAudioTrackRef?.isEnabled = false
            localVideoTrackRef?.isEnabled = false

            capturer?.stopCapture()
            capturer = nil

            audioProducer?.pause()
            videoProducer?.pause()
            audioProducer?.close()
            videoProducer?.close()
            audioProducer = nil
            videoProducer = nil

            consumers.values.forEach { $0.close() }
            consumers.removeAll()
            remoteVideoTracks.removeAll()

            sendTransport?.close()
            sendTransport?.dispose()
            recvTransport?.close()
            recvTransport?.dispose()
            sendTransport = nil
            recvTransport = nil

            device = nil
            localAudioTrackRef = nil
            localVideoTrackRef = nil
            localVideoHandle = nil
            videoSource = nil
            signaling = nil
            isRunning = false

            // Same half of manual audio as CallKit `didDeactivate`: flip the
            // unit off, then tell RTCAudioSession the session is no longer ours.
            // Relying only on CallKit for this left the mic indicator on when
            // deactivate was late or missed.
            let session = RTCAudioSession.sharedInstance()
            session.isAudioEnabled = false
            session.audioSessionDidDeactivate(session.session)

            #if DEBUG
            print("[CallMedia] SFU stopped — audio unit disabled, session deactivated")
            #endif
        }
    }

    // MARK: - Capabilities and tracks

    public func rtpCapabilities() async throws -> String {
        try await onQueue { [self] in
            guard let device, device.isLoaded() else { throw CallMediaError.notStarted }
            return try device.rtpCapabilities()
        }
    }

    public func localVideoTrack() async -> (any CallVideoTrackProtocol)? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.localVideoHandle) }
        }
    }

    public func prepareLocalVideoPreview() async throws -> (any CallVideoTrackProtocol)? {
        try await onQueue { [self] in
            try startCapture()
            eventSink.yield(.localVideoTrackChanged)
            return localVideoHandle
        }
    }

    public func videoTrack(forConsumer consumerId: String) async -> (any CallVideoTrackProtocol)? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.remoteVideoTracks[consumerId]) }
        }
    }

    // MARK: - Producing

    /// Queue-confined.
    private func produceAudio() throws {
        guard let sendTransport else { throw CallMediaError.notStarted }
        let source = factory.audioSource(with: nil)
        let track = factory.audioTrack(with: source, trackId: "mic-\(UUID().lowercasedString)")
        localAudioTrackRef = track
        pendingMediaType = .audio
        do {
            audioProducer = try sendTransport.createProducer(
                for: track,
                encodings: nil,
                codecOptions: nil,
                codec: nil,
                appData: nil
            )
            #if DEBUG
            print("[CallMedia] Produced audio id=\(audioProducer?.id ?? "nil") transport=\(sendTransport.id)")
            #endif
        } catch {
            throw CallMediaError.produceFailed(Self.describe(error))
        }
    }

    /// Queue-confined.
    private func produceVideo() throws {
        guard let sendTransport else { throw CallMediaError.notStarted }
        guard let track = localVideoTrackRef else { throw CallMediaError.cameraUnavailable }
        pendingMediaType = .video
        do {
            videoProducer = try sendTransport.createProducer(
                for: track,
                encodings: nil,
                codecOptions: nil,
                codec: nil,
                appData: nil
            )
            #if DEBUG
            print("[CallMedia] Produced video id=\(videoProducer?.id ?? "nil") transport=\(sendTransport.id)")
            #endif
        } catch {
            throw CallMediaError.produceFailed(Self.describe(error))
        }
    }

    // MARK: - Consuming

    public func receive(consumer parameters: CallConsumerParameters) async throws {
        try await onQueue { [self] in
            guard let recvTransport else { throw CallMediaError.notStarted }
            let consumer: Consumer
            do {
                consumer = try recvTransport.consume(
                    consumerId: parameters.consumerId,
                    producerId: parameters.producerId,
                    kind: parameters.kind == .video ? .video : .audio,
                    rtpParameters: parameters.rtpParameters,
                    appData: nil
                )
            } catch {
                throw CallMediaError.consumeFailed(Self.describe(error))
            }

            consumers[parameters.consumerId] = consumer

            #if DEBUG
            print("[CallMedia] Consumed \(parameters.kind.rawValue) consumer=\(parameters.consumerId) producer=\(parameters.producerId) peer=\(parameters.peerId)")
            #endif

            if parameters.kind == .video, let videoTrack = consumer.track as? RTCVideoTrack {
                remoteVideoTracks[parameters.consumerId] = MediasoupVideoTrack(videoTrack)
                eventSink.yield(
                    .remoteVideoTrackAdded(
                        peerId: parameters.peerId,
                        consumerId: parameters.consumerId
                    )
                )
            }
        }
    }

    // MARK: - Audio levels

    /// Who is talking, straight from each receiver's RTP statistics.
    ///
    /// Paused and closed consumers are skipped: a paused track keeps reporting
    /// its last level, which would leave a muted peer looking like they were
    /// still speaking.
    public func remoteAudioLevels() async -> [String: Float] {
        let levels = try? await onQueue { [self] () -> [String: Float] in
            var result: [String: Float] = [:]
            for (consumerId, consumer) in consumers where consumer.kind == .audio {
                guard !consumer.closed, !consumer.paused else { continue }
                let stats = consumer.stats
                Self.logFirstAudioStats(stats, consumerId: consumerId)
                if let level = Self.audioLevel(fromStatsJSON: stats) {
                    result[consumerId] = level
                }
            }
            return result
        }
        return levels ?? [:]
    }

    /// Prints one raw statistics payload per run, so it can be confirmed that
    /// `audioLevel` is actually reported — and in what range — rather than
    /// assumed. Whether this key is present depends on the WebRTC build behind
    /// the SFU client, and a wrong assumption here fails silently: flat bars and
    /// no error anywhere.
    ///
    /// One sample only. At 8 Hz per consumer this would otherwise bury the log.
    private static func logFirstAudioStats(_ stats: String, consumerId: String) {
        #if DEBUG
        guard !hasLoggedAudioStats else { return }
        hasLoggedAudioStats = true
        print("[CallMedia] audio stats sample consumer=\(consumerId): \(stats)")
        print("[CallMedia] parsed audioLevel=\(String(describing: audioLevel(fromStatsJSON: stats)))")
        #endif
    }

    #if DEBUG
    private nonisolated(unsafe) static var hasLoggedAudioStats = false
    #endif

    public func localAudioLevel() async -> Float? {
        let level = try? await onQueue { [self] () -> Float? in
            guard let audioProducer, !audioProducer.closed, !audioProducer.paused else {
                return nil
            }
            return Self.audioLevel(fromStatsJSON: audioProducer.stats)
        }
        return level ?? nil
    }

    // MARK: - Inbound liveness

    /// Bytes received per consumer, for spotting a peer whose media has stalled.
    ///
    /// Paused consumers are kept here, unlike in `remoteAudioLevels()`: a peer
    /// who muted or turned their camera off pauses the consumer deliberately and
    /// is not in trouble, so their counter must keep being reported (flat, but
    /// present) rather than vanishing and reading as a drop-out. Closed
    /// consumers are gone for real and are skipped.
    public func remoteInboundBytes() async -> [String: UInt64] {
        let counters = try? await onQueue { [self] () -> [String: UInt64] in
            var result: [String: UInt64] = [:]
            for (consumerId, consumer) in consumers {
                guard !consumer.closed else { continue }
                if let bytes = Self.bytesReceived(fromStatsJSON: consumer.stats) {
                    result[consumerId] = bytes
                }
            }
            return result
        }
        return counters ?? [:]
    }

    /// Pulls `bytesReceived` out of a serialised `RTCStatsReport`.
    ///
    /// Structural search, and summed rather than first-match — the same reason
    /// `audioLevel` searches structurally, plus one of its own: a consumer's
    /// report can carry several inbound entries (RTP and RTX), and taking
    /// whichever happened to be enumerated first would make the total jump
    /// around between samples and read as a stall.
    static func bytesReceived(fromStatsJSON json: String) -> UInt64? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return nil }

        var total: UInt64 = 0
        var found = false
        sumBytesReceived(in: root, total: &total, found: &found)
        return found ? total : nil
    }

    private static func sumBytesReceived(in object: Any, total: inout UInt64, found: inout Bool) {
        if let dictionary = object as? [String: Any] {
            if let value = (dictionary["bytesReceived"] as? NSNumber)?.uint64Value {
                total &+= value
                found = true
            }
            for value in dictionary.values {
                sumBytesReceived(in: value, total: &total, found: &found)
            }
            return
        }
        if let array = object as? [Any] {
            for value in array {
                sumBytesReceived(in: value, total: &total, found: &found)
            }
        }
    }

    /// Pulls `audioLevel` out of a serialised `RTCStatsReport`.
    ///
    /// Searched structurally rather than by a fixed path. The report is the
    /// WebRTC stats graph dumped verbatim, and which entry carries the level —
    /// `inbound-rtp`, `media-source`, `track` — moves between WebRTC versions,
    /// so pinning a path would break silently on the next bump.
    static func audioLevel(fromStatsJSON json: String) -> Float? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return audioLevel(in: root)
    }

    private static func audioLevel(in object: Any) -> Float? {
        if let dictionary = object as? [String: Any] {
            if let value = (dictionary["audioLevel"] as? NSNumber)?.floatValue {
                return min(max(value, 0), 1)
            }
            for value in dictionary.values {
                if let found = audioLevel(in: value) { return found }
            }
            return nil
        }
        if let array = object as? [Any] {
            for value in array {
                if let found = audioLevel(in: value) { return found }
            }
        }
        return nil
    }

    // MARK: - Audio session

    public func setAudioSessionActivated(_ isActivated: Bool) async {
        await onQueue {
            let session = RTCAudioSession.sharedInstance()

            // Manual audio mode has two halves and both are required. Telling
            // `RTCAudioSession` that CallKit activated the session out of band is
            // what `RTCAudioSessionActivationDelegate` exists for; without it
            // `isActive` stays false, the VoIP audio unit never starts, and the
            // call is silent in both directions however often `isAudioEnabled`
            // is flipped.
            //
            // `session.session` is `AVAudioSession.sharedInstance()` — the same
            // object CallKit hands to `provider(_:didActivate:)`.
            if isActivated {
                session.audioSessionDidActivate(session.session)
                session.isAudioEnabled = true
            } else {
                // Stop the unit before disowning the session, or WebRTC keeps
                // rendering into one it no longer holds.
                session.isAudioEnabled = false
                session.audioSessionDidDeactivate(session.session)
            }

            #if DEBUG
            print("[CallMedia] audio session activated=\(isActivated) isActive=\(session.isActive)")
            #endif
        }
    }

    /// Earpiece or speaker. Goes through `RTCAudioSession` rather than
    /// `AVAudioSession` so the override takes the same configuration lock WebRTC
    /// uses — an unlocked change races the audio unit and is dropped.
    public func setSpeakerEnabled(_ isEnabled: Bool) async throws {
        try await onQueue {
            let session = RTCAudioSession.sharedInstance()
            session.lockForConfiguration()
            defer { session.unlockForConfiguration() }
            try session.overrideOutputAudioPort(isEnabled ? .speaker : .none)
        }
    }

    /// Queue-confined. Puts the live session into the shape WebRTC expects
    /// before any track exists. Category and mode only — activation is CallKit's.
    ///
    /// Video uses `videoChat` + `.defaultToSpeaker` so the proximity sensor does
    /// not treat the call like a phone held to the ear. Audio stays on
    /// `voiceChat` (earpiece until the user enables speaker).
    private func configureAudioSession(isVideo: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        do {
            let configuration = RTCAudioSessionConfiguration.webRTC()
            configuration.category = AVAudioSession.Category.playAndRecord.rawValue
            if isVideo {
                configuration.mode = AVAudioSession.Mode.videoChat.rawValue
                configuration.categoryOptions = [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .allowAirPlay,
                    .defaultToSpeaker
                ]
            } else {
                configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
                configuration.categoryOptions = [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .allowAirPlay
                ]
            }
            try session.setConfiguration(configuration)
        } catch {
            #if DEBUG
            print("[CallMedia] audio session configuration failed: \(error)")
            #endif
        }
    }

    // MARK: - Local media control

    public func setMicrophoneEnabled(_ isEnabled: Bool) async {
        await onQueue { [self] in
            localAudioTrackRef?.isEnabled = isEnabled
            // Pausing tells the SFU to stop relaying, which saves the other side
            // decoding silence.
            if isEnabled { audioProducer?.resume() } else { audioProducer?.pause() }
        }
    }

    public func setCameraEnabled(_ isEnabled: Bool) async throws {
        try await onQueue { [self] in
            guard isRunning else { throw CallMediaError.notStarted }

            guard isEnabled else {
                capturer?.stopCapture()
                localVideoTrackRef?.isEnabled = false
                videoProducer?.pause()
                return
            }

            if localVideoTrackRef == nil {
                // An audio call upgraded to video: no camera track exists yet.
                try startCapture()
                try produceVideo()
                eventSink.yield(.localVideoTrackChanged)
            } else {
                try startCapture()
                localVideoTrackRef?.isEnabled = true
                videoProducer?.resume()
            }
        }
    }

    public func switchCamera() async throws {
        try await onQueue { [self] in
            guard capturer != nil else { throw CallMediaError.cameraUnavailable }
            cameraPosition = (cameraPosition == .front) ? .back : .front
            capturer?.stopCapture()
            try startCapture()
        }
    }

    // MARK: - Screen share

    public func startScreenShare() async throws {
        try await onQueue { [self] in
            guard isRunning else { throw CallMediaError.notStarted }
            guard screenProducer == nil else {
                throw CallMediaError.screenShareAlreadyRunning
            }
            guard let sendTransport else { throw CallMediaError.notStarted }

            let source = factory.videoSource()
            let track = factory.videoTrack(
                with: source,
                trackId: "screen-\(UUID().lowercasedString)"
            )
            track.isEnabled = true
            screenSource = source
            screenTrackRef = track
            screenCapturerToken = RTCVideoCapturer(delegate: source)

            pendingMediaType = .screen
            do {
                screenProducer = try sendTransport.createProducer(
                    for: track,
                    encodings: nil,
                    codecOptions: nil,
                    codec: nil,
                    appData: nil
                )
            } catch {
                screenSource = nil
                screenTrackRef = nil
                screenCapturerToken = nil
                throw CallMediaError.produceFailed(Self.describe(error))
            }

            #if DEBUG
            print("[CallMedia] Produced screen id=\(screenProducer?.id ?? "nil")")
            #endif
        }
    }

    public func stopScreenShare() async {
        await onQueue { [self] in
            screenProducer?.close()
            screenProducer = nil
            screenTrackRef?.isEnabled = false
            screenTrackRef = nil
            screenSource = nil
            screenCapturerToken = nil
        }
    }

    public func submitScreenFrame(
        _ pixelBuffer: CVPixelBuffer,
        rotation: Int,
        timestampNanos: UInt64
    ) async {
        await onQueue { [self] in
            guard let screenSource, let token = screenCapturerToken else { return }

            let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let frame = RTCVideoFrame(
                buffer: buffer,
                rotation: Self.rtcRotation(fromDegrees: rotation),
                timeStampNs: Int64(bitPattern: timestampNanos)
            )
            screenSource.capturer(token, didCapture: frame)
        }
    }

    private static func rtcRotation(fromDegrees degrees: Int) -> RTCVideoRotation {
        switch degrees {
        case 90: return ._90
        case 180: return ._180
        case 270: return ._270
        default: return ._0
        }
    }

    // MARK: - Capture

    /// Queue-confined. Creates the track on first use, then (re)starts capture
    /// on `cameraPosition`.
    private func startCapture() throws {
        if localVideoTrackRef == nil {
            let source = factory.videoSource()
            let track = factory.videoTrack(with: source, trackId: "cam-\(UUID().lowercasedString)")
            videoSource = source
            localVideoTrackRef = track
            localVideoHandle = MediasoupVideoTrack(track)
        }
        guard let videoSource else { throw CallMediaError.cameraUnavailable }

        let capturer = self.capturer ?? RTCCameraVideoCapturer(delegate: videoSource)
        self.capturer = capturer

        guard let device = RTCCameraVideoCapturer.captureDevices()
            .first(where: { $0.position == cameraPosition })
            ?? RTCCameraVideoCapturer.captureDevices().first
        else {
            throw CallMediaError.cameraUnavailable
        }

        guard let format = Self.preferredFormat(for: device) else {
            throw CallMediaError.cameraUnavailable
        }

        let fps = min(Self.targetFrameRate, Int(Self.maxFrameRate(of: format)))
        capturer.startCapture(with: device, format: format, fps: fps)
        localVideoTrackRef?.isEnabled = true
    }

    private static let targetWidth: Int32 = 1280
    private static let targetHeight: Int32 = 720
    private static let targetFrameRate = 30

    /// Largest format that still fits the 720p target — going higher costs
    /// battery and uplink for a picture the call UI never shows.
    private static func preferredFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let fitting = formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width <= targetWidth && dimensions.height <= targetHeight
        }
        let pool = fitting.isEmpty ? formats : fitting
        return pool.max { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return l.width * l.height < r.width * r.height
        }
    }

    private static func maxFrameRate(of format: AVCaptureDevice.Format) -> Float64 {
        format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
    }

    // MARK: - Helpers

    private static func describe(_ error: Error) -> String {
        if let mediasoupError = error as? MediasoupError {
            switch mediasoupError {
            case .unsupported(let message),
                 .invalidState(let message),
                 .invalidParameters(let message):
                return message
            case .mediasoup(let nsError):
                return nsError.localizedDescription
            case .unknown(let underlying):
                return String(describing: underlying)
            }
        }
        return error.localizedDescription
    }

    deinit {
        eventSink.finish()
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: - Transport delegates
// ─────────────────────────────────────────────────────────────
//
// These are called by WebRTC on its own threads. They must not touch `queue`
// synchronously: `onProduce` in particular runs on the thread that is blocked
// inside `createProducer`.

extension MediasoupCallEngine: SendTransportDelegate, ReceiveTransportDelegate {

    public func onConnect(transport: any Transport, dtlsParameters: String) {
        let transportId = transport.id
        let signaling = self.signaling
        Task {
            // `call-ice`. The server answers with CALL_ICE_ANSWER; the client
            // library does not wait for it, so a failure here surfaces as a
            // transport that never leaves `checking`.
            #if DEBUG
            print("[CallMedia] call-ice transport=\(transportId)")
            #endif
            do {
                try await signaling?.connectTransport(
                    id: transportId,
                    dtlsParameters: dtlsParameters
                )
                #if DEBUG
                print("[CallMedia] call-ice OK transport=\(transportId)")
                #endif
            } catch {
                #if DEBUG
                print("[CallMedia] call-ice FAILED transport=\(transportId): \(error)")
                #endif
            }
        }
    }

    public func onConnectionStateChange(
        transport: any Transport,
        connectionState: TransportConnectionState
    ) {
        #if DEBUG
        print("[CallMedia] transport=\(transport.id) state=\(connectionState)")
        #endif
        switch connectionState {
        case .failed, .disconnected:
            eventSink.yield(.transportFailed(transportId: transport.id))
        default:
            break
        }
    }

    public func onProduce(
        transport: any Transport,
        kind: MediaKind,
        rtpParameters: String,
        appData: String,
        callback: @escaping (String?) -> Void
    ) {
        let transportId = transport.id
        let mediaKind: CallMediaKind = (kind == .video) ? .video : .audio
        let mediaType = self.pendingMediaType
        let signaling = self.signaling

        Task {
            guard let signaling else {
                #if DEBUG
                print("[CallMedia] onProduce \(mediaKind.rawValue) aborted — no signaling")
                #endif
                callback(nil)
                return
            }
            do {
                #if DEBUG
                print("[CallMedia] onProduce \(mediaKind.rawValue) → call-produce transport=\(transportId)")
                #endif
                let producerId = try await signaling.produce(
                    transportId: transportId,
                    kind: mediaKind,
                    mediaType: mediaType,
                    rtpParameters: rtpParameters
                )
                #if DEBUG
                print("[CallMedia] onProduce \(mediaKind.rawValue) OK id=\(producerId)")
                #endif
                callback(producerId)
            } catch {
                // A nil id fails `createProducer`, which is the honest outcome:
                // the server never acknowledged the producer.
                #if DEBUG
                print("[CallMedia] onProduce \(mediaKind.rawValue) FAILED: \(error)")
                #endif
                callback(nil)
            }
        }
    }

    public func onProduceData(
        transport: any Transport,
        sctpParameters: String,
        label: String,
        protocol dataProtocol: String,
        appData: String,
        callback: @escaping (String?) -> Void
    ) {
        // Calls carry no data channels.
        callback(nil)
    }
}
