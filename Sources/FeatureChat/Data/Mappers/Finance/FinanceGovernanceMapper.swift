//
//  FinanceGovernanceMapper.swift
//  FeatureChat
//
//  Traduit l'amorçage Chat Core vers les contrats que les écrans consomment déjà.
//

import Foundation
import WaanguCoreKit

/// Ce que l'amorçage a rapporté, lu d'un bloc.
struct FinanceSessionSnapshot: Equatable, Sendable {
    let experience: ExperienceConfigDTO
    let governance: GovernanceSnapshotDTO
    let security: SecurityCapabilitiesDTO
    /// `nil` si l'état de reprise n'a pas pu être lu : la session reste verrouillée.
    let resume: ResumeStateDTO?
    let fetchedAt: Date
}

/// Correspondances gouvernance → contrats existants.
///
/// **Règle unique : ce qui n'est pas affirmé est fermé.** Un champ absent, un
/// état inconnu, une capacité non listée ne s'ouvrent jamais par défaut.
enum FinanceGovernanceMapper {

    /// États exécutables pour le grand public — §1.3. `INTERNAL` et
    /// `PARTNER_ONLY` sont servis côté serveur à des comptes réservés ; le
    /// client grand public les masque.
    static let executableStates: Set<String> = ["GENERAL", "PILOT", "LIMITED"]

    /// Durée de validité d'un instantané quand la reprise n'annonce pas d'expiration.
    static let snapshotLifetime: TimeInterval = 300

    /// Droits de session publiés par `GET /security/capabilities` — §1.5.
    enum SecurityRight {
        static let financeRead = "FINANCE_READ"
        static let paymentPrepare = "PAYMENT_PREPARE"
        static let paymentConfirm = "PAYMENT_CONFIRM"
        /// Haut risque : fermé tant que le serveur ne l'accorde pas (CF_068).
        static let cashOut = "CASH_OUT"
    }

    /// Clés de gouvernance qui exigent en plus un droit de session à haut risque.
    ///
    /// Le contrat liste aussi `ADD_BENEFICIARY`, `ADD_CARD`, `HIGH_VALUE_PAYMENT`
    /// et `EXPORT_DATA` : aucun parcours de l'app ne les met en œuvre, et le seuil
    /// « haute valeur » n'est pas publié — le serveur refuse par CF_068.
    static let highRiskRights: [String: String] = ["CASH_OUT": SecurityRight.cashOut]

    // MARK: - Capacités — FinancialCapabilityGateProviding

    /// Identifiants de capacité client pour une clé de gouvernance.
    static func capabilityIDs(forGovernanceKey key: String) -> [String] {
        switch key {
        case "FX":     return [FinancialCapabilityID.fxConversion]
        case "CREDIT": return [FinancialCapabilityID.creditDiscovery, FinancialCapabilityID.creditApply]
        default:       return [key]
        }
    }

    static func capabilities(from snapshot: FinanceSessionSnapshot) -> [FinancialCapability] {
        let governance = snapshot.governance
        let configVersion = governance.configHash ?? String(governance.configGeneration ?? 0)
        let countryApproved = governance.countryApproved ?? false

        return governance.capabilities.flatMap { decision -> [FinancialCapability] in
            let securityGranted = highRiskRights[decision.capabilityKey]
                .map(snapshot.security.allows) ?? true
            let enabled = (decision.allowed ?? false)
                && executableStates.contains(decision.state ?? "")
                && !(decision.killSwitch ?? false)
                && securityGranted
            let licensed = countryApproved && (decision.countryApproved ?? false)
            return capabilityIDs(forGovernanceKey: decision.capabilityKey).map { id in
                FinancialCapability(
                    capabilityID: id,
                    country: decision.country ?? governance.country ?? "XX",
                    currency: governance.currency,
                    enabled: enabled, licensed: licensed,
                    // Le gel conformité est décidé par intention (CF_010), pas par capacité.
                    complianceApproved: true, partnerApproved: true,
                    effectiveFrom: .distantPast, effectiveUntil: nil,
                    configVersion: configVersion
                )
            }
        }
    }

    // MARK: - Coupe-circuit — OperationalKillSwitchProviding

    static func killSwitch(from snapshot: FinanceSessionSnapshot) -> KillSwitchState {
        let entireLayer = (snapshot.experience.killSwitchGlobal ?? false)
            || (snapshot.experience.killSwitchCountry ?? false)
            || (snapshot.governance.killSwitchGlobal ?? false)
            || (snapshot.governance.killSwitchCountry ?? false)

        let suspendedProducts = snapshot.governance.capabilities
            .filter { $0.killSwitch == true }
            .flatMap { entryKinds(forGovernanceKey: $0.capabilityKey) }
            .map(\.rawValue)

        return KillSwitchState(
            suspendedProducts: Set(suspendedProducts),
            entireFinancialLayerSuspended: entireLayer,
            reasonKey: entireLayer ? "finance.killswitch.suspended" : nil
        )
    }

    static func entryKinds(forGovernanceKey key: String) -> [FinanceEntryKind] {
        let ids = Set(capabilityIDs(forGovernanceKey: key))
        return FinanceEntryKind.allCases.filter { kind in kind.capabilityID.map(ids.contains) ?? false }
    }

    // MARK: - Statut de session

    static func status(from snapshot: FinanceSessionSnapshot) -> FinanceSessionStatus {
        let safeMode = snapshot.experience.safeMode ?? snapshot.governance.safeMode
        let security = snapshot.security
        return FinanceSessionStatus(
            paymentsAllowed: snapshot.experience.paymentsAllowed ?? false,
            // Sans état de reprise lisible, la session est verrouillée. Les deux
            // `financialActionsLocked` comptent : experience (§1.2, « ne pas
            // appeler Send Money tant que… ») et sécurité (§1.5, epoch périmée).
            writeLocked: (snapshot.resume?.locked ?? true)
                || (snapshot.experience.financialActionsLocked ?? false)
                || (security.financialActionsLocked ?? false),
            // Mode absent ⇒ consultation seule.
            safeModeActive: safeMode != "NORMAL",
            serviceSuspended: killSwitch(from: snapshot).entireFinancialLayerSuspended,
            // Approuvé **et** localisé : l'un sans l'autre, le contrat demande
            // l'écran « pays non ouvert » à la place du Hub (§1.2).
            countryOpen: countryOpen(of: snapshot),
            currency: snapshot.experience.currency ?? snapshot.governance.currency,
            // `FINANCE_READ` **et** consultation non coupée par l'experience
            // (`consultationAllowed: false` — mode lecture impossible).
            financeReadAllowed: security.allows(SecurityRight.financeRead)
                && snapshot.experience.consultationAllowed != false,
            paymentPrepareAllowed: security.allows(SecurityRight.paymentPrepare),
            paymentConfirmAllowed: security.allows(SecurityRight.paymentConfirm)
        )
    }

    /// Fin de validité : la reprise de session (~15 min) ou, à défaut, cinq minutes.
    static func expiry(of snapshot: FinanceSessionSnapshot) -> Date {
        let fallback = snapshot.fetchedAt.addingTimeInterval(snapshotLifetime)
        guard let lease = FinanceCoreDates.parse(snapshot.resume?.expiresAt) else { return fallback }
        return min(lease, fallback)
    }

    // MARK: - Capacités du Bloc 3 — FinanceCapabilityProviding

    static func financeCapabilities(from snapshot: FinanceSessionSnapshot,
                                    context: FinanceCapabilityContext) -> FinanceCapabilities {
        let status = status(from: snapshot)
        let gates = capabilities(from: snapshot)
        func open(_ id: String) -> Bool {
            status.canWrite && gates.contains { $0.capabilityID == id && $0.isAvailable() }
        }
        // Les cartes déjà reçues restent lisibles hors pays ouvert : seul
        // `FINANCE_READ` en décide, pas le catalogue du marché.
        let canRead = status.financeReadAllowed

        return FinanceCapabilities(
            sendMoney: open(FinancialCapabilityID.sendMoney),
            requestMoney: open(FinancialCapabilityID.requestMoney),
            qrPayment: open(FinancialCapabilityID.scanQR),
            merchantPayment: open(FinancialCapabilityID.scanQR),
            splitPayment: open(FinancialCapabilityID.splitBill),
            billPayment: open(FinancialCapabilityID.payBill),
            recharge: open(FinancialCapabilityID.topUp),
            fx: open(FinancialCapabilityID.fxConversion),
            remittance: open(FinancialCapabilityID.remittance),
            viewFinancialCards: canRead,
            context: context,
            signature: nil,
            expiresAt: expiry(of: snapshot)
        )
    }

    // MARK: - Hub — ChatFinanceCatalogProviding

    static func conversationType(for kind: ConversationFinancialKind) -> String {
        switch kind {
        case .group:                 return "GROUP"
        case .support, .institution: return "SUPPORT"
        case .direct, .merchant:     return "DIRECT"
        // §5.1.1 — `PAY_BILL`, `TOP_UP`, `CASH_IN`, `CASH_OUT`, groupe `WALLET`.
        case .selfChat:              return "SELF"
        }
    }

    /// Écran natif d'une action du Hub. `nil` : action sans écran dans cette
    /// version (Copilot, reçu, litige, paiement délégué) — non proposée en tuile.
    static func entryKind(forActionCode code: String) -> FinanceEntryKind? {
        switch code {
        case "SEND_MONEY":                          return .sendMoney
        // `GROUP_COLLECTION` n'a pas d'API dédiée : c'est Request Money en groupe — §2.1.
        case "REQUEST_MONEY", "GROUP_COLLECTION":   return .requestMoney
        case "PAY_BILL":                            return .payBill
        case "SCAN_QR":                             return .qrPay
        case "SPLIT_BILL":                          return .splitBill
        case "TOP_UP":                              return .topUp
        case "CASH_IN":                             return .cashIn
        case "CASH_OUT":                            return .cashOut
        case "REMITTANCE":                          return .remittance
        case "FX":                                  return .fxConversion
        case "CREDIT":                              return .credit
        case "SAVINGS":                             return .savings
        case "INVESTMENT":                          return .investment
        default:                                    return nil
        }
    }

    /// `visible=false` n'apparaît pas ; `visible` sans `enabled` apparaît grisé
    /// avec sa raison — §2.1. Une nature n'apparaît qu'une fois.
    static func catalogEntries(from actions: [ResolvedActionDTO]) -> [FinanceCatalogEntry] {
        var seen = Set<FinanceEntryKind>()
        return actions.compactMap { action in
            guard action.visible == true,
                  let kind = entryKind(forActionCode: action.code),
                  seen.insert(kind).inserted else { return nil }
            let enabled = action.enabled == true
            return FinanceCatalogEntry(
                id: action.code.lowercased(),
                kind: kind,
                titleKey: FinanceTranslationKeys.entryKey(for: kind),
                iconName: icon(for: kind),
                isEnabled: enabled,
                unavailableReasonKey: enabled ? nil : reasonKey(forHubReason: action.reason),
                requiresStepUp: action.requiresStepUp == true
            )
        }
    }

    /// Motif traduit d'une action grisée.
    ///
    /// La raison du Hub est un texte technique (`SAFE_MODE`, `REVALIDATE_SESSION`,
    /// `Kill-switch`, `Capability PROHIBITED in BI`) : jamais affichée telle
    /// quelle, mais pas jetée non plus — « session à revalider » et « interdit
    /// dans ce pays » n'appellent pas le même geste. Inconnue ⇒ motif générique.
    static func reasonKey(forHubReason reason: String?) -> String {
        let raw = (reason ?? "").uppercased()
        if raw.contains("REVALIDATE_SESSION") { return "finance.session.session_locked_detail" }
        if raw.contains("SAFE_MODE")          { return "finance.session.safe_mode_detail" }
        if raw.contains("KILL")               { return "finance.killswitch.suspended" }
        if raw.contains("PROHIBITED") || raw.contains("DISABLED") {
            return CapabilityClosure.notEnabled.messageKey
        }
        return FinanceTranslationKeys.ENTRY_UNAVAILABLE
    }

    static func icon(for kind: FinanceEntryKind) -> String {
        switch kind {
        case .sendMoney:    return "arrow.up.circle"
        case .requestMoney: return "arrow.down.circle"
        case .qrPay:        return "qrcode.viewfinder"
        case .qrPresent:    return "qrcode"
        case .payBill:      return "doc.text"
        case .topUp:        return "antenna.radiowaves.left.and.right"
        case .cashIn:       return "tray.and.arrow.down"
        case .cashOut:      return "tray.and.arrow.up"
        case .splitBill:    return "person.2"
        case .remittance:   return "paperplane"
        case .fxConversion: return "arrow.left.arrow.right"
        // Crédit et épargne portaient le **même** billet de banque : deux
        // services distincts que rien ne distinguait dans la grille. Emprunter
        // se lit comme une main qui reçoit, épargner comme une tirelire.
        case .credit:       return "hand.raised.fingers.spread"
        case .savings:      return "building.columns"
        case .investment:   return "chart.line.uptrend.xyaxis"
        case .cards:        return "creditcard"
        case .merchant:     return "storefront"
        case .orders:       return "bag"
        case .invoice:      return "doc.plaintext"
        case .paymentLinks: return "link"
        case .campaign:     return "megaphone"
        case .reconciliation: return "arrow.triangle.2.circlepath"
        case .pfm:          return "chart.pie"
        default:            return "creditcard"
        }
    }
}

/// Dates ISO-8601 du contrat, avec ou sans fraction de seconde.
extension FinanceGovernanceMapper {

    /// Pays **approuvé et localisé** : l'un sans l'autre, le contrat demande
    /// l'écran « pays non ouvert » à la place du Hub (§1.2).
    ///
    /// Journalisé quand c'est non : sans le détail, l'écran ne disait pas
    /// laquelle des deux conditions manquait.
    static func countryOpen(of snapshot: FinanceSessionSnapshot) -> Bool {
        let approved = snapshot.experience.countryApproved ?? snapshot.governance.countryApproved ?? false
        let localized = snapshot.experience.countryLocalized ?? false
        #if DEBUG
        if !(approved && localized) {
            print("[FinanceSession] country closed — approved=\(approved) localized=\(localized) "
                  + "country=\(snapshot.experience.country ?? "nil")")
        }
        #endif
        return approved && localized
    }
}

enum FinanceCoreDates {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
