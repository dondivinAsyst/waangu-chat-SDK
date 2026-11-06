// MARK: - NetworkKit/APIClient/APIClientFactory.swift
//
// Factory qui construit APIClient depuis les dépendances injectées.
// Résout DeviceConfiguration via AdaptivePolicyResolver au moment de la création.
//
//import Foundation
//import CoreKit
//import DeviceKit
//
//final class APIClientFactory {
//
//    private let appConfiguration: any AppConfigurationProviding
//    private let logger: AppLogger
//    private let performanceMonitor: any PerformanceMonitorProtocol
//    private let networkMonitor: any NetworkMonitoringProtocol
//    private let deviceInfoProvider: any DeviceInfoProvidingProtocol
//    private let tokenManager: any TokenManagerProtocol
//    private let basicAuthToken: String?
//
//    init(
//        appConfiguration: any AppConfigurationProviding,
//        logger: AppLogger,
//        performanceMonitor: any PerformanceMonitorProtocol,
//        networkMonitor: any NetworkMonitoringProtocol,
//        deviceInfoProvider: any DeviceInfoProvidingProtocol,
//        tokenManager: any TokenManagerProtocol,
//        basicAuthToken: String? = nil
//    ) {
//        self.appConfiguration = appConfiguration
//        self.logger = logger
//        self.performanceMonitor = performanceMonitor
//        self.networkMonitor = networkMonitor
//        self.deviceInfoProvider = deviceInfoProvider
//        self.tokenManager = tokenManager
//        self.basicAuthToken = basicAuthToken
//    }
//
//    func make() async throws -> any APIClientProtocol {
//        let snapshot = deviceInfoProvider.captureSnapshot()
//        let deviceTier = DeviceTier(deviceInfoSnapshot: snapshot, logger: logger)
//
//        let resolver = AdaptivePolicyResolver(deviceTier: deviceTier)
//        let initialConfig = await resolver.resolve(
//            performanceMonitor: performanceMonitor,
//            networkMonitor: networkMonitor
//        )
//
//        let session = URLSession(configuration: .default)
//        let circuitBreaker = CircuitBreakerServiceImpl(logger: logger)
//        let rateLimiter = RateLimiterServiceImpl(logger: logger)
//        let dedupService = DedupServiceImpl()
//
//        let middlewares: [any HTTPMiddlewareProtocol] = [
//            LoggingMiddleware(logger: logger),
//            AuthMiddleware(tokenManager: tokenManager, logger: logger, basicAuthToken: basicAuthToken)
//        ]
//
//        return await APIClient.makeConfigured(
//            baseURL: appConfiguration.baseURL,
//            session: session,
//            middlewares: middlewares,
//            circuitBreaker: circuitBreaker,
//            rateLimiter: rateLimiter,
//            dedupService: dedupService,
//            logger: logger,
//            runTimeConfig: initialConfig,
//            networkMonitor: networkMonitor,
//            performanceMonitor: performanceMonitor,
//            policyResolver: resolver
//        )
//    }
//}



// MARK: - NetworkKit/APIClient/APIClientFactory.swift
//
// Factory qui construit APIClient depuis les dépendances injectées.
// Résout DeviceConfiguration via AdaptivePolicyResolver au moment de la création.
//
// Améliorations vs version originale :
// 1. CacheMiddleware injecté dans la pipeline (était absent — bug critique)
// 2. URLSession configurée avec .ephemeral pour déléguer entièrement la gestion
//    du cache au CacheMiddleware (évite les interférences de URLCache système)
// 3. URLCache dédiée injectée dans CacheMiddleware : 20 MB mémoire / 100 MB disque
// 4. Ordre d'injection explicitement documenté et respecté :
//       AuthMiddleware → LoggingMiddleware → CacheMiddleware
// 5. makeConfigured est async throws pour propager les erreurs d'initialisation

import Foundation
import WaanguCoreKit
import WaanguDeviceKit

final class APIClientFactory {

    // MARK: - Dependencies
    private let baseURL : String
    private let doctorBaseURL: String?
    private let appConfiguration: any AppConfigurationProviding
    private let logger: AppLogger
    private let performanceMonitor: any PerformanceMonitorProtocol
    private let networkMonitor: any NetworkMonitoringProtocol
    private let deviceInfoProvider: any DeviceInfoProvidingProtocol
    private let tokenManager: any TokenManagerProtocol
    private let basicAuthToken: String?

    // MARK: - Init

    /// Bloc 9, G9-01 — broches d'épinglage. Défaut sans épinglage pour que
    /// l'activation soit un geste explicite de l'AppTarget, pas un effet de bord.
    private let certificatePins: any CertificatePinProviding

    init(
        baseURL : String,
        doctorBaseURL: String? = nil,
        appConfiguration: any AppConfigurationProviding,
        logger: AppLogger,
        performanceMonitor: any PerformanceMonitorProtocol,
        networkMonitor: any NetworkMonitoringProtocol,
        deviceInfoProvider: any DeviceInfoProvidingProtocol,
        tokenManager: any TokenManagerProtocol,
        basicAuthToken: String? = nil,
        certificatePins: any CertificatePinProviding = NoCertificatePinning()
    ) {
        self.appConfiguration = appConfiguration
        self.logger = logger
        self.performanceMonitor = performanceMonitor
        self.networkMonitor = networkMonitor
        self.deviceInfoProvider = deviceInfoProvider
        self.tokenManager = tokenManager
        self.basicAuthToken = basicAuthToken
        self.certificatePins = certificatePins
        self.baseURL = baseURL
        self.doctorBaseURL = doctorBaseURL
    }

    // MARK: - Factory

    func make() async throws -> any APIClientProtocol {

        // 1. Résolution de la configuration adaptative initiale
        let snapshot = deviceInfoProvider.captureSnapshot()
        let deviceTier = DeviceTier(deviceInfoSnapshot: snapshot, logger: logger)
        let resolver = AdaptivePolicyResolver(deviceTier: deviceTier)
        let initialConfig = await resolver.resolve(
            performanceMonitor: performanceMonitor,
            networkMonitor: networkMonitor
        )

        // 2. Session .ephemeral — URLCache système désactivé.
        //    La gestion du cache est entièrement déléguée au CacheMiddleware
        //    via sa propre URLCache dédiée. Cela évite les conflits de politique
        //    entre CachePolicy de l'endpoint et le comportement natif d'URLCache.
        let sessionConfig = URLSessionConfiguration.default  

        // Bloc 9, G9-01 — épinglage SPKI. Le délégué laisse passer les hôtes
        // sans politique : injecter `NoCertificatePinning` revient exactement au
        // comportement d'avant, ce qui rend l'activation progressive.
        let pinningDelegate = CertificatePinningDelegate(pins: certificatePins)
        let session = URLSession(
            configuration: sessionConfig,
            delegate: pinningDelegate,
            delegateQueue: nil
        )

        // 3. Services
        let circuitBreaker = CircuitBreakerServiceImpl(logger: logger)
        let rateLimiter = RateLimiterServiceImpl(logger: logger)
        let dedupService = DedupServiceImpl()

        // 4. Cache store dédié (isolé de URLCache.shared)
        let tier =  await deviceTier.getDeviceTier()
        let cacheStore = makeAdaptiveCacheStore(tier : tier)

        // 5. Pipeline de middlewares — ordre contractuel strict :
        //
        //   ┌─────────────────────────────────────────────────────────┐
        //   │  prepare()     : AuthMiddleware → Logging → Cache       │
        //   │  process(res)  : Cache → Logging → Auth   (reversed)    │
        //   │  process(err)  : Auth → Logging → Cache                 │
        //   └─────────────────────────────────────────────────────────┘
        //
        //   AuthMiddleware   — en tête pour que le token soit injecté avant logging
        //   LoggingMiddleware — capture la requête finale (avec auth headers)
        //   CacheMiddleware  — en dernier : lit/écrit après que la requête soit complète
        var middlewares: [any HTTPMiddlewareProtocol] = [
            AuthMiddleware(
                tokenManager: tokenManager,
                logger: logger,
                basicAuthToken: basicAuthToken
            )
        ]
 
        middlewares.append(LoggingMiddleware(logger: logger))
        middlewares.append(CacheMiddleware(cache: cacheStore, logger: logger))

        // 6. Construction du client
        return await APIClient.makeConfigured(
            baseURL: baseURL,
            session: session,
            middlewares: middlewares,
            circuitBreaker: circuitBreaker,
            rateLimiter: rateLimiter,
            dedupService: dedupService,
            logger: logger,
            runTimeConfig: initialConfig,
            networkMonitor: networkMonitor,
            performanceMonitor: performanceMonitor,
            policyResolver: resolver
        )
    }

    // MARK: - Private helpers

    /// Crée un URLCache dédié, isolé de `URLCache.shared`.
    /// Le dossier `networkCache` dans les caches de l'app garantit la persistance
    /// entre sessions sans polluer le cache système.
    /// // MARK: - Cache configuration

    
    private func makeAdaptiveCacheStore(tier: DeviceTierSnapshot) -> URLCache {
       
        let config: (memory: Int, disk: Int)

       switch tier {
       case .lowEnd:
           config = (10, 50)
       case .midRange:
           config = (30, 100)
       case .premium:
           config = (50, 200)
       }

        let cacheURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("networkCache")

        return URLCache(
            memoryCapacity: config.memory * 1024 * 1024,
            diskCapacity: config.disk * 1024 * 1024,
            directory: cacheURL
        )
    }
}

// Public helper to create an APIClient from outside the NetworkKit package
// without exposing the internal `APIClientFactory` type. This keeps the
// factory implementation internal while offering a stable API for other
// modules (e.g. the App target) to create dedicated clients when needed.
public enum APIClientFactoryProvider {
    public static func makeClient(
        baseURL: String,
        doctorBaseURL: String? = nil,
        appConfiguration: any AppConfigurationProviding,
        logger: AppLogger,
        performanceMonitor: any PerformanceMonitorProtocol,
        networkMonitor: any NetworkMonitoringProtocol,
        deviceInfoProvider: any DeviceInfoProvidingProtocol,
        tokenManager: any TokenManagerProtocol,
        basicAuthToken: String? = nil,
        // Bloc 9, G9-01. Défaut sans épinglage : le comportement est identique
        // à avant tant que l'AppTarget ne fournit pas de broches.
        certificatePins: any CertificatePinProviding = NoCertificatePinning()
    ) async throws -> any APIClientProtocol {
        let factory = APIClientFactory(
            baseURL: baseURL,
            doctorBaseURL: doctorBaseURL,
            appConfiguration: appConfiguration,
            logger: logger,
            performanceMonitor: performanceMonitor,
            networkMonitor: networkMonitor,
            deviceInfoProvider: deviceInfoProvider,
            tokenManager: tokenManager,
            basicAuthToken: basicAuthToken,
            certificatePins: certificatePins
        )
        return try await factory.make()
    }
}
