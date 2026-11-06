//
//  FinanceSessionStatus.swift
//  FeatureChat
//
//  Ce que la session financière permet, tel que Chat Core le décide — §1.
//

import Foundation
import WaanguCoreKit

/// État de la session financière, vu par l'interface.
///
/// Aucun champ n'est calculé par le client : chacun reflète une décision de
/// Chat Core (experience, governance, security, resume). L'interface s'en sert
/// pour dire *pourquoi* une action est grisée — jamais pour ouvrir une action
/// que le Hub a fermée.
public struct FinanceSessionStatus: Equatable, Sendable {

    /// Écritures de paiement permises — interrupteur maître du serveur.
    public let paymentsAllowed: Bool
    /// Verrou d'écriture : reprise de session non faite ou expirée.
    public let writeLocked: Bool
    /// Mode consultation seule (`PAYMENTS_DISABLED`).
    public let safeModeActive: Bool
    /// Coupe-circuit global ou pays.
    public let serviceSuspended: Bool
    /// Pays du JWT ouvert à la finance **et** localisé (`countryApproved` et
    /// `countryLocalized`, §1.2). L'un sans l'autre, le contrat demande l'écran
    /// « pays non ouvert » à la place du Hub.
    public let countryOpen: Bool
    /// Devise imposée par le serveur (`BIF`, `RWF`, `CAD`) — jamais choisie par l'app.
    public let currency: String?

    // Droits de session — `GET /security/capabilities` (§1.5). Un droit que le
    // serveur n'affirme pas est refusé.

    /// `FINANCE_READ` : consulter solde, relevé et cartes.
    public let financeReadAllowed: Bool
    /// `PAYMENT_PREPARE` : préparer une opération (devis, intention).
    public let paymentPrepareAllowed: Bool
    /// `PAYMENT_CONFIRM` : exécuter une opération confirmée.
    public let paymentConfirmAllowed: Bool

    public init(paymentsAllowed: Bool, writeLocked: Bool, safeModeActive: Bool,
                serviceSuspended: Bool, countryOpen: Bool, currency: String?,
                financeReadAllowed: Bool = false,
                paymentPrepareAllowed: Bool = false,
                paymentConfirmAllowed: Bool = false) {
        self.paymentsAllowed = paymentsAllowed
        self.writeLocked = writeLocked
        self.safeModeActive = safeModeActive
        self.serviceSuspended = serviceSuspended
        self.countryOpen = countryOpen
        self.currency = currency
        self.financeReadAllowed = financeReadAllowed
        self.paymentPrepareAllowed = paymentPrepareAllowed
        self.paymentConfirmAllowed = paymentConfirmAllowed
    }

    /// Le compte peut être **lu** : solde, relevé.
    ///
    /// Le mode sûr et le verrou d'écriture n'y changent rien — ils interdisent
    /// de payer, pas de consulter (« vous pouvez consulter vos opérations »).
    /// Un pays fermé, une couche suspendue ou un `FINANCE_READ` refusé, si.
    public var canReadAccount: Bool {
        countryOpen && !serviceSuspended && financeReadAllowed
    }

    /// Une opération peut être **préparée**.
    public var canWrite: Bool {
        paymentsAllowed && !writeLocked && !safeModeActive && !serviceSuspended && countryOpen
            && paymentPrepareAllowed
    }

    /// Une opération préparée peut être **exécutée**.
    public var canConfirm: Bool {
        canWrite && paymentConfirmAllowed
    }
}

// MARK: - Pourquoi une écriture est refusée

/// La raison précise d'un refus décidé **par l'app**, avant tout appel réseau.
///
/// Le refus lui-même reste `FinanceError.capabilityUnavailable` — la logique
/// n'a pas besoin d'en savoir plus. La raison ne sert qu'à l'écran : « session à
/// revalider » et « pays non ouvert » n'appellent pas le même geste, et un
/// « service indisponible » unique laissait l'utilisateur deviner.
public enum FinanceWriteRefusal: Equatable, Sendable {
    /// L'amorçage n'a pas abouti : aucun droit n'a pu être affirmé.
    case sessionUnavailable
    case countryClosed
    case serviceSuspended
    case safeMode
    case sessionLocked
    /// `paymentsAllowed` faux ou `PAYMENT_PREPARE` refusé.
    case paymentsDisabled
    /// `PAYMENT_CONFIRM` refusé : préparer reste possible, exécuter non.
    case confirmationDenied
    /// Droit de session à haut risque refusé — `CASH_OUT` sans moteur de risque.
    case highRiskUnavailable
}

public extension FinanceSessionStatus {

    /// Pourquoi une opération ne peut pas être **préparée**, ou `nil` si elle le peut.
    ///
    /// `nil` exactement quand `canWrite` est vrai. L'ordre est celui où
    /// l'utilisateur peut agir le moins : un pays fermé passe avant un verrou
    /// qu'une reconnexion lèvera.
    var writeRefusal: FinanceWriteRefusal? {
        if !countryOpen { return .countryClosed }
        if serviceSuspended { return .serviceSuspended }
        if safeModeActive { return .safeMode }
        if writeLocked { return .sessionLocked }
        if !paymentsAllowed || !paymentPrepareAllowed { return .paymentsDisabled }
        return nil
    }

    /// Pourquoi une opération préparée ne peut pas être **exécutée**, ou `nil`.
    ///
    /// `nil` exactement quand `canConfirm` est vrai.
    var confirmRefusal: FinanceWriteRefusal? {
        writeRefusal ?? (paymentConfirmAllowed ? nil : .confirmationDenied)
    }
}

/// Fournit l'état de la session financière.
public protocol FinanceSessionProviding: Sendable {
    func status() async -> Result<FinanceSessionStatus, FinanceError>
    /// Force un nouvel amorçage — reconnexion, retour au premier plan, changement de compte.
    func invalidate() async
}
