// MARK: - RealtimeKit/Transports/MQTTTransport.swift
//
// Module  : RealtimeTransportKit (internal)
// Rôle    : Implémentation du protocol RealtimeTransport via CocoaMQTT5.
//
// Contrainte Swift 6 :
//   MQTTDelegateHandler est une CLASS (pas un actor) pour les callbacks sync.
//   Elle yield vers des AsyncStream.Continuation (thread-safe).
//   L'actor MQTTTransport consomme ces streams.

import Foundation
import WaanguCoreKit
import CocoaMQTT

// MARK: - MQTTTransport

actor MQTTTransport: RealtimeTransport {

    // MARK: - Identity

    nonisolated let transportName: String = "MQTT"
    nonisolated let transportType: RealtimeTransportType = .mqtt

    // MARK: - State

    private var mqttClient: CocoaMQTT5?
    private var delegateHandler: MQTTDelegateHandler?
    private var currentConfig: RealtimeTransportConfig?

    // MARK: - Streams

    private var connectionContinuation: AsyncStream<TransportConnectionEvent>.Continuation?
    private var messageContinuation: AsyncStream<RawTransportMessage>.Continuation?

    // MARK: - Init

    init() {}

    // MARK: - RealtimeTransport — Connection

    var isConnected: Bool {
        mqttClient?.connState == .connected
    }

    func connect(config: RealtimeTransportConfig) async throws {
        currentConfig = config
        debugLog("MQTT connecting... transition to connecting")
        try await connectTCP(config: config)
    }

    func disconnect(reason: DisconnectReason) async throws {
        delegateHandler?.expectIntentionalDisconnect = true
        mqttClient?.disconnect()
        connectionContinuation?.yield(.disconnected(error: nil, isRecoverable: false))
        cleanup()
    }

    // MARK: - RealtimeTransport — Streams

    func connectionStateStream() async -> AsyncStream<TransportConnectionEvent> {
        connectionContinuation?.finish()
        let (stream, continuation) = AsyncStream<TransportConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        connectionContinuation = continuation
        delegateHandler?.connectionContinuation = continuation
        return stream
    }

    func incomingMessages() async -> AsyncStream<RawTransportMessage> {
        messageContinuation?.finish()
        let (stream, continuation) = AsyncStream<RawTransportMessage>.makeStream(
            bufferingPolicy: .bufferingNewest(100)
        )
        messageContinuation = continuation
        delegateHandler?.messageContinuation = continuation
        return stream
    }

    // MARK: - RealtimeTransport — Subscribe / Unsubscribe

    func subscribe(topic: String, qos: RealtimeQoS) async throws {
        guard let client = mqttClient else { throw RealtimeError.notConnected }
        client.subscribe(topic, qos: qos.toCocoaMQTT())
    }

    func unsubscribe(topic: String) async throws {
        mqttClient?.unsubscribe(topic)
    }

    // MARK: - RealtimeTransport — Publish

    func publish(
        data: Data,
        to topic: String,
        qos: RealtimeQoS,
        messageId: MessageID
    ) async throws {
        guard let client = mqttClient else { throw RealtimeError.notConnected }

        let message = CocoaMQTT5Message(topic: topic, payload: [UInt8](data))
        message.qos = qos.toCocoaMQTT()
        message.retained = false

        let properties = MqttPublishProperties()
        properties.userProperty = ["messageId": messageId.uuidString]
        client.publish(message, properties: properties)
    }

    // MARK: - RealtimeTransport — Heartbeat

    func updateHeartbeatInterval(_ interval: TimeInterval?) async {
        guard let interval else { return }
        mqttClient?.keepAlive = UInt16(min(interval, Double(UInt16.max)))
    }

    // MARK: - RealtimeTransport — Re-auth

    func reauthenticate(with credentials: RealtimeCredentials) async throws -> Bool {
        guard let client = mqttClient,
              let config = currentConfig else { return false }

        client.username = credentials.userId
        client.password = credentials.token

        // MQTT 5.0 : re-auth via AUTH packet
        if config.protocolOptions.mqttVersion.supportsReauth {
            let authProperties = MqttAuthProperties()
            authProperties.authenticationMethod = "JWT"
            if let tokenData = credentials.token.data(using: .utf8) {
                authProperties.authenticationData = [UInt8](tokenData)
            }
            // Valeur numérique du reason code reAuthenticate
            client.auth(reasonCode: CocoaMQTTAUTHReasonCode(rawValue: 0x19) ?? .continueAuthentication,
                        authProperties: authProperties)
            return true
        }

        return false
    }

    // MARK: - Private — TCP Connection

    private func connectTCP(config: RealtimeTransportConfig) async throws {
        cleanup()

        let client = CocoaMQTT5(
            clientID: config.clientId,
            host: config.host,
            port: config.port
        )

        configureClient(client, config: config)

        let handler = MQTTDelegateHandler()
        handler.connectionContinuation = connectionContinuation
        handler.messageContinuation = messageContinuation
        client.delegate = handler

        mqttClient = client
        delegateHandler = handler

        connectionContinuation?.yield(.connecting)
        
       

        let connected = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, Error>) in
            handler.connectContinuation = continuation
            let success = client.connect()
            if !success {
                handler.connectContinuation = nil
                continuation.resume(
                    throwing: RealtimeError.connectionFailed(reason: "CocoaMQTT5.connect() returned false")
                )
            }
        }

        if !connected {
            throw RealtimeError.connectionFailed(reason: "MQTT handshake failed")
        }else {
            debugLog("✅Successfully connected")
        }
    }

    private nonisolated func configureClient(
        _ client: CocoaMQTT5,
        config: RealtimeTransportConfig
    ) {
        client.username = config.credentials.userId
        client.password = config.credentials.token
        client.keepAlive = UInt16(min(config.heartbeatInterval, Double(UInt16.max)))
        client.cleanSession = config.protocolOptions.mqttCleanSession
        client.autoReconnect = false   // ReconnectionManager pilote

        // TLS
        client.enableSSL = config.tlsConfig.enabled
        if config.tlsConfig.enabled {
            client.allowUntrustCACertificate = !config.tlsConfig.validatesCertificateChain
        }

        // Last Will
        if let lwt = config.protocolOptions.mqttLastWill {
            let willMessage = CocoaMQTT5Message(
                topic: lwt.topic,
                payload: [UInt8](lwt.payload)
            )
            willMessage.qos = lwt.qos.toCocoaMQTT()
            willMessage.retained = lwt.retain
            client.willMessage = willMessage
        }

        // MQTT 5.0 Connect Properties
        let connectProperties = MqttConnectProperties()
        connectProperties.sessionExpiryInterval = config.protocolOptions.mqttSessionExpiryInterval
        connectProperties.receiveMaximum = config.protocolOptions.mqttReceiveMaximum
        connectProperties.topicAliasMaximum = config.protocolOptions.mqttTopicAliasMaximum
        // requestResponseInformation est UInt8 dans CocoaMQTT (0 = false, 1 = true)
        connectProperties.requestResponseInformation = 1
        client.connectProperties = connectProperties
    }

    private func cleanup() {
        mqttClient?.disconnect()
        mqttClient?.delegate = nil
        mqttClient = nil
        delegateHandler?.invalidate()
        delegateHandler = nil
    }
}

// MARK: - MQTTDelegateHandler

/// Handler non-actor pour les callbacks synchrones de CocoaMQTT5.
final class MQTTDelegateHandler: CocoaMQTT5Delegate, @unchecked Sendable {

    var connectionContinuation: AsyncStream<TransportConnectionEvent>.Continuation?
    var messageContinuation: AsyncStream<RawTransportMessage>.Continuation?
    var connectContinuation: CheckedContinuation<Bool, Error>?
    /// Set before client-initiated `disconnect()` so clean closes don't trigger reconnect.
    var expectIntentionalDisconnect: Bool = false

    private let lock = NSLock()
    private var isInvalid: Bool = false

    func invalidate() {
        lock.lock()
        isInvalid = true
        connectionContinuation?.finish()
        messageContinuation?.finish()
        connectContinuation = nil
        connectionContinuation = nil
        messageContinuation = nil
        lock.unlock()
    }

    // MARK: - Connection

    func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        lock.lock()
        defer { lock.unlock() }
        guard !isInvalid else { return }

        if ack == .success {
            connectionContinuation?.yield(.connected)
            connectContinuation?.resume(returning: true)
        } else {
            let reason = "CONNACK: \(ack.rawValue)"
            connectionContinuation?.yield(.authenticationRejected(reason: reason))
            connectContinuation?.resume(
                throwing: RealtimeError.authenticationFailed(reason: reason)
            )
        }
        connectContinuation = nil
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didStateChangeTo state: CocoaMQTTConnState) {
        lock.lock()
        defer { lock.unlock() }
        guard !isInvalid else { return }
        if state == .connecting { connectionContinuation?.yield(.connecting) }
    }

    func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !isInvalid else { return }

        // Broker/keep-alive/idle closes often arrive with err == nil. Treat those as
        // recoverable so RealtimeClient can reconnect while the app stays in foreground.
        // Only intentional client disconnects are non-recoverable.
        let recoverable = !expectIntentionalDisconnect
        expectIntentionalDisconnect = false

        connectionContinuation?.yield(
            .disconnected(error: err?.localizedDescription, isRecoverable: recoverable)
        )
        if let continuation = connectContinuation {
            continuation.resume(
                throwing: RealtimeError.connectionFailed(
                    reason: err?.localizedDescription ?? "Disconnected during connect"
                )
            )
            connectContinuation = nil
        }
    }

    func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}
    func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}

    // MARK: - Messages

    func mqtt5(
        _ mqtt5: CocoaMQTT5,
        didReceiveMessage message: CocoaMQTT5Message,
        id: UInt16,
        publishData: MqttDecodePublish?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !isInvalid else { return }

        var properties: [String: String] = [:]
        if let userProps = publishData?.userProperty {
            for (key, value) in userProps { properties[key] = value }
        }

        messageContinuation?.yield(RawTransportMessage(
            topic: message.topic,
            payload: Data(message.payload),
            qos: RealtimeQoS.fromCocoaMQTT(message.qos),
            brokerMessageId: properties["messageId"] ?? "\(id)",
            receivedAt: Date(),
            isRetained: message.retained,
            properties: properties
        ))
    }

    // MARK: - Publish Acks

    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}
    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishComplete id: UInt16, pubCompData: MqttDecodePubComp?) {}

    // MARK: - Subscribe / Unsubscribe

    func mqtt5(
        _ mqtt5: CocoaMQTT5,
        didSubscribeTopics success: NSDictionary,
        failed: [String],
        subAckData: MqttDecodeSubAck?
    ) {
        #if DEBUG
        if !failed.isEmpty { print("[MQTTTransport] Subscribe failed: \(failed)") }
        #endif
    }

    func mqtt5(
        _ mqtt5: CocoaMQTT5,
        didUnsubscribeTopics topics: [String],
        unsubAckData: MqttDecodeUnsubAck?
    ) {}

    // MARK: - Auth (MQTT 5.0)

    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {
        #if DEBUG
        print("[MQTTTransport] AUTH reason: \(reasonCode.rawValue)")
        #endif
    }

    // MARK: - Disconnect (MQTT 5.0)

    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {
        lock.lock()
        defer { lock.unlock() }
        guard !isInvalid else { return }
        connectionContinuation?.yield(
            .serverDisconnect(code: Int(reasonCode.rawValue), reason: "\(reasonCode)")
        )
    }
}

// MARK: - QoS Mapping

extension RealtimeQoS {
    func toCocoaMQTT() -> CocoaMQTTQoS {
        switch self {
        case .fireAndForget: return .qos0
        case .atLeastOnce:   return .qos1
        case .exactlyOnce:   return .qos2
        }
    }

    static func fromCocoaMQTT(_ qos: CocoaMQTTQoS) -> RealtimeQoS {
        switch qos {
        case .qos0: return .fireAndForget
        case .qos1: return .atLeastOnce
        case .qos2: return .exactlyOnce
        @unknown default: return .fireAndForget
        }
    }
}
