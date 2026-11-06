//
//  AnalyticsProtocol.swift
//  AppModules
//
//  Created by Asyst on 6/5/26.
//

// MARK: - CoreKit/Observability/AnalyticsProtocol.swift


import Foundation

// MARK: - AnalyticsProtocol

/// Contrat d'analytics — les features importent CoreKit uniquement.
///
/// ```swift
/// // FeatureWallet — import CoreKit
/// class WalletViewModel {
///     private let analytics: any AnalyticsProtocol
///
///     func onTransactionCompleted(amount: Double) {
///         analytics.logEvent("transaction_completed", parameters: [
///             "amount": amount,
///             "currency": "BIF"
///         ])
///     }
/// }
/// ```
public protocol AnalyticsProtocol: Sendable {

    /// Logue un événement avec des paramètres optionnels.
    func logEvent(_ name: String, parameters: [String: Any]?)

    /// Définit une propriété utilisateur (segmentation dans le dashboard).
    func setUserProperty(_ value: String?, forName name: String)

    /// Associe un userId aux événements (après login).
    func setUserId(_ userId: String?)

    /// Logue un écran visité (screen tracking).
    func logScreenView(screenName: String, screenClass: String?)
}

// MARK: - Convenience

extension AnalyticsProtocol {

    /// Logue un événement sans paramètres.
    public func logEvent(_ name: String) {
        logEvent(name, parameters: nil)
    }

    /// Logue un écran sans classe.
    public func logScreenView(screenName: String) {
        logScreenView(screenName: screenName, screenClass: nil)
    }
}

// MARK: - AnalyticsEvent

/// Événement analytics typé — alternative au name + parameters.
///
/// Les features peuvent définir des enums conformes pour le type-safety :
/// ```swift
/// enum WalletAnalytics: AnalyticsEvent {
///     case transactionCompleted(amount: Double, currency: String)
///
///     var name: String { "transaction_completed" }
///     var parameters: [String: Any]? {
///         switch self {
///         case .transactionCompleted(let amount, let currency):
///             return ["amount": amount, "currency": currency]
///         }
///     }
/// }
///
/// analytics.log(WalletAnalytics.transactionCompleted(amount: 5000, currency: "BIF"))
/// ```
public protocol AnalyticsEvent: Sendable {
    var name: String { get }
    var parameters: [String: Any]? { get }
}

extension AnalyticsProtocol {
    /// Logue un événement typé.
    public func log(_ event: any AnalyticsEvent) {
        logEvent(event.name, parameters: event.parameters)
    }
}
