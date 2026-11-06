//
//  NFCSessionContract.swift
//  CoreKit
//
//  Paiement de proximité — Bloc 6, chapitre 47.
//
//  **BACKEND CONTRACT REQUIRED** — ouverture de session, attestation
//  d'appareil, confirmation, requête d'état.
//

import Foundation

/// Paiement sans contact en face d'un terminal.
///
/// Sept choses doivent être **impossibles**, et le chapitre 47 les nomme :
/// rejeu, double paiement, changement de marchand, changement de montant,
/// changement de terminal, paiement hors session, paiement après expiration.
///
/// Toutes se ramènent à un même principe : **le paiement est lié à une session,
/// et la session épingle tout**. Le terminal, le montant, le marchand et
/// l'appareil sont figés à l'ouverture ; rien de ce qui est présenté ensuite ne
/// peut s'en écarter sans que la session soit invalide.
public protocol ProximityPaymentSessioning: Sendable {

    /// L'appareil peut-il payer sans contact ici et maintenant ?
    ///
    /// Séparé de l'ouverture : afficher un bouton « payer sans contact » puis
    /// échouer au moment de l'approche est la pire manière de l'apprendre,
    /// devant un commerçant qui attend.
    func capability() async -> Result<ProximityCapability, FinanceError>

    /// Ouvre une session pour un terminal donné.
    ///
    /// L'attestation d'appareil part **avec** la demande : une session ouverte
    /// puis attestée laisserait une fenêtre pendant laquelle un appareil non
    /// vérifié détient une session valide.
    func open(
        terminal: TerminalIdentitySnapshot,
        attestation: DeviceAttestationResult,
        idempotency: IdempotencyContext
    ) async -> Result<ProximityPaymentSession, FinanceError>

    /// Confirme le paiement dans la session.
    ///
    /// `session` est passée entière, pas seulement son identifiant : le backend
    /// revérifie que le montant et le terminal présentés sont bien ceux qu'il a
    /// épinglés.
    func confirm(
        session: ProximityPaymentSession,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<ProximityPaymentOutcome, FinanceError>

    /// Redemande l'état d'un paiement dont l'issue est incertaine.
    ///
    /// **Ne relance jamais un paiement** (§19). Un état inconnu se clarifie, il
    /// ne se rejoue pas — sans quoi une réponse perdue devient un double débit.
    func requery(sessionID: String) async -> Result<ProximityPaymentOutcome, FinanceError>

    /// Abandonne la session. La libérer explicitement vaut mieux que la laisser
    /// expirer : le terminal reste bloqué en face pendant ce temps.
    func cancel(sessionID: String, idempotency: IdempotencyContext) async -> Result<Void, FinanceError>
}

// MARK: - Capacité

public struct ProximityCapability: Codable, Sendable, Hashable {

    public let isAvailable: Bool

    /// Pourquoi c'est indisponible, quand ça l'est. Chaque motif appelle un
    /// geste différent : activer le NFC n'est pas la même réponse qu'un pays
    /// non ouvert.
    public let unavailableReason: ProximityUnavailableReason?

    /// Montant maximal sans authentification renforcée, **fixé par le backend**.
    /// `nil` ⇒ toute opération demande un step-up.
    public let contactlessCeiling: Money?

    public init(isAvailable: Bool, unavailableReason: ProximityUnavailableReason? = nil,
                contactlessCeiling: Money? = nil) {
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
        self.contactlessCeiling = contactlessCeiling
    }
}

public enum ProximityUnavailableReason: String, Codable, Sendable, CaseIterable {
    case hardwareMissing    = "HARDWARE_MISSING"
    case nfcDisabled        = "NFC_DISABLED"
    case countryNotOpen     = "COUNTRY_NOT_OPEN"
    case deviceNotAttested  = "DEVICE_NOT_ATTESTED"
    case accountRestricted  = "ACCOUNT_RESTRICTED"
    case unknown            = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProximityUnavailableReason(rawValue: raw) ?? .unknown
    }
}

// MARK: - Attestation d'appareil

/// Ce que l'appareil peut prouver de lui-même.
///
/// **Le client ne juge pas.** Il rapporte des signaux ; c'est le backend qui
/// décide si l'appareil peut payer. Un appareil compromis mentirait de toute
/// façon sur son propre verdict — d'où des signaux bruts plutôt qu'un booléen
/// « je suis sûr ».
public struct DeviceAttestationResult: Codable, Sendable, Hashable {

    /// Jeton d'attestation matérielle, opaque.
    public let attestationToken: String

    /// Liaison de l'appareil au compte, établie à l'enrôlement.
    public let deviceBindingID: String

    /// Signal d'intégrité — jailbreak, root, débogueur attaché.
    ///
    /// Rapporté, jamais interprété localement : un appareil compromis peut
    /// falsifier ce signal, mais le rapporter reste utile pour la corrélation.
    public let integritySignals: [String]

    public let capturedAt: Date

    public init(attestationToken: String, deviceBindingID: String,
                integritySignals: [String] = [], capturedAt: Date) {
        self.attestationToken = attestationToken
        self.deviceBindingID = deviceBindingID
        self.integritySignals = integritySignals
        self.capturedAt = capturedAt
    }

    /// Une attestation vieillie ne vaut plus rien : l'appareil a pu changer
    /// d'état entre-temps.
    public func isFresh(at now: Date = Date(), maxAge: TimeInterval = 60) -> Bool {
        now.timeIntervalSince(capturedAt) <= maxAge
    }
}

// MARK: - Terminal

/// Le terminal tel qu'il s'est présenté.
///
/// Épinglé dans la session. Si le terminal qui répond ensuite n'est pas
/// celui-là, la session est invalide — c'est ce qui interdit le « changement de
/// terminal » du chapitre 47.
public struct TerminalIdentitySnapshot: Codable, Sendable, Hashable {

    public let terminalID: String
    public let merchantID: String

    /// Nom affiché au porteur. Sert à la confirmation visuelle : payer un nom
    /// qu'on ne reconnaît pas doit pouvoir s'interrompre.
    public let merchantDisplayName: String

    /// Montant réclamé par le terminal.
    public let amount: Money

    /// Empreinte de ce que le terminal a présenté, **calculée par le backend**.
    ///
    /// Rejouer une trame capturée produit la même empreinte sur une session
    /// différente : c'est le rapprochement des deux qui trahit le rejeu.
    public let presentedHash: String

    public let capturedAt: Date

    public init(terminalID: String, merchantID: String, merchantDisplayName: String,
                amount: Money, presentedHash: String, capturedAt: Date) {
        self.terminalID = terminalID
        self.merchantID = merchantID
        self.merchantDisplayName = merchantDisplayName
        self.amount = amount
        self.presentedHash = presentedHash
        self.capturedAt = capturedAt
    }

    /// Le terminal présenté est-il celui qu'on a épinglé ?
    ///
    /// Les quatre champs comptent. Le montant en fait partie : un terminal qui
    /// change son montant après l'ouverture est le scénario « changement de
    /// montant » que le chapitre interdit.
    public func matches(_ other: TerminalIdentitySnapshot) -> Bool {
        terminalID == other.terminalID
            && merchantID == other.merchantID
            && amount == other.amount
            && presentedHash == other.presentedHash
    }
}

// MARK: - La session

public struct ProximityPaymentSession: Codable, Sendable, Hashable, Identifiable {

    public let id: String

    /// Ce qui est épinglé. Immuable pour la durée de la session.
    public let terminal: TerminalIdentitySnapshot

    /// Valeur à usage unique, liée à cette session.
    public let nonce: String

    public let openedAt: Date

    /// **Courte par conception.** Une session de proximité vit le temps d'un
    /// geste ; la prolonger rallonge la fenêtre d'attaque sans servir personne.
    public let expiresAt: Date

    public let state: ProximitySessionState

    /// Risque de relais, évalué par le backend.
    public let relayRisk: RelayRiskResult

    /// Une authentification renforcée est-elle exigée pour ce montant ?
    public let requiresStepUp: Bool

    public init(id: String, terminal: TerminalIdentitySnapshot, nonce: String,
                openedAt: Date, expiresAt: Date, state: ProximitySessionState,
                relayRisk: RelayRiskResult, requiresStepUp: Bool) {
        self.id = id
        self.terminal = terminal
        self.nonce = nonce
        self.openedAt = openedAt
        self.expiresAt = expiresAt
        self.state = state
        self.relayRisk = relayRisk
        self.requiresStepUp = requiresStepUp
    }

    public func hasExpired(at now: Date = Date()) -> Bool { now >= expiresAt }

    /// Confirmable **maintenant**.
    ///
    /// Trois conditions. L'expiration est revérifiée côté client en plus du
    /// verdict serveur : entre l'ouverture et le geste de confirmation, il peut
    /// s'écouler plus que la durée de vie de la session.
    public func isConfirmable(at now: Date = Date()) -> Bool {
        state == .open && !hasExpired(at: now) && relayRisk.permitsPayment
    }

    /// Le terminal qui répond est-il celui qu'on a épinglé ?
    ///
    /// À appeler **avant** de confirmer. Un écart ici est un incident, pas une
    /// erreur d'usage : quelqu'un a substitué le terminal ou le montant.
    public func validate(presented: TerminalIdentitySnapshot) -> ProximityMismatch? {
        if terminal.terminalID != presented.terminalID { return .terminalChanged }
        if terminal.merchantID != presented.merchantID { return .merchantChanged }
        if terminal.amount != presented.amount { return .amountChanged }
        if terminal.presentedHash != presented.presentedHash { return .payloadChanged }
        return nil
    }
}

/// Ce qui a changé entre l'épinglage et la présentation.
///
/// Nommé plutôt que réduit à un booléen : « le montant a changé » et « le
/// marchand a changé » n'ont pas la même gravité pour l'analyse de fraude.
public enum ProximityMismatch: String, Sendable, Equatable {
    case terminalChanged
    case merchantChanged
    case amountChanged
    case payloadChanged
}

public enum ProximitySessionState: String, Codable, Sendable, CaseIterable {
    case open      = "OPEN"
    case confirming = "CONFIRMING"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case expired   = "EXPIRED"
    case rejected  = "REJECTED"
    case unknown   = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProximitySessionState(rawValue: raw) ?? .unknown
    }
}

// MARK: - Relais

/// Évaluation du risque de relais.
///
/// Une attaque par relais transporte l'échange sans contact sur une distance
/// arbitraire : la carte est chez vous, le terminal est ailleurs. La détection
/// repose sur des mesures que seul le backend corrèle — temps de réponse,
/// géolocalisation du terminal, historique.
public struct RelayRiskResult: Codable, Sendable, Hashable {

    public let level: RelayRiskLevel
    public let signalKeys: [String]

    public init(level: RelayRiskLevel, signalKeys: [String] = []) {
        self.level = level
        self.signalKeys = signalKeys
    }

    /// Seul un risque faible laisse passer sans friction.
    public var permitsPayment: Bool { level != .blocked }

    /// Un risque élevé exige une authentification, même sous le plafond sans
    /// contact : c'est le seul moyen de distinguer le porteur d'un relais.
    public var forcesStepUp: Bool { level == .elevated }
}

public enum RelayRiskLevel: String, Codable, Sendable, CaseIterable {
    case low      = "LOW"
    case elevated = "ELEVATED"
    case blocked  = "BLOCKED"

    /// Un niveau inconnu est traité comme **élevé**, pas comme faible.
    ///
    /// Le sens de la dégradation compte : traiter un signal incompris comme
    /// bénin annulerait la protection le jour où le backend en ajoute un.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RelayRiskLevel(rawValue: raw) ?? .elevated
    }
}

// MARK: - Issue

public struct ProximityPaymentOutcome: Codable, Sendable, Hashable {

    public let sessionID: String
    public let truth: ProximityPaymentTruth

    /// Référence financière, dès que le backend en a une.
    public let reference: FinancialReference?

    /// Référence de rapprochement, pour retrouver l'opération côté PGW.
    public let reconciliationReference: String?

    public let updatedAt: Date

    public init(sessionID: String, truth: ProximityPaymentTruth,
                reference: FinancialReference? = nil,
                reconciliationReference: String? = nil, updatedAt: Date) {
        self.sessionID = sessionID
        self.truth = truth
        self.reference = reference
        self.reconciliationReference = reconciliationReference
        self.updatedAt = updatedAt
    }
}

/// L'issue d'un paiement de proximité (§19).
///
/// `unknown` et `pending` sont **distincts de `failed`**. Les confondre est
/// exactement ce qui produit un double débit : l'utilisateur voit « échec »,
/// réessaie, et paie deux fois une opération qui avait abouti.
public enum ProximityPaymentTruth: String, Codable, Sendable, CaseIterable {
    case confirmed  = "CONFIRMED"
    case processing = "PROCESSING"
    case pending    = "PENDING"
    case failed     = "FAILED"
    case reversed   = "REVERSED"
    case unknown    = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProximityPaymentTruth(rawValue: raw) ?? .unknown
    }

    /// Peut être présenté comme abouti.
    public var isSettled: Bool { self == .confirmed }

    /// **Ne jamais rejouer sur ces états.** Il faut requêter.
    public var requiresRequery: Bool {
        self == .pending || self == .processing || self == .unknown
    }

    /// Une nouvelle tentative est légitime : rien n'a abouti, rien n'est en vol.
    public var permitsRetry: Bool { self == .failed }
}

// MARK: - Défaut fermé

/// N'ouvre aucune session de proximité.
public struct ClosedProximityPaymentSessioning: ProximityPaymentSessioning {

    public init() {}

    public func capability() async -> Result<ProximityCapability, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func open(terminal: TerminalIdentitySnapshot, attestation: DeviceAttestationResult,
                     idempotency: IdempotencyContext) async -> Result<ProximityPaymentSession, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func confirm(session: ProximityPaymentSession, idempotency: IdempotencyContext,
                        stepUp: StepUpAttestation?) async -> Result<ProximityPaymentOutcome, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func requery(sessionID: String) async -> Result<ProximityPaymentOutcome, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func cancel(sessionID: String, idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
