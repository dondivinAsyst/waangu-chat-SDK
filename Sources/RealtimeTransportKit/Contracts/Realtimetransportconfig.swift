//
//  Realtimetransportconfig.swift
//  AppModules
//
//  Created by Asyst on 6/2/26.
//

// MARK: - RealtimeKit/Contracts/RealtimeTransportConfig.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Configuration complète passée à chaque transport au connect().
//           Porte la connexion (host, port, TLS), l'auth, le heartbeat,
//           la compression, les limites, et les options spécifiques au transport.
//
// Design  : Struct immuable construite par RealtimeAssembly à partir de la
//           config publique (RealtimeConfiguration). Le transport lit ce dont
//           il a besoin et ignore le reste.
//
//           La config publique (ce que le DependencyContainer fournit) est dans
//           RealtimeAssembly. Ici c'est la config interne résolue, prête à l'emploi.

import Foundation
import WaanguCoreKit

// MARK: - RealtimeTransportConfig

/// Configuration interne résolue pour un transport.
///
/// Construite par le `RealtimeAssembly` en combinant :
/// - La configuration publique fournie par le `DependencyContainer`
/// - Les paramètres adaptatifs résolus par `AdaptiveRealtimePolicy`
/// - Les credentials du `RealtimeAuthDelegate`
struct RealtimeTransportConfig: Sendable {

    // MARK: - Connection

    /// Hostname ou IP du broker/serveur.
    let host: String

    /// Port de connexion.
    let port: UInt16

    /// Configuration TLS/SSL.
    let tlsConfig: TransportTLSConfig

    // MARK: - Authentication

    /// Credentials pour l'authentification initiale.
    let credentials: RealtimeCredentials

    /// Identifiant unique du client auprès du broker.
    ///
    /// MQTT : clientId (unique par connexion, ex: "waangu-ios-{deviceId}").
    /// WebSocket : porté dans le handshake ou le premier message.
    let clientId: String

    // MARK: - Device

    /// Informations sur le device (pour la presence multi-device et les métriques).
    let deviceInfo: RealtimeDeviceInfo

    // MARK: - Keep-alive / Heartbeat

    /// Intervalle de heartbeat/keep-alive en secondes.
    ///
    /// MQTT : PINGREQ interval.
    /// WebSocket : ping frame interval.
    /// Adapté dynamiquement par le BatteryAwareScheduler (fg: 15s, bg: 60s).
    let heartbeatInterval: TimeInterval

    /// Timeout après lequel un heartbeat manqué déclenche une déconnexion.
    ///
    /// Typiquement 1.5× le heartbeatInterval.
    let heartbeatTimeout: TimeInterval

    // MARK: - Payload Limits

    /// Taille maximale d'un payload en bytes.
    ///
    /// Les messages qui dépassent cette taille sont rejetés avant l'envoi
    /// avec `RealtimeError.payloadTooLarge`.
    let maxPayloadSize: Int

    // MARK: - Compression

    /// `true` si la compression des payloads est activée.
    ///
    /// Décidé par l'`AdaptiveRealtimePolicy` selon le réseau
    /// (cellular/constrained → true, WiFi premium → false).
    let compressionEnabled: Bool

    // MARK: - Protocol-specific Options

    /// Options spécifiques au protocole de transport.
    ///
    /// Chaque transport lit les options qui le concernent et ignore les autres.
    /// Permet d'ajouter des options sans modifier la struct.
    let protocolOptions: TransportProtocolOptions

    // MARK: - Init

    init(
        host: String,
        port: UInt16,
        tlsConfig: TransportTLSConfig = .standard,
        credentials: RealtimeCredentials,
        clientId: String,
        deviceInfo: RealtimeDeviceInfo,
        heartbeatInterval: TimeInterval = 15,
        heartbeatTimeout: TimeInterval = 25,
        maxPayloadSize: Int = 256 * 1024,       // 256 KB default
        compressionEnabled: Bool = false,
        protocolOptions: TransportProtocolOptions = .init()
    ) {
        self.host = host
        self.port = port
        self.tlsConfig = tlsConfig
        self.credentials = credentials
        self.clientId = clientId
        self.deviceInfo = deviceInfo
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.maxPayloadSize = maxPayloadSize
        self.compressionEnabled = compressionEnabled
        self.protocolOptions = protocolOptions
    }
}

// MARK: - TransportTLSConfig

/// Configuration TLS pour la connexion transport.
///
/// Réutilise les mêmes certificats/pins que NetworkKit
/// (fournis par le DependencyContainer, pas recrées ici).
struct TransportTLSConfig: Sendable {

    /// `true` pour activer TLS/SSL. `false` pour connexion en clair (dev uniquement).
    let enabled: Bool

    /// `true` pour valider le certificat serveur (désactiver uniquement en dev local).
    let validatesCertificateChain: Bool

    /// Certificats racine custom pour le pinning (DER-encoded).
    /// `nil` = utiliser les certificats système.
    /// Fournis depuis la config de certificate pinning de NetworkKit.
    let pinnedCertificates: [Data]?

    /// Clé publique pinnée (SHA-256 hash, base64-encoded).
    /// Alternative au certificate pinning.
    let pinnedPublicKeyHashes: [String]?

    // MARK: - Presets

    /// TLS standard avec validation système.
    static let standard = TransportTLSConfig(
        enabled: true,
        validatesCertificateChain: true,
        pinnedCertificates: nil,
        pinnedPublicKeyHashes: nil
    )

    /// TLS désactivé (développement local uniquement).
    static let disabled = TransportTLSConfig(
        enabled: false,
        validatesCertificateChain: false,
        pinnedCertificates: nil,
        pinnedPublicKeyHashes: nil
    )

    /// TLS avec certificate pinning.
    static func pinned(certificates: [Data]) -> TransportTLSConfig {
        TransportTLSConfig(
            enabled: true,
            validatesCertificateChain: true,
            pinnedCertificates: certificates,
            pinnedPublicKeyHashes: nil
        )
    }

    /// TLS avec public key pinning (plus flexible que le certificate pinning).
    static func pinned(publicKeyHashes: [String]) -> TransportTLSConfig {
        TransportTLSConfig(
            enabled: true,
            validatesCertificateChain: true,
            pinnedCertificates: nil,
            pinnedPublicKeyHashes: publicKeyHashes
        )
    }

    // MARK: - Init

    init(
        enabled: Bool = true,
        validatesCertificateChain: Bool = true,
        pinnedCertificates: [Data]? = nil,
        pinnedPublicKeyHashes: [String]? = nil
    ) {
        self.enabled = enabled
        self.validatesCertificateChain = validatesCertificateChain
        self.pinnedCertificates = pinnedCertificates
        self.pinnedPublicKeyHashes = pinnedPublicKeyHashes
    }
}

// MARK: - TransportProtocolOptions

/// Options spécifiques à chaque protocole de transport.
///
/// Chaque transport lit les options qui le concernent et ignore les autres.
/// Design extensible — ajouter des options ne casse pas les transports existants.
struct TransportProtocolOptions: Sendable {

    // MARK: - MQTT Options

    /// Version du protocole MQTT.
    let mqttVersion: MQTTVersion

    /// `true` pour une session propre (MQTT Clean Session / Clean Start).
    /// `false` pour reprendre les souscriptions persistées côté broker.
    let mqttCleanSession: Bool

    /// Message envoyé automatiquement par le broker si le client se déconnecte
    /// de manière inattendue (crash, network loss).
    let mqttLastWill: LastWillConfig?

    /// `true` pour activer la rétention des messages (MQTT retained).
    /// Le broker garde le dernier message de chaque topic et l'envoie
    /// aux nouveaux souscripteurs.
    let mqttRetainSupported: Bool

    /// Taille maximale de la receive queue MQTT.
    let mqttReceiveMaximum: UInt16

    // MARK: - WebSocket Options

    /// Path de l'endpoint WebSocket (ex: "/ws", "/realtime").
    let webSocketPath: String

    /// Sous-protocoles WebSocket demandés (ex: ["mqtt", "v1.realtime"]).
    let webSocketSubprotocols: [String]

    /// Headers HTTP additionnels pour le handshake WebSocket.
    let webSocketHeaders: [String: String]

    /// Intervalle de ping WebSocket en secondes.
    /// Si `nil`, utilise le heartbeatInterval de la config principale.
    let webSocketPingInterval: TimeInterval?

    // MARK: - Init

    // MARK: - MQTT 5.0 Session Properties

    /// Durée d'expiration de la session côté broker (secondes).
    /// Après déconnexion, le broker garde les souscriptions et messages
    /// pendant cette durée. `0` = session supprimée immédiatement.
    /// MQTT 5.0 uniquement — ignoré en 3.1.1.
    let mqttSessionExpiryInterval: UInt32

    /// Topic alias maximum (MQTT 5.0).
    /// Permet au broker d'utiliser des alias numériques au lieu de
    /// répéter les topic strings complets — réduit la bande passante.
    let mqttTopicAliasMaximum: UInt16

    // MARK: - Init

    init(
        mqttVersion: MQTTVersion = .v5_0,
        mqttCleanSession: Bool = true,
        mqttLastWill: LastWillConfig? = nil,
        mqttRetainSupported: Bool = false,
        mqttReceiveMaximum: UInt16 = 65535,
        mqttSessionExpiryInterval: UInt32 = 3600,
        mqttTopicAliasMaximum: UInt16 = 0,
        webSocketPath: String = "/ws",
        webSocketSubprotocols: [String] = [],
        webSocketHeaders: [String: String] = [:],
        webSocketPingInterval: TimeInterval? = nil
    ) {
        self.mqttVersion = mqttVersion
        self.mqttCleanSession = mqttCleanSession
        self.mqttLastWill = mqttLastWill
        self.mqttRetainSupported = mqttRetainSupported
        self.mqttReceiveMaximum = mqttReceiveMaximum
        self.mqttSessionExpiryInterval = mqttSessionExpiryInterval
        self.mqttTopicAliasMaximum = mqttTopicAliasMaximum
        self.webSocketPath = webSocketPath
        self.webSocketSubprotocols = webSocketSubprotocols
        self.webSocketHeaders = webSocketHeaders
        self.webSocketPingInterval = webSocketPingInterval
    }
}

// MARK: - MQTTVersion

/// Version du protocole MQTT.
public enum MQTTVersion: String, Sendable {

    /// MQTT 3.1.1 — le plus supporté, pas de re-auth in-place.
    case v3_1_1 = "3.1.1"

    /// MQTT 5.0 — supporte re-auth, user properties, reason codes.
    case v5_0 = "5.0"

    /// `true` si cette version supporte la ré-authentification in-place.
    public var supportsReauth: Bool {
        self == .v5_0
    }

    /// `true` si cette version supporte les user properties (metadata custom).
    public var supportsUserProperties: Bool {
        self == .v5_0
    }

    /// `true` si cette version supporte les reason codes détaillés.
    public var supportsReasonCodes: Bool {
        self == .v5_0
    }
}

// MARK: - LastWillConfig

/// Configuration du Last Will and Testament (LWT).
///
/// Message envoyé automatiquement par le broker quand le client
/// se déconnecte de manière inattendue (crash, perte réseau).
///
/// Usage typique : publier un état de presence `.offline` quand le client crash.
///
/// ```swift
/// let lastWill = LastWillConfig(
///     topic: "users/\(userId)/presence",
///     payload: try JSONEncoder().encode(PresenceState.offline),
///     qos: .atLeastOnce,
///     retain: true        // le broker garde l'état offline pour les futurs souscripteurs
/// )
/// ```
public struct LastWillConfig: Sendable {

    /// Topic sur lequel publier le LWT.
    let topic: String

    /// Payload du LWT (déjà encodé en Data).
    let payload: Data

    /// QoS du message LWT.
    let qos: RealtimeQoS

    /// `true` pour que le broker retienne le LWT comme dernier message du topic.
    let retain: Bool

    public init(
        topic: String,
        payload: Data,
        qos: RealtimeQoS = .atLeastOnce,
        retain: Bool = true
    ) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retain = retain
    }
}

// MARK: - RealtimeTransportConfig Validation

extension RealtimeTransportConfig {

    /// Valide la configuration et retourne les erreurs éventuelles.
    ///
    /// Appelé par le `RealtimeAssembly` avant de créer le transport.
    func validate() -> [String] {
        var errors: [String] = []

        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Host cannot be empty")
        }

        if port == 0 {
            errors.append("Port cannot be 0")
        }

        if clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Client ID cannot be empty")
        }

        if heartbeatInterval <= 0 {
            errors.append("Heartbeat interval must be positive")
        }

        if heartbeatTimeout <= heartbeatInterval {
            errors.append("Heartbeat timeout must be greater than heartbeat interval")
        }

        if maxPayloadSize <= 0 {
            errors.append("Max payload size must be positive")
        }

        if credentials.token.isEmpty {
            errors.append("Auth token cannot be empty")
        }

        return errors
    }

    /// `true` si la configuration est valide.
    var isValid: Bool {
        validate().isEmpty
    }
}

// MARK: - Port Defaults

extension RealtimeTransportConfig {

    /// Ports standard par transport et TLS.
    enum DefaultPort {
        /// MQTT standard (non-TLS).
        static let mqtt: UInt16 = 1883

        /// MQTT over TLS.
        static let mqttTLS: UInt16 = 8883

        /// MQTT over WebSocket (non-TLS).
        static let mqttWebSocket: UInt16 = 8083

        /// MQTT over WebSocket over TLS.
        static let mqttWebSocketTLS: UInt16 = 8084

        /// WebSocket standard (non-TLS).
        static let webSocket: UInt16 = 80

        /// WebSocket over TLS (wss://).
        static let webSocketTLS: UInt16 = 443
    }
}
