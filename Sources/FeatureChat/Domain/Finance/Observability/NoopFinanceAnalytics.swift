//
//  NoopFinanceAnalytics.swift
//  FeatureChat
//
//  Analytics inerte, en attendant l'injection de l'implémentation réelle.

import Foundation
import WaanguCoreKit

/// Ne publie rien.
///
/// `ChatDependencies` ne porte pas encore d'`AnalyticsProtocol` — l'ajouter
/// toucherait tous les sites de construction du graphe, ce qui déborde du
/// périmètre. Ce repli garde `FinanceTelemetry` construit et appelable : les
/// événements traversent le code, ils ne quittent simplement pas l'appareil.
///
/// Conséquence assumée : l'alerte sur `finance.event.version_rejected` — le
/// signal clé du §9.4 — ne remonte nulle part tant que ce type est en place. Le
/// rejet reste visible dans les logs via `FinanceTelemetry`, pas dans un dashboard.
struct NoopFinanceAnalytics: AnalyticsProtocol {
    func logEvent(_ name: String, parameters: [String: Any]?) {}
    func setUserProperty(_ value: String?, forName name: String) {}
    func setUserId(_ userId: String?) {}
    func logScreenView(screenName: String, screenClass: String?) {}
}
