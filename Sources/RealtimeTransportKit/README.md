# RealtimeTransportKit

## Infrastructure Temps Réel — Waangu Super App iOS

**Version** : 1.0  
**Stack** : iOS 16+ · Swift 6 · Swift Concurrency (actors, async/await, AsyncStream)  
**Transport actuel** : MQTT 5.0 via CocoaMQTT  
**Transports supportés** : MQTT, WebSocket (standalone), InMemory (tests), extensible

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture](#2-architecture)
3. [Usage dans les features](#3-usage-dans-les-features)
4. [Configuration dans le DependencyContainer](#4-configuration-dans-le-dependencycontainer)
5. [Déclaration des topics par feature](#5-déclaration-des-topics-par-feature)
6. [Subscribe — recevoir des messages](#6-subscribe--recevoir-des-messages)
7. [Publish — envoyer des messages](#7-publish--envoyer-des-messages)
8. [Request-Reply — envoyer et attendre une réponse](#8-request-reply--envoyer-et-attendre-une-réponse)
9. [Presence — typing indicators et online/offline](#9-presence--typing-indicators-et-onlineoffline)
10. [Connection state — adapter l'UI](#10-connection-state--adapter-lui)
11. [Subscription lifecycle — éviter les fuites](#11-subscription-lifecycle--éviter-les-fuites)
12. [Backpressure — gérer les flux haute fréquence](#12-backpressure--gérer-les-flux-haute-fréquence)
13. [Offline queue — messages hors connexion](#13-offline-queue--messages-hors-connexion)
14. [Testing](#14-testing)
15. [Flux internes](#15-flux-internes)
16. [Résilience réseau](#16-résilience-réseau)
17. [Background iOS](#17-background-ios)
18. [Métriques et observabilité](#18-métriques-et-observabilité)
19. [Ajout d'un nouveau transport](#19-ajout-dun-nouveau-transport)
20. [Ce qui est consommé depuis NetworkKit](#20-ce-qui-est-consommé-depuis-networkkit)
21. [Statistiques du module](#21-statistiques-du-module)

---

## 1. Vue d'ensemble

RealtimeTransportKit gère la communication bidirectionnelle temps réel de Waangu : messages chat, tracking GPS live, notifications de transaction, indicateurs de presence. Il est agnostique du transport — MQTT, WebSocket, ou tout autre protocole. Les features n'en savent rien.

```
FeatureChat / FeatureRide / FeatureWallet
    │ import CoreKit uniquement
    │ reçoit : any RealtimeClientProtocol
    │
CoreKit (protocols, value types)
    │
RealtimeTransportKit (implémentation)
    │
Transport actif (MQTT 5.0 / WebSocket / InMemory)
    │
Broker distant
```

---

## 2. Architecture

### Symétrie avec StorageKit

Chaque concept de StorageKit a son équivalent exact :

| StorageKit | RealtimeTransportKit | Rôle |
|---|---|---|
| `DatabaseRepositoryProtocol` | `RealtimeClientProtocol` | Contrat public (CoreKit) |
| `DatabaseStore` | `RealtimeClient` | Adapter central (actor) |
| `DatabaseEngine` | `RealtimeTransport` | Protocol interne du transport |
| `SQLiteEngine` | `MQTTTransport` | Implémentation concrète |
| `InMemoryEngine` | `InMemoryTransport` | Tests unitaires |
| `DatabaseAssembly` | `RealtimeAssembly` | Factory publique |
| `DatabaseRegistrable` | `RealtimeRegistrable` | Déclaration par feature |

### Sous-systèmes

```
RealtimeTransportKit/
├── Contracts/        RealtimeTransport + TransportConfig
├── Client/           RealtimeClient (adapter) + ConnectionStateMachine
├── Assembly/         RealtimeAssembly (factory publique)
├── Transports/       MQTTTransport, InMemoryTransport, TransportFallbackChain
├── Reconnection/     ReconnectionManager (exponential backoff + jitter)
├── Auth/             RealtimeTokenRefresher (JWT refresh sur connexion vivante)
├── Dedup/            MessageDeduplicator (fenêtre glissante QoS 1)
├── Subscriptions/    SubscriptionRegistry (tracking, wildcards, throttle/debounce)
├── Parsing/          PayloadDecoder (JSON centralisé)
├── Compression/      PayloadCompressor (gzip pour réseaux limités)
├── Network/          NetworkTransitionHandler (reconnect proactif WiFi↔Cellular)
├── Battery/          BatteryAwareScheduler (heartbeat adaptatif)
├── Background/       BackgroundPolicyManager (iOS background tasks)
├── Metrics/          RealtimeMetricsCollector (OSSignpost + callbacks)
└── Testing/          ChaosTransport, RecordingTransport, RealtimeTestCase
```

---

## 3. Usage dans les features

### Règle fondamentale

```swift
// ✅ CORRECT — la feature importe CoreKit uniquement
import CoreKit

actor ChatRepository {
    private let realtime: any RealtimeClientProtocol  // injecté
}

// ❌ INTERDIT — jamais dans une feature
import RealtimeTransportKit
import CocoaMQTT
```

### Injection via Dependencies

```swift
// La feature déclare ses dépendances
struct ChatDependencies {
    let realtime: any RealtimeClientProtocol    // ← protocol CoreKit
    let database: any DatabaseRepositoryProtocol
    let analytics: any AnalyticsProtocol
}

// Le DependencyContainer injecte
func makeChatDependencies() -> ChatDependencies {
    ChatDependencies(
        realtime: realtimeClient,     // ← RealtimeAssembly.make(...)
        database: databaseStore,
        analytics: analytics
    )
}
```

---

## 4. Configuration dans le DependencyContainer

```swift
// DependencyContainer.swift — seul fichier qui importe RealtimeTransportKit
import RealtimeTransportKit

lazy var realtimeClient: any RealtimeClientProtocol = {
    RealtimeAssembly.make(config: RealtimeConfiguration(
        // Transport — swap en 1 ligne
        transport: .mqtt,              // .webSocket, .inMemory
        
        // Connexion
        host: appConfig.realtimeHost,  // "mqtt.waangu.com"
        port: appConfig.realtimePort,  // 8883
        useTLS: true,
        
        // Auth — pont vers AuthKit
        authDelegate: realtimeAuthBridge,
        
        // Device
        deviceInfo: RealtimeDeviceInfo(
            deviceId: deviceInfoProvider.deviceId,
            platform: "iOS",
            appVersion: Bundle.main.appVersion
        ),
        
        // NetworkKit (consommé, pas recréé)
        networkMonitor: networkMonitor,
        deviceTier: deviceTier,
        performanceMonitor: performanceMonitor,
        
        // Reconnexion
        reconnectionPolicy: .standard,       // .aggressive pour le ride
        
        // Métriques
        metricsDelegate: RealtimeMetricsCollector.shared
    ))
}()
```

### Bootstrap — ordre d'appel

```swift
func bootstrap() async {
    await configureURLCache()
    await registerSQLiteEntities()
    await bootstrapRealtime()               // enregistre les topics
    await connectRealtimeIfAuthenticated()   // connect SI token valide
}

// Après login
func onLoginSuccess() async {
    try? await realtimeClient.connect()
}

// Au logout
func onLogout() async {
    try? await realtimeClient.disconnect(reason: .userInitiated, flushQueue: true)
}
```

---

## 5. Déclaration des topics par feature

Chaque feature déclare ses topics via `RealtimeRegistrable` dans son propre module :

```swift
// FeatureChat/ChatRealtimeRegistration.swift
import CoreKit  // jamais RealtimeTransportKit

enum ChatRealtimeRegistration: RealtimeRegistrable {
    static var topicRegistrations: [TopicRegistration] {
        [
            TopicRegistration(
                topicPattern: .singleWildcard(feature: "chat", path: "+/messages"),
                qos: .atLeastOnce,             // chaque message compte
                backgroundPolicy: .disconnect,  // couper en background
                bufferingPolicy: .unbounded,     // tout garder
                priority: .normal
            ),
            TopicRegistration(
                topicPattern: .singleWildcard(feature: "chat", path: "+/presence"),
                qos: .fireAndForget,
                backgroundPolicy: .disconnect,
                bufferingPolicy: .debounce(interval: 1.0),  // stabiliser le typing
                priority: .low
            ),
        ]
    }
}
```

```swift
// FeatureRide/RideRealtimeRegistration.swift
enum RideRealtimeRegistration: RealtimeRegistrable {
    static var topicRegistrations: [TopicRegistration] {
        [
            TopicRegistration(
                topicPattern: .singleWildcard(feature: "ride", path: "+/position"),
                qos: .fireAndForget,
                backgroundPolicy: .maintainBriefly,           // garder ~30s en bg
                bufferingPolicy: .throttle(interval: 0.5),     // max 2 positions/s
                priority: .high
            ),
            TopicRegistration(
                topicPattern: .singleWildcard(feature: "ride", path: "+/status"),
                qos: .atLeastOnce,
                backgroundPolicy: .maintainBriefly,
                bufferingPolicy: .unbounded,
                priority: .critical
            ),
        ]
    }
}
```

Le DependencyContainer collecte tout au bootstrap :

```swift
private static let allRegistrations: [any RealtimeRegistrable.Type] = [
    ChatRealtimeRegistration.self,
    RideRealtimeRegistration.self,
    WalletRealtimeRegistration.self,
    MarketplaceRealtimeRegistration.self,
]
```

---

## 6. Subscribe — recevoir des messages

```swift
actor ChatRepository {
    private let realtime: any RealtimeClientProtocol
    private let subscriptions = SubscriptionGroup()

    /// Observe les messages d'une conversation en temps réel.
    func observeMessages(conversationId: UUID) async throws -> AsyncStream<ChatMessage> {
        let topic = RealtimeTopic.scoped(
            feature: "chat",
            path: "\(conversationId)/messages"
        )
        
        let (stream, token) = try await realtime.subscribe(
            to: topic,
            as: ChatMessage.self,       // décodage JSON automatique
            buffering: .unbounded,      // chaque message est critique
            qos: .atLeastOnce           // at-least-once + dédup automatique
        )
        
        // Stocker le token pour le cleanup
        subscriptions.add(token)
        
        return stream
    }
}
```

**Dans le ViewModel :**

```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    
    private var messageTask: Task<Void, Never>?
    
    func onAppear() {
        messageTask = Task {
            let stream = try await repository.observeMessages(conversationId: convId)
            for await message in stream {
                messages.append(message)
            }
        }
    }
    
    func onDisappear() {
        messageTask?.cancel()
        Task { await repository.cleanup() }
    }
}
```

---

## 7. Publish — envoyer des messages

```swift
/// Envoi simple — fire and forget côté code appelant.
/// Si déconnecté, l'offline queue prend le relais automatiquement.
func sendMessage(_ message: ChatMessage) async throws {
    try await realtime.publish(
        message,                        // Encodable — sérialisé en JSON automatiquement
        to: .scoped(feature: "chat", path: "\(message.conversationId)/messages"),
        qos: .atLeastOnce,
        priority: .normal
    )
}

/// Envoi avec defaults (QoS atLeastOnce, priority normal).
func sendQuick(_ message: ChatMessage) async throws {
    try await realtime.publish(
        message,
        to: .scoped(feature: "chat", path: "\(message.conversationId)/messages")
    )
}
```

**Comportement selon l'état de connexion :**

| État | Comportement |
|---|---|
| Connecté | Envoi immédiat via le transport |
| Reconnecting | Message mis en offline queue → envoyé à la reconnexion |
| Déconnecté (pas de queue) | Throw `RealtimeError.notConnected` |

---

## 8. Request-Reply — envoyer et attendre une réponse

Pour les cas où une confirmation serveur est nécessaire (accusé de réception, validation) :

```swift
/// Envoie un message et attend l'ack serveur (timeout 10s).
func sendAndConfirm(_ message: ChatMessage) async throws -> ServerAck {
    let ack: ServerAck = try await realtime.request(
        message,
        to: .scoped(feature: "chat", path: "\(message.conversationId)/messages"),
        replyOn: .scoped(feature: "chat", path: "\(message.conversationId)/acks"),
        as: ServerAck.self,
        timeout: 10.0
    )
    return ack
}

struct ServerAck: Codable, Sendable {
    let messageId: UUID
    let serverTimestamp: Date
    let status: String
}
```

**Flow interne :**
1. Subscribe au topic de réponse (acks)
2. Publish le message sur le topic principal
3. Attend un message sur le topic acks avec correlationId
4. Timeout si pas de réponse → throw `RealtimeError.requestTimeout`

---

## 9. Presence — typing indicators et online/offline

```swift
/// Publier un état de presence.
func startTyping(conversationId: UUID) async throws {
    try await realtime.publishPresence(
        .typing(in: conversationId.uuidString),
        to: .scoped(feature: "chat", path: "\(conversationId)/presence")
    )
}

func stopTyping(conversationId: UUID) async throws {
    try await realtime.publishPresence(
        .online,
        to: .scoped(feature: "chat", path: "\(conversationId)/presence")
    )
}

/// Observer la presence des autres (filtrer ses propres events).
func observeTyping(conversationId: UUID) -> AsyncStream<PresenceInfo> {
    let stream = realtime.observePresence(
        on: .scoped(feature: "chat", path: "\(conversationId)/presence")
    )
    // Filtrer ses propres events
    return stream.filter { $0.userId != currentUserId }
}
```

**États de presence disponibles :**

```swift
.online                        // l'utilisateur est actif
.offline                       // déconnecté ou app fermée
.away(since: Date)             // inactif depuis X minutes
.typing(in: "conversationId")  // en train de taper
.custom(key: "in_call", value: nil)  // état custom extensible
```

**Multi-device :** chaque `PresenceInfo` porte un `deviceId` — si l'utilisateur est sur iPhone et iPad, la presence distingue les deux.

---

## 10. Connection state — adapter l'UI

```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var connectionBanner: String?
    
    func observeConnection() {
        Task {
            for await state in realtime.observeConnectionState() {
                switch state {
                case .connected:
                    connectionBanner = nil
                case .connecting, .authenticating:
                    connectionBanner = "Connexion..."
                case .reconnecting(let attempt, let delay):
                    connectionBanner = "Reconnexion (\(attempt))..."
                case .disconnected(let reason):
                    switch reason {
                    case .networkLost:  connectionBanner = "Pas de réseau"
                    case .tokenExpired: connectionBanner = "Session expirée"
                    default:            connectionBanner = "Déconnecté"
                    }
                case .suspended:
                    connectionBanner = nil  // background — pas de banner
                }
            }
        }
    }
}
```

**Machine à états complète :**

```
disconnected → connecting → authenticating → connected
      ↑                                         │
      │←── reconnecting(attempt, delay) ←───────│
      │                                         │
      │←─────────── suspended ←─────────────────│
      │                   │
      │←──────────────────│ (fatal error)
```

---

## 11. Subscription lifecycle — éviter les fuites

**Le problème :** un subscribe() vit indéfiniment. Sans cleanup, on accumule des souscriptions zombies.

**La solution :** chaque subscribe retourne un token. Quand le token meurt, le unsubscribe est automatique.

```swift
actor RideRepository {
    private let subscriptions = SubscriptionGroup()
    
    func startTracking(tripId: UUID) async throws {
        // Chaque subscribe retourne un token
        let (positionStream, token1) = try await realtime.subscribe(
            to: .scoped(feature: "ride", path: "\(tripId)/position"),
            as: DriverPosition.self,
            buffering: .throttle(interval: 0.5),
            qos: .fireAndForget
        )
        subscriptions.add(token1)
        
        let (statusStream, token2) = try await realtime.subscribe(
            to: .scoped(feature: "ride", path: "\(tripId)/status"),
            as: TripStatus.self,
            buffering: .unbounded,
            qos: .atLeastOnce
        )
        subscriptions.add(token2)
    }
    
    /// Cleanup — annule TOUTES les souscriptions d'un coup.
    func stopTracking() async {
        await subscriptions.cancelAll()
    }
    
    /// Ou annuler par feature (depuis le RealtimeClient directement)
    func emergencyCleanup() async {
        await realtime.cancelAllSubscriptions(forFeature: "ride")
    }
}
```

**Safety net :** si le développeur oublie `cancel()`, le token log un warning en DEBUG au `deinit` et tente un cleanup automatique.

---

## 12. Backpressure — gérer les flux haute fréquence

Un topic GPS peut pousser 60 messages/seconde. Sans backpressure, l'AsyncStream explose la mémoire.

```swift
// GPS tracking — seule la dernière position compte, max 2/s
let (stream, _) = try await realtime.subscribe(
    to: topic,
    as: DriverPosition.self,
    buffering: .throttle(interval: 0.5),  // 1 message max toutes les 0.5s
    qos: .fireAndForget
)

// Chat — chaque message est important
let (stream, _) = try await realtime.subscribe(
    to: topic,
    as: ChatMessage.self,
    buffering: .unbounded,                 // tout garder
    qos: .atLeastOnce
)

// Typing — attendre la stabilisation
let (stream, _) = try await realtime.subscribe(
    to: topic,
    as: PresenceInfo.self,
    buffering: .debounce(interval: 1.0),   // 1s de silence avant d'émettre
    qos: .fireAndForget
)

// Solde wallet — seul le dernier compte
let (stream, _) = try await realtime.subscribe(
    to: topic,
    as: WalletBalance.self,
    buffering: .bufferNewest(1),            // garder uniquement le plus récent
    qos: .atLeastOnce
)
```

**Policies disponibles :**

| Policy | Comportement | Cas d'usage |
|---|---|---|
| `.unbounded` | Tout garder | Chat messages, notifications |
| `.bufferNewest(N)` | Garder les N derniers, drop les anciens | Dernier solde, dernier statut |
| `.bufferOldest(N)` | Garder les N premiers, drop les nouveaux | Résultats de recherche |
| `.throttle(interval)` | Max 1 message par intervalle | GPS tracking (2/s max) |
| `.debounce(interval)` | Attendre la stabilisation | Typing indicators, recherche live |

---

## 13. Offline queue — messages hors connexion

L'utilisateur tape un message sans réseau → le message est mis en file → envoyé à la reconnexion.

```swift
// Côté feature — transparent, pas de code spécial
try await realtime.publish(message, to: topic, qos: .atLeastOnce, priority: .normal)
// Si déconnecté → automatiquement mis en offline queue
// Si connecté → envoyé immédiatement

// Consultation de l'état de la queue
let pending = await realtime.offlineQueue.pendingCount
let items = await realtime.offlineQueue.pendingItems()

// Purge manuelle
await realtime.offlineQueue.clear()
```

**Comportement automatique :**
- Les messages dont le TTL est expiré sont purgés avant le flush
- L'ordre FIFO est garanti par topic
- Le flush se fait automatiquement à la reconnexion

---

## 14. Testing

### Test unitaire avec InMemoryTransport

```swift
class ChatRepositoryTests: RealtimeTestCase {
    
    var repository: ChatRepository!
    
    override func setUp() async throws {
        try await super.setUp()
        // realtimeClient et inMemoryTransport sont fournis par RealtimeTestCase
        repository = ChatRepository(
            realtime: realtimeClient,
            database: mockDatabase,
            currentUserId: "user-1"
        )
    }
    
    func testObserveMessages() async throws {
        // 1. Souscrire
        let stream = try await repository.observeMessages(conversationId: convId)
        
        // 2. Simuler un message entrant (comme si le broker l'envoyait)
        let message = ChatMessage(conversationId: convId, senderId: "user-2", text: "Hello")
        let data = try JSONEncoder().encode(message)
        await inMemoryTransport.simulateIncoming(
            topic: "chat/\(convId)/messages",
            payload: data
        )
        
        // 3. Vérifier
        let received = try await awaitFirst(from: stream)
        XCTAssertEqual(received.text, "Hello")
    }
    
    func testPublishMessage() async throws {
        let message = ChatMessage(conversationId: convId, senderId: "user-1", text: "Hi")
        try await repository.sendMessage(message)
        
        // Vérifier que le message a été publié
        await assertPublishedCount(1)
        let published = await inMemoryTransport.lastPublishedMessage
        let decoded = try published?.decode(as: ChatMessage.self)
        XCTAssertEqual(decoded?.text, "Hi")
    }
}
```

### Test de résilience avec ChaosTransport

```swift
func testReconnectionDuringPublish() async throws {
    // Simuler une déconnexion inattendue
    await inMemoryTransport.simulateDisconnection(recoverable: true)
    
    // Le publish doit mettre le message en offline queue (pas throw)
    let message = ChatMessage(...)
    try await repository.sendMessage(message)
    
    // Vérifier que le message est en queue
    let pending = await realtimeClient.offlineQueue.pendingCount
    XCTAssertEqual(pending, 1)
}

func testTokenExpiry() async throws {
    // Simuler un rejet d'auth par le broker
    await inMemoryTransport.simulateAuthRejection(reason: "Token expired")
    
    // Vérifier que l'état passe à .disconnected(.tokenExpired)
    let state = await realtimeClient.connectionState
    if case .disconnected(let reason) = state {
        XCTAssertEqual(reason, .tokenExpired)
    }
}
```

### Transports de test disponibles

| Transport | Rôle | API clé |
|---|---|---|
| `InMemoryTransport` | Déterministe | `simulateIncoming()`, `publishedMessages`, `simulateDisconnection()` |
| `ChaosTransport` | Conditions dégradées | Latence aléatoire, drop rate, déconnexions planifiées |
| `RecordingTransport` | Assertions précises | `publishedMessages`, `subscribedTopics`, `connectionEvents` |

---

## 15. Flux internes

### Publish

```
Feature.publish(ChatMessage)
  → RealtimeClient.publish()
    → PayloadDecoder.encode() → Data
    → vérifie taille ≤ maxPayloadSize
    → PayloadCompressor.compress() (si cellular)
    → si connecté : MQTTTransport.publish(Data, topic, qos, messageId)
    → si reconnecting : OfflineQueue.enqueue() → flush à la reconnexion
    → si déconnecté : throw .notConnected
```

### Receive

```
Broker → MQTT PUBLISH
  → MQTTDelegateHandler.didReceiveMessage() [sync, non-actor]
    → continuation.yield(RawTransportMessage) [thread-safe]
  → RealtimeClient receive loop (for await)
    → MessageDeduplicator.isDuplicate(id) → filtrer
    → PayloadCompressor.decompress()
    → SubscriptionRegistry.subscriptions(matching: topic)
      → wildcard matching
      → throttle/debounce filtering
    → PayloadDecoder.decode(Type, from: data)
    → subscription.continuation.yield(ChatMessage)
  → Feature (for await message in stream)
```

### Reconnexion

```
Connexion perdue
  → TransportConnectionEvent.disconnected(isRecoverable: true)
  → ConnectionStateMachine → .reconnecting(attempt: 1)
  → ReconnectionManager.nextDelay(1) → 1.2s (base + jitter)
  → Task.sleep(1.2s)
  → RealtimeAuthBridge → TokenManager → JWT frais
  → MQTTTransport.connect(config)
    → succès → .connected → resubscribe → flush queue → reset
    → échec → .reconnecting(attempt: 2) → retry avec 2.4s
```

### Token refresh (MQTT 5.0)

```
Token expire dans < 90s
  → RealtimeTokenRefresher (timer proactif)
  → RealtimeAuthBridge.realtimeClientNeedsToken()
  → TokenManager.getAccessToken() → JWT frais
  → MQTTTransport.reauthenticate(credentials)
  → MQTT 5.0 AUTH packet → broker valide
  → Connexion maintenue, souscriptions intactes, zéro interruption
```

---

## 16. Résilience réseau

### Reconnexion automatique

| Preset | Base delay | Max delay | Usage |
|---|---|---|---|
| `.standard` | 1.0s | 60s | Chat, marketplace, wallet |
| `.aggressive` | 0.5s | 15s | Ride tracking actif |
| `.conservative` | 5.0s | 300s | Background, batterie faible |

Exponential backoff : 1s → 2s → 4s → 8s → 16s → 32s → 60s (plafonné). Jitter aléatoire pour éviter le thundering herd.

### Déduplication

Fenêtre glissante de 1000 message IDs, TTL 5 minutes. Filtre les re-deliveries QoS 1. Sans ça, FeatureWallet affiche deux fois la même transaction.

### Network Transition

Détecte WiFi → Cellular (et inverse) et déclenche un reconnect proactif immédiat au lieu d'attendre le heartbeat timeout de 25 secondes.

### Transport Fallback

Si le transport principal échoue après N tentatives, le système essaie automatiquement le suivant dans la chaîne configurée.

---

## 17. Background iOS

Chaque topic déclare son comportement en background :

| Policy | Durée | Usage |
|---|---|---|
| `.disconnect` | Immédiat | Chat, typing, UI updates |
| `.maintainBriefly` | ~30s (`beginBackgroundTask`) | Ride tracking pendant une course |
| `.keepAlive` | Périodique (`BGAppRefreshTask`) | Notifications transaction wallet |
| `.reducedFrequency(30)` | Continu mais réduit | GPS (1/s → 1/30s) |

Le `BatteryAwareScheduler` adapte le heartbeat :

| Condition | Heartbeat |
|---|---|
| Foreground, WiFi, batterie ok | 15s |
| Cellular | 30s |
| Background | 60s |
| Thermique sérieux | 90s |
| Low Power Mode | 120s |

---

## 18. Métriques et observabilité

Le `RealtimeMetricsCollector` collecte :

- Messages reçus/publiés (compteurs)
- Latence moyenne de réception et publication (ms)
- Reconnexions et durée passée en reconnexion
- Messages dédupliqués / perdus (et raison)
- Taille de l'offline queue
- Souscriptions actives
- Changements d'état de connexion

Les métriques sont routées vers Firebase Analytics (événements custom) et Sentry (contexte crash reports) via le `MetricsBridge` d'ObservabilityKit.

---

## 19. Ajout d'un nouveau transport

Pour ajouter un transport (ex: Socket.IO, gRPC streaming) :

**1. Implémenter `RealtimeTransport`** dans un nouveau fichier :

```swift
actor SocketIOTransport: RealtimeTransport {
    nonisolated let transportName = "SocketIO"
    nonisolated let transportType: RealtimeTransportType = .webSocket
    
    func connect(config: RealtimeTransportConfig) async throws { ... }
    func disconnect(reason: DisconnectReason) async throws { ... }
    func subscribe(topic: String, qos: RealtimeQoS) async throws { ... }
    func unsubscribe(topic: String) async throws { ... }
    func publish(data: Data, to topic: String, qos: RealtimeQoS, messageId: MessageID) async throws { ... }
    func connectionStateStream() async -> AsyncStream<TransportConnectionEvent> { ... }
    func incomingMessages() async -> AsyncStream<RawTransportMessage> { ... }
}
```

**2. Ajouter le cas dans `TransportType`** et la factory dans `RealtimeAssembly`.

**3. Aucun autre fichier ne change.** Les features, le RealtimeClient, les sous-systèmes, les tests — tout fonctionne automatiquement avec le nouveau transport.

---

## 20. Ce qui est consommé depuis NetworkKit

| Composant NetworkKit | Usage | Recréé ? |
|---|---|---|
| `NetworkMonitoringProtocol` | Transitions WiFi↔Cellular | Non — consommé |
| `DeviceTierProtocol` | Adapter heartbeat, buffers | Non — consommé |
| `PerformanceMonitorProtocol` | Réduire l'activité sous pression | Non — consommé |
| CircuitBreaker | — | Non transposé (→ ReconnectionManager) |
| DedupService | — | Non transposé (→ MessageDeduplicator) |
| RateLimitPolicy | — | Non transposé (→ throttle par souscription) |

Les trois derniers portent le même nom conceptuel mais résolvent des problèmes fondamentalement différents (connexion persistante vs requêtes HTTP stateless).

---

## 21. Statistiques du module

| Couche | Fichiers | Rôle |
|---|---|---|
| CoreKit/Realtime | 13 | Contrats purs, types valeur |
| RealtimeTransportKit | 18 | Client, transports, sous-systèmes |
| AppTarget | 4 | DependencyContainer, AuthBridge, Registration |
| Features | 7 | Registrations + exemples (chat, ride, wallet) |
| **Total** | **42** | |
