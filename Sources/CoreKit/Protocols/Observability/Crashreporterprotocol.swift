//
//  Crashreporterprotocol.swift
//  AppModules
//
//  Created by Asyst on 6/5/26.
//

// MARK: - CoreKit/Observability/CrashReporterProtocol.swift
//
// Module  : CoreKit
// Rôle    : Contrat pour le crash reporting et le error tracking.
//           Les features reportent des erreurs et ajoutent du contexte
//           sans savoir si c'est Sentry, Crashlytics, ou Bugsnag.
//
// Design  : Les breadcrumbs tracent le parcours utilisateur.
//           Quand un crash ou une erreur survient, Sentry montre
//           les 100 dernières breadcrumbs → on voit exactement
//           ce que l'utilisateur faisait avant le crash.

import Foundation

// MARK: - CrashReporterProtocol

/// Contrat pour le crash reporting et le error tracking.
///
/// ```swift
/// // FeatureRide — import CoreKit
/// class RideTrackingViewModel {
///     private let crashReporter: any CrashReporterProtocol
///
///     func onTrackingError(_ error: Error) {
///         crashReporter.capture(error, context: [
///             "tripId": tripId,
///             "driverDistance": distance
///         ])
///     }
/// }
/// ```
public protocol CrashReporterProtocol: Sendable {

    /// Capture une erreur non-fatale avec contexte optionnel.
    func capture(_ error: Error, context: [String: Any]?)

    /// Capture un message (pas une erreur, juste un événement notable).
    func captureMessage(_ message: String, level: CrashReportLevel)

    /// Ajoute un breadcrumb (trace du parcours utilisateur).
    func addBreadcrumb(
        category: String,
        message: String,
        level: CrashReportLevel,
        data: [String: Any]?
    )

    /// Associe un utilisateur aux rapports (après login).
    func setUser(id: String?, email: String?, username: String?)

    /// Ajoute une paire clé-valeur au contexte global (visible dans chaque rapport).
    func setTag(key: String, value: String)

    /// Ajoute du contexte structuré (visible dans la section "Additional Data").
    func setContext(key: String, value: [String: Any])
}

// MARK: - Convenience

extension CrashReporterProtocol {

    /// Capture une erreur sans contexte.
    public func capture(_ error: Error) {
        capture(error, context: nil)
    }

    /// Breadcrumb simple sans data.
    public func addBreadcrumb(category: String, message: String) {
        addBreadcrumb(category: category, message: message, level: .info, data: nil)
    }

    /// Breadcrumb de navigation (l'utilisateur a ouvert un écran).
    public func addNavigationBreadcrumb(from: String, to: String) {
        addBreadcrumb(
            category: "navigation",
            message: "\(from) → \(to)",
            level: .info,
            data: nil
        )
    }

    /// Breadcrumb d'action utilisateur (tap, swipe, etc.).
    public func addUserActionBreadcrumb(action: String, target: String) {
        addBreadcrumb(
            category: "user",
            message: "\(action): \(target)",
            level: .info,
            data: nil
        )
    }

    /// Efface l'utilisateur (au logout).
    public func clearUser() {
        setUser(id: nil, email: nil, username: nil)
    }
}

// MARK: - CrashReportLevel

/// Niveau de sévérité pour les messages et breadcrumbs.
public enum CrashReportLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
    case fatal
}
