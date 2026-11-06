// swift-tools-version: 5.9
import PackageDescription

// Manifeste PUBLIÉ dans github.com/dondivinAsyst/waangu-chat-SDK.
//
// Ce fichier n'est pas compilé par l'app : l'app utilise `Packages/Package.swift`.
// `Scripts/publish/publish_waangu_chat.sh` le copie à la place de
// `Packages/Package.swift` dans la release, et ne publie que les dossiers de
// `Sources/` et `Tests/` déclarés ici.
//
// Contenu : FeatureChat, les kits contre lesquels il compile, et les kits qui
// fournissent les implémentations de `ChatDependencies` (DomainKit compris :
// `SharedFeatureUseCaseFactory` donne `getBalance`, d'où vient l'identifiant
// utilisé pour l'authentification du chat).
//
// Retirés : les autres features, LocationKit, ObservabilityKit (et donc
// Firebase et Sentry), dont le chat n'a pas besoin.
//
// Règle : chaque target gardée ici doit avoir EXACTEMENT les mêmes
// dépendances que dans `Packages/Package.swift`. Le script le vérifie.

// Nom distinct de `AppModules` : une app dont le package local s'appelle aussi
// `AppModules` ferait croire à SwiftPM qu'elle « remplace » waangu-chat-sdk
// (« unable to override package 'AppModules' … »). Le nom n'est pas l'identité :
// les apps écrivent toujours `package: "waangu-chat-sdk"`.
let package = Package(
    name: "WaanguChat",
    platforms: [.iOS(.v17), .macOS(.v11)],

    products: [

        // Products KITS

        .library(name: "WaanguCoreKit",                 targets: ["WaanguCoreKit"]),
        .library(name: "WaanguDeviceKit",               targets: ["WaanguDeviceKit"]),
        .library(name: "WaanguRealtimeTransportKit",    targets: ["WaanguRealtimeTransportKit"]),
        .library(name: "WaanguNetworkKit",              targets: ["WaanguNetworkKit"]),
        .library(name: "WaanguStorageKit",              targets: ["WaanguStorageKit"]),
        .library(name: "WaanguAuthKit",                 targets: ["WaanguAuthKit"]),
        .library(name: "WaanguDomainKit",               targets: ["WaanguDomainKit"]),
        .library(name: "WaanguPermissionKit",           targets: ["WaanguPermissionKit"]),
        .library(name: "WaanguNavigationKit",           targets: ["WaanguNavigationKit"]),
        .library(name: "WaanguSharedUI",                targets: ["WaanguSharedUI"]),
        .library(name: "WaanguSecurityKit",             targets: ["WaanguSecurityKit"]),
        .library(name: "WaanguOpusKit",                 targets: ["WaanguOpusKit"]),
        .library(name: "WaanguCallMediaKit",            targets: ["WaanguCallMediaKit"]),
        .library(name: "WaanguScreenShareTransport",    targets: ["WaanguScreenShareTransport"]),
        .library(name: "WaanguTranslationKit",          targets: ["WaanguTranslationKit"]),

        //Products FEATURES

        .library(name: "WaanguFeatureChat",             targets: ["WaanguFeatureChat"]),
        .library(name: "WaanguChatSDK",           targets: ["WaanguChatSDK"]),
    ],

    dependencies: [
           .package(
               url: "https://github.com/SDWebImage/SDWebImageSwiftUI.git",
               from: "3.0.0"
           ),
           .package(
               url: "https://github.com/emqx/CocoaMQTT.git",
               from: "2.1.0"
           ),
           .package(
               url: "https://github.com/sbooth/ogg-binary-xcframework",
               exact: "0.1.3"
           ),
           .package(
               url: "https://github.com/sbooth/opus-binary-xcframework",
               exact: "0.3.0"
           ),
           .package(
               url: "https://github.com/saoudrizwan/Disk",
               from: "0.6.4"
           ),
        // ── Mediasoup : uniquement CallMediaKit en a besoin ────────
        // Wrapper Swift de libmediasoupclient. Livre Mediasoup.xcframework
        // et WebRTC.xcframework en binary targets — aucun build source.
        .package(
            url: "https://github.com/VLprojects/mediasoup-client-swift",
            exact: "0.13.2"
        ),

        // ── GRDB : uniquement StorageKit en a besoin ──────────────
        // Les features et le App Target ne voient jamais GRDB directement.
        .package(
            url: "https://github.com/groue/GRDB.swift",
            exact: "7.0.0"
        ),

        .package(
            url: "https://github.com/airbnb/lottie-ios.git",
            from: "4.4.0"
        ),
    ],

    targets: [

        // MARK: - CoreKit
        .target(
            name: "WaanguCoreKit",
            dependencies: [],
            path: "Sources/CoreKit"
        ),

        .target(
            name: "WaanguRealtimeTransportKit",
            dependencies: [
                "WaanguCoreKit",
                .product(name: "CocoaMQTT", package: "CocoaMQTT"),
            ],
            path: "Sources/RealtimeTransportKit"
        ),

        // MARK: - DeviceKit
        .target(
            name: "WaanguDeviceKit",
            dependencies: ["WaanguCoreKit"],
            path: "Sources/DeviceKit"
        ),

        // MARK: - NetworkKit
        .target(
            name: "WaanguNetworkKit",
            dependencies: ["WaanguCoreKit", "WaanguDeviceKit"],
            path: "Sources/NetworkKit"
        ),

        // MARK: - StorageKit
        // GRDB ajouté ici — et UNIQUEMENT ici.
        // Aucun autre target ne doit dépendre de GRDB directement.
        .target(
            name: "WaanguStorageKit",
            dependencies: [
                "WaanguCoreKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/StorageKit"
        ),

        // MARK: - SecurityKit
        // Enterprise security and compliance: message confirmation, payment guards,
        // fraud detection, policy enforcement, AI safety, and regulatory compliance.
        // Dépend de CoreKit (Logger, protocols) et StorageKit (secure storage).
        .target(
            name: "WaanguSecurityKit",
            dependencies: ["WaanguCoreKit", "WaanguStorageKit"],
            path: "Sources/SecurityKit"
        ),

        // MARK: - AuthKit
        .target(
            name: "WaanguAuthKit",
            dependencies: ["WaanguCoreKit", "WaanguStorageKit"],
            path: "Sources/AuthKit"
        ),

        // MARK: - PermissionKit
        .target(
            name: "WaanguPermissionKit",
            dependencies: ["WaanguCoreKit"],
            path: "Sources/PermissionKit"
        ),

        // MARK: - DomainKit
        .target(
            name: "WaanguDomainKit",
            dependencies: ["WaanguCoreKit", "WaanguNetworkKit"],
            path: "Sources/DomainKit"
        ),

        // MARK: - NavigationKit
        .target(
            name: "WaanguNavigationKit",
            dependencies: [],
            path: "Sources/NavigationKit"
        ),

        // MARK: - OpusKit
        // Audio encoding/decoding : Opus codec integration for voice messages and calls.
        // Dépend de CoreKit (Logger, protocols) et Opus/Ogg XCFrameworks.
        .target(
            name: "WaanguOpusKit",
            dependencies: [
                "WaanguCoreKit",
                "WaanguStorageKit",
                .product(name: "ogg", package: "ogg-binary-xcframework"),
                .product(name: "opus", package: "opus-binary-xcframework")
            ],
            path: "Sources/OpusKit"
        ),

        // MARK: - CallMediaKit
        // SFU media for calls. Mediasoup/WebRTC are added here — and ONLY here.
        // Features talk to `CallMediaEngineProtocol` in CoreKit and never import
        // WebRTC, exactly as they never import GRDB.
        .target(
            name: "WaanguCallMediaKit",
            dependencies: [
                "WaanguCoreKit",
                .product(name: "Mediasoup", package: "mediasoup-client-swift")
            ],
            path: "Sources/CallMediaKit"
        ),

        // MARK: - ScreenShareTransport
        // Frame relay between the broadcast upload extension and the app.
        // Deliberately dependency-free: the extension links this and must stay
        // far below the 50 MB ceiling, so it can never pull in Mediasoup/WebRTC.
        .target(
            name: "WaanguScreenShareTransport",
            path: "Sources/ScreenShareTransport"
        ),

        // MARK: - SharedUI
        .target(
            name: "WaanguSharedUI",
            dependencies: [
                .product(name: "SDWebImageSwiftUI", package: "SDWebImageSwiftUI"),
            ],
            path: "Sources/SharedUI"
        ),

        // MARK: - TranslationKit
        .target(
            name: "WaanguTranslationKit",
            dependencies: ["WaanguCoreKit"],
            path: "Sources/TranslationKit",
            resources: [.process("Resources")]
        ),

        // MARK: - Features

        .target(
            name: "WaanguFeatureChat",
            dependencies: [
                "WaanguCoreKit",
                "WaanguNetworkKit",
                "WaanguSharedUI",
                "WaanguNavigationKit",
                "WaanguScreenShareTransport",
                .product(name: "Disk", package: "Disk"),
                .product(name: "Lottie", package: "lottie-ios"),
            ],
            path: "Sources/FeatureChat",
            resources: [.process("Resources")]
        ),

        // MARK: - WaanguChatSDK
        // The entry point for a host app (SDK plan, step 1.9, D-01 = b). It sits on top of
        // FeatureChat and the kits FeatureChat deliberately does not import (StorageKit, ...).
        .target(
            name: "WaanguChatSDK",
            dependencies: [
                "WaanguCoreKit", "WaanguNetworkKit", "WaanguStorageKit", "WaanguAuthKit", "WaanguDeviceKit", "WaanguSecurityKit",
                "WaanguPermissionKit", "WaanguOpusKit", "WaanguCallMediaKit", "WaanguRealtimeTransportKit", "WaanguTranslationKit",
                "WaanguDomainKit", "WaanguFeatureChat",
            ],
            path: "Sources/WaanguChatSDK"
        ),

        // MARK: - Tests
        .testTarget(
            name: "ScreenShareTransportTests",
            dependencies: ["WaanguScreenShareTransport"],
            path: "Tests/ScreenShareTransportTests"
        ),

        .testTarget(
            name: "CoreKitTests",
            dependencies: ["WaanguCoreKit"],
            path: "Tests/CoreKitTests"
        ),

        .testTarget(
            name: "DeviceKitTests",
            dependencies: ["WaanguDeviceKit", "WaanguCoreKit"],
            path: "Tests/DeviceKitTests"
        ),

        .testTarget(
            name: "NetworkKitTests",
            // AuthKit : les tests de session (plan SDK, étape 1.7) utilisent le
            // vrai `TokenManager` derrière `AuthMiddleware`.
            dependencies: ["WaanguNetworkKit", "WaanguCoreKit", "WaanguAuthKit"],
            path: "Tests/NetworkKitTests"
        ),

        // StorageKitTests peut utiliser GRDB en transitif via StorageKit
        .testTarget(
            name: "StorageKitTests",
            dependencies: ["WaanguStorageKit", "WaanguCoreKit"],
            path: "Tests/StorageKitTests"
        ),

        // StorageKit (and GRDB through it) is needed here, not by FeatureChat
        // itself: `@testable import` requires the whole transitive module chain
        // to be resolvable, and the call log tests drive a real SQLite store.
        .testTarget(
            name: "FeatureChatTests",
            // SecurityKit : les tests du garde de confirmation instancient
            // l'implémentation réelle (`PaymentConfirmationGuard`) avec un
            // vérificateur de signature scripté.
            dependencies: ["WaanguFeatureChat", "WaanguStorageKit", "WaanguSecurityKit"],
            path: "Tests/FeatureChatTests"
        ),

        .testTarget(
            name: "WaanguChatSDKTests",
            dependencies: ["WaanguChatSDK", "WaanguCoreKit", "WaanguStorageKit", "WaanguAuthKit"],
            path: "Tests/WaanguChatSDKTests"
        ),

        .testTarget(
            name: "SharedUITests",
            dependencies: ["WaanguSharedUI"],
            path: "Tests/SharedUITests"
        ),
    ]
)
