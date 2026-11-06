//
//  OperationalKillSwitch.swift
//  CoreKit
//
//  Suspension immédiate — Bloc 4 §44 (GAP-13, côté client).
//

import Foundation

/// Ce que le backend a suspendu, et que le client doit cesser de proposer.
///
/// **Le kill switch est serveur.** Le client ne décide de rien : il consulte, et
/// il ferme. Ce qui lui appartient est étroit et non négociable — honorer la
/// suspension **avant** de proposer une action, pas après l'avoir tentée.
///
/// Fermé par défaut : un état de suspension qu'on n'a pas pu lire est traité
/// comme une suspension. L'inverse laisserait passer des opérations pendant
/// exactement l'incident que le kill switch existe pour arrêter.
public protocol OperationalKillSwitchProviding: Sendable {

    /// Suspensions en vigueur. Toute erreur donne « tout suspendu ».
    func activeSuspensions() async -> KillSwitchState
}

// MARK: - État

public struct KillSwitchState: Sendable, Hashable, Codable {

    public let suspendedProviders: Set<String>
    public let suspendedProducts: Set<String>
    public let suspendedWorkflows: Set<String>
    public let suspendedPaymentMethods: Set<String>
    public let suspendedCountries: Set<String>

    /// Coupure totale de la couche financière. Le levier de dernier recours.
    public let entireFinancialLayerSuspended: Bool

    /// Clé de message expliquant la suspension. Affichée telle quelle.
    public let reasonKey: String?

    public init(
        suspendedProviders: Set<String> = [], suspendedProducts: Set<String> = [],
        suspendedWorkflows: Set<String> = [], suspendedPaymentMethods: Set<String> = [],
        suspendedCountries: Set<String> = [],
        entireFinancialLayerSuspended: Bool = false,
        reasonKey: String? = nil
    ) {
        self.suspendedProviders = suspendedProviders
        self.suspendedProducts = suspendedProducts
        self.suspendedWorkflows = suspendedWorkflows
        self.suspendedPaymentMethods = suspendedPaymentMethods
        self.suspendedCountries = suspendedCountries
        self.entireFinancialLayerSuspended = entireFinancialLayerSuspended
        self.reasonKey = reasonKey
    }

    /// Rien n'est suspendu.
    public static let none = KillSwitchState()

    /// Tout est suspendu. **Repli quand l'état n'a pas pu être lu.**
    public static let everything = KillSwitchState(
        entireFinancialLayerSuspended: true,
        reasonKey: "finance.killswitch.unavailable"
    )
}

public extension KillSwitchState {

    /// `true` si cette opération peut être proposée.
    ///
    /// Les cinq dimensions comptent ensemble : une opération autorisée par
    /// quatre d'entre elles et suspendue par la cinquième reste suspendue.
    func allows(
        providerID: String? = nil,
        productID: String? = nil,
        workflowID: String? = nil,
        paymentMethod: String? = nil,
        country: String? = nil
    ) -> Bool {
        if entireFinancialLayerSuspended { return false }
        if let providerID, suspendedProviders.contains(providerID) { return false }
        if let productID, suspendedProducts.contains(productID) { return false }
        if let workflowID, suspendedWorkflows.contains(workflowID) { return false }
        if let paymentMethod, suspendedPaymentMethods.contains(paymentMethod) { return false }
        if let country, suspendedCountries.contains(country) { return false }
        return true
    }

    var isAnythingSuspended: Bool {
        entireFinancialLayerSuspended
            || !suspendedProviders.isEmpty || !suspendedProducts.isEmpty
            || !suspendedWorkflows.isEmpty || !suspendedPaymentMethods.isEmpty
            || !suspendedCountries.isEmpty
    }
}
