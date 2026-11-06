//
//  FinancialCapabilityGates.swift
//  CoreKit
//
//  Portes d'activation d'une capacité financière — Bloc 5 §16 (GAP5-10).
//
//  **BACKEND CONTRACT REQUIRED** — `GET /v1/financial/capabilities`.
//

import Foundation

/// Ce qui rend une capacité financière disponible, ou non.
///
/// > « Une fonctionnalité ne devient disponible que si **toutes** les portes
/// > requises sont ouvertes. » (§16)
///
/// Les quatre portes sont indépendantes et se cumulent. Une capacité activée par
/// le produit, licenciée et approuvée par le partenaire mais refusée par la
/// conformité reste fermée — et l'inverse aussi. Les mélanger en un seul drapeau
/// ferait perdre l'information qui explique *pourquoi* c'est fermé, alors que
/// c'est précisément ce que le support et l'utilisateur ont besoin de savoir.
public struct FinancialCapability: Codable, Sendable, Hashable, Identifiable {

    public let capabilityID: String
    public var id: String { capabilityID }

    public let country: String
    public let currency: String?

    // ── Les quatre portes ────────────────────────────────────

    /// Le produit est activé pour ce marché.
    public let enabled: Bool

    /// Waangu détient la licence requise ici. **Absence = interdiction.**
    public let licensed: Bool

    /// La conformité a approuvé cette capacité pour ce contexte.
    public let complianceApproved: Bool

    /// Le partenaire agréé l'a approuvée de son côté.
    public let partnerApproved: Bool

    // ── Validité ─────────────────────────────────────────────

    public let effectiveFrom: Date
    public let effectiveUntil: Date?

    /// Version de configuration ayant produit cette capacité.
    /// Transportée sur toute mutation qu'elle autorise — voir `ConfigurationVersions`.
    public let configVersion: String

    public init(
        capabilityID: String, country: String, currency: String? = nil,
        enabled: Bool, licensed: Bool, complianceApproved: Bool, partnerApproved: Bool,
        effectiveFrom: Date, effectiveUntil: Date? = nil, configVersion: String
    ) {
        self.capabilityID = capabilityID
        self.country = country
        self.currency = currency
        self.enabled = enabled
        self.licensed = licensed
        self.complianceApproved = complianceApproved
        self.partnerApproved = partnerApproved
        self.effectiveFrom = effectiveFrom
        self.effectiveUntil = effectiveUntil
        self.configVersion = configVersion
    }
}

// MARK: - Verdict

/// Pourquoi une capacité est fermée.
///
/// Nommer la porte fermée n'est pas un confort d'interface : « indisponible dans
/// votre pays » et « en cours de revue de conformité » appellent des gestes
/// différents de la part de l'utilisateur et du support.
public enum CapabilityClosure: String, Sendable, Equatable, CaseIterable {
    case notEnabled        = "NOT_ENABLED"
    case notLicensed       = "NOT_LICENSED"
    case complianceWithheld = "COMPLIANCE_WITHHELD"
    case partnerWithheld   = "PARTNER_WITHHELD"
    case notYetEffective   = "NOT_YET_EFFECTIVE"
    case expired           = "EXPIRED"

    /// Clé de message. Jamais une phrase composée ici.
    public var messageKey: String { "finance.capability.closed.\(rawValue.lowercased())" }
}

public extension FinancialCapability {

    /// La porte fermée, ou `nil` si toutes sont ouvertes.
    ///
    /// L'ordre du contrôle est délibéré : la licence l'emporte sur la conformité,
    /// qui l'emporte sur le partenaire. On rapporte la cause la plus structurelle,
    /// celle qui ne se lèvera pas d'elle-même.
    func closure(asOf now: Date = Date()) -> CapabilityClosure? {
        if now < effectiveFrom { return .notYetEffective }
        if let until = effectiveUntil, now >= until { return .expired }
        if !licensed { return .notLicensed }
        if !complianceApproved { return .complianceWithheld }
        if !partnerApproved { return .partnerWithheld }
        if !enabled { return .notEnabled }
        return nil
    }

    /// `true` si les quatre portes sont ouvertes **et** la période courante.
    func isAvailable(asOf now: Date = Date()) -> Bool { closure(asOf: now) == nil }
}

// MARK: - Fourniture

/// Donne les capacités financières du contexte courant.
public protocol FinancialCapabilityGateProviding: Sendable {

    /// Ne lève jamais : toute erreur donne une liste vide, donc tout fermé.
    ///
    /// L'absence de `throws` est le même choix de sûreté que partout ailleurs
    /// dans ce dépôt — un `try?` produirait `nil`, et un site d'appel finirait
    /// par écrire `?? .allOpen` « le temps de déboguer ».
    func capabilities() async -> [FinancialCapability]

    func invalidate() async
}

public extension FinancialCapabilityGateProviding {

    /// Verdict pour une capacité nommée.
    ///
    /// Une capacité **absente du catalogue est fermée**, et non ouverte par
    /// défaut : le silence du backend n'est pas une autorisation.
    func closure(for capabilityID: String, asOf now: Date = Date()) async -> CapabilityClosure? {
        let all = await capabilities()
        guard let match = all.first(where: { $0.capabilityID == capabilityID }) else {
            return .notEnabled
        }
        return match.closure(asOf: now)
    }

    func isAvailable(_ capabilityID: String, asOf now: Date = Date()) async -> Bool {
        await closure(for: capabilityID, asOf: now) == nil
    }
}

// MARK: - Identifiants du Bloc 5

/// Les capacités que le Bloc 5 fait intervenir.
///
/// Des constantes plutôt que des chaînes libres : une faute de frappe dans un
/// identifiant de capacité ouvrirait une porte que personne n'a voulue —
/// non, elle la fermerait, puisque l'absence vaut fermeture. Mais elle la
/// fermerait **silencieusement**, ce qui est presque aussi mauvais.
public enum FinancialCapabilityID {
    // ── Clés de gouvernance Chat Core (INTEGRATION_CHAT_FINANCE.md §1.3–1.4) ──
    public static let sendMoney       = "SEND_MONEY"
    public static let requestMoney    = "REQUEST_MONEY"
    public static let payBill         = "PAY_BILL"
    public static let scanQR          = "SCAN_QR"
    public static let splitBill       = "SPLIT_BILL"
    public static let topUp           = "TOP_UP"
    public static let cashIn          = "CASH_IN"
    public static let cashOut         = "CASH_OUT"

    // ── Bloc 5 ──
    public static let remittance      = "REMITTANCE"
    public static let fxConversion    = "FX_CONVERSION"
    public static let multiCurrency   = "MULTI_CURRENCY_WALLET"
    public static let creditDiscovery = "CREDIT_DISCOVERY"
    public static let creditApply     = "CREDIT_APPLY"
    public static let savings         = "SAVINGS"
    public static let investment      = "INVESTMENT"
    public static let pfm             = "PFM"
}
