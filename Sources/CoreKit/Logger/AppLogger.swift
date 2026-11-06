//
//  AppLogger.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//
import OSLog
import Foundation

// MARK: - LogObserverProtocol

/// Protocole d'observation des logs.
/// Permet d'injecter des destinations externes (Sentry, Datadog, fichier...)
/// sans que AppLogger connaisse ces SDKs.
///
/// Usage dans ObservabilityKit :
/// ```swift
/// final class SentryLogObserver: LogObserverProtocol {
///     func didLog(_ message: String, level: LogLevel) {
///         SentrySDK.capture(message: message, level: level.sentryLevel)
///     }
/// }
/// // Au bootstrap :
/// await AppLogger.shared.addObserver(SentryLogObserver())
/// ```
public protocol LogObserverProtocol: Sendable {
    func didLog(_ message: String, level: LogLevel) async
}

// MARK: - AppLogger

/// Logger central thread-safe basé sur OSLog.
///
/// - `os.Logger` est la destination principale : visible dans Xcode ET Console.app
/// - Les observers (Sentry, fichier...) sont notifiés après chaque log
/// - `minLevel` permet de filtrer les logs en production
public actor AppLogger: AppLoggerProtocol {

    // MARK: - Singleton
    public static let shared = AppLogger()

    // MARK: - State
    private let osLogger: os.Logger
    private var observers: [any LogObserverProtocol] = []

    /// Niveau minimum de log.
    /// - DEBUG builds : `.debug` (tout passe)
    /// - RELEASE builds : `.warning` (réduit le bruit en production)
    public var minLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }()

    // MARK: - Init
    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.waangu.driver"
        self.osLogger = os.Logger(subsystem: subsystem, category: "App")
    }

    // MARK: - Observer Management

    /// Ajoute un observer de logs (Sentry, fichier, analytics...).
    /// Appelé depuis ObservabilityKit au bootstrap — jamais depuis une feature.
    public func addObserver(_ observer: any LogObserverProtocol) async {
        observers.append(observer)
    }

    public func removeAllObservers() async {
        observers.removeAll()
    }

    // MARK: - Log

    /// Enregistre un message de log.
    ///
    /// - `os.Logger` reçoit le format court (il horodate lui-même)
    /// - Les observers reçoivent le format long (timestamp + niveau + fichier)
    public func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        guard level >= minLevel else { return }

        // Format court pour os.Logger — timestamp ajouté automatiquement par OSLog
        let shortMessage = LogFormatter.formatShort(message, file: file, function: function, line: line)

        // Format long pour les observers externes
        let fullMessage = LogFormatter.format(message, level: level, file: file, function: function, line: line)

        // Écriture OSLog
        //
        // DEBUG : `.public`, lisible dans Xcode et Console.
        // RELEASE : `.private` (plan SDK, étape 1.12) — le système affiche
        // `<private>` hors d'un appareil de développement, donc ni contenu de
        // message ni identifiant ne sortent des logs d'un téléphone client.
        // `privacy:` doit être une constante pour OSLog, d'où les deux branches.
        #if DEBUG
        switch level {
        case .debug:
            osLogger.debug("\(shortMessage, privacy: .public)")
        case .info:
            osLogger.info("\(shortMessage, privacy: .public)")
        case .warning:
            osLogger.warning("\(shortMessage, privacy: .public)")
        case .error:
            osLogger.error("\(shortMessage, privacy: .public)")
        case .critical:
            osLogger.critical("\(shortMessage, privacy: .public)")
        }
        #else
        switch level {
        case .debug:
            break
        case .info:
            osLogger.info("\(shortMessage, privacy: .private)")
        case .warning:
            osLogger.warning("\(shortMessage, privacy: .private)")
        case .error:
            osLogger.error("\(shortMessage, privacy: .private)")
        case .critical:
            osLogger.critical("\(shortMessage, privacy: .private)")
        }
        #endif

        // Notification des observers (Sentry, fichier, remote...)
        for observer in observers {
            await observer.didLog(fullMessage, level: level)
        }
    }
}
