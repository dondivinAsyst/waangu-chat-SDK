//
//  CashOutIssuing.swift
//  CoreKit
//
//  Retrait d'argent — Bloc 3, chapitre 20.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /v1/cash-outs`, `GET`, `/requery`,
//  `/cancel`.
//

import Foundation

/// Émet et révoque les autorisations de retrait.
///
/// **Un code de retrait est un porteur de valeur.** Contrairement à un
/// identifiant d'opération, quiconque le détient peut retirer l'argent. Toutes
/// les contraintes de ce fichier découlent de ce seul fait : jamais persisté,
/// jamais journalisé, jamais notifié, et révocable à tout instant.
public protocol CashOutIssuing: Sendable {

    func availableChannels() async -> Result<[CashOutChannel], FinanceError>

    /// Émet une autorisation de retrait.
    ///
    /// - Parameter stepUp: obligatoire côté backend pour ce geste. Le client ne
    ///   décide pas du niveau : il satisfait celui qu'on lui impose.
    func issue(
        _ request: CashOutRequest,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<CashOutAuthorization, FinanceError>

    /// Révoque immédiatement — code compromis, retrait abandonné.
    ///
    /// Séparé de `cancel` : révoquer est un geste d'urgence qui doit rester
    /// accessible même quand l'opération est déjà en cours côté rail.
    func revoke(_ reference: FinancialReference,
                idempotency: IdempotencyContext) async -> Result<Void, FinanceError>

    func requery(_ reference: FinancialReference) async -> Result<CashOutAuthorization, FinanceError>

    /// `POST /cash-out/prepare` (§6) — **un devis**, pas un retrait.
    func quote(_ request: CashOutRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError>

    /// `true` si cette implémentation demande un devis au serveur.
    var providesQuotes: Bool { get }

    /// `POST /cash-out/token` (§6) — le jeton de retrait, **émis par Finance**.
    ///
    /// « Chat n'invente plus de jeton local » : le code vient du rail, et
    /// `CF_051` si Finance n'est pas câblé. Rendu en clair **une seule fois**,
    /// haché au repos côté serveur.
    func issueToken(_ reference: FinancialReference, conversationID: String?,
                    agentID: String) async -> Result<CashOutToken, FinanceError>

    /// `POST /cash-out/token/consume` (§6) — l'agent a présenté le code.
    ///
    /// **Consommer n'est pas une finalité financière** (`financialFinality=false`) :
    /// le code est utilisé, l'argent n'est pas pour autant sorti du compte.
    func consumeToken(_ reference: FinancialReference, conversationID: String?,
                      token: String, agentID: String) async -> Result<CashOutTokenOverlay, FinanceError>

    /// `POST /cash-out/token/revoke` (§6) — code compromis ou retrait abandonné.
    func revokeToken(_ reference: FinancialReference,
                     conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError>

    /// `POST /cash-out/confirm-remittance` (§6) — les espèces ont été remises.
    ///
    /// **N'écrit pas le ledger.** C'est un constat de terrain, comme la
    /// confirmation physique d'un dépôt.
    func confirmRemittance(_ reference: FinancialReference,
                           conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError>

    /// `POST /cash-out/incident` (§6) — écart constaté. **N'écrit pas le ledger.**
    func reportIncident(_ reference: FinancialReference,
                        conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError>
}

public extension CashOutIssuing {
    func quote(_ request: CashOutRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    var providesQuotes: Bool { false }

    func issueToken(_ reference: FinancialReference, conversationID: String?,
                    agentID: String) async -> Result<CashOutToken, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func consumeToken(_ reference: FinancialReference, conversationID: String?,
                      token: String, agentID: String) async -> Result<CashOutTokenOverlay, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func revokeToken(_ reference: FinancialReference,
                     conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func confirmRemittance(_ reference: FinancialReference,
                           conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func reportIncident(_ reference: FinancialReference,
                        conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

// MARK: - Le jeton de retrait

/// Le code de retrait, tel que Finance vient de l'émettre.
///
/// **Délibérément non `Codable`**, comme ``CashOutAuthorization`` : l'encoder
/// inviterait à l'écrire quelque part, et un code de retrait sur disque est un
/// billet dans un tiroir ouvert. Le serveur le rend **en clair une seule fois**
/// et le hache au repos ; il vit ici le temps de l'afficher.
public struct CashOutToken: Sendable, Equatable {

    /// À montrer, jamais à journaliser, persister ni notifier.
    public let code: String
    public let expiresAt: Date?
    /// Le mot du serveur — « Shown once — hashed at rest. Token consume ≠
    /// financial finality. » Affiché tel quel plutôt que reformulé.
    public let message: String?

    public init(code: String, expiresAt: Date? = nil, message: String? = nil) {
        self.code = code
        self.expiresAt = expiresAt
        self.message = message
    }
}

/// Où en est un retrait chez un agent — `CashOutOverlay` (§6).
///
/// Quatre faits distincts, et aucun n'est une finalité financière : le code est
/// consommé, les espèces sont remises, un incident est ouvert, le code est
/// révoqué. Le ledger, lui, est écrit par Finance et se lit sur la carte —
/// `confirm-remittance` et `incident` **n'y écrivent pas**.
public struct CashOutTokenOverlay: Sendable, Hashable, Codable {

    public let reference: FinancialReference
    public let conversationID: String?
    public let channel: CashOutChannel?
    public let agentID: String?

    /// Empreinte du code côté serveur. Jamais le code lui-même.
    public let tokenHash: String?
    public let tokenExpiresAt: Date?
    public let revoked: Bool
    /// Le code a été présenté. **≠ argent sorti du compte.**
    public let consumedAt: Date?
    /// Les espèces ont été remises. **N'écrit pas le ledger.**
    public let remittedAt: Date?
    public let incidentOpened: Bool

    public init(reference: FinancialReference, conversationID: String? = nil,
                channel: CashOutChannel? = nil, agentID: String? = nil,
                tokenHash: String? = nil, tokenExpiresAt: Date? = nil,
                revoked: Bool = false, consumedAt: Date? = nil,
                remittedAt: Date? = nil, incidentOpened: Bool = false) {
        self.reference = reference
        self.conversationID = conversationID
        self.channel = channel
        self.agentID = agentID
        self.tokenHash = tokenHash
        self.tokenExpiresAt = tokenExpiresAt
        self.revoked = revoked
        self.consumedAt = consumedAt
        self.remittedAt = remittedAt
        self.incidentOpened = incidentOpened
    }

    /// Le code est encore présentable : ni consommé, ni révoqué, ni expiré.
    public func isUsable(at now: Date = Date()) -> Bool {
        guard !revoked, consumedAt == nil else { return false }
        guard let expiry = tokenExpiresAt else { return true }
        return expiry > now
    }

    /// Le code a servi, l'argent n'est pas encore sorti : l'état que l'écran
    /// doit montrer, et qui n'est **pas** un retrait abouti.
    public var awaitsSettlement: Bool { consumedAt != nil && remittedAt == nil }
}

public enum CashOutChannel: String, Codable, Sendable, CaseIterable {
    case agent, atm, bank, merchant
}

public struct CashOutRequest: Sendable, Hashable, Codable {
    public let channel: CashOutChannel
    public let amount: Decimal
    public let currency: String
    public let conversationID: String?

    public init(channel: CashOutChannel, amount: Decimal, currency: String,
                conversationID: String? = nil) {
        self.channel = channel
        self.amount = amount
        self.currency = currency
        self.conversationID = conversationID
    }
}

// MARK: - Autorisation

/// Une autorisation de retrait active.
///
/// Le type ne conforme **délibérément pas** à `Codable` : le rendre encodable
/// inviterait à le persister, et un code de retrait sur disque est un billet de
/// banque dans un tiroir non fermé. Il vit en mémoire, le temps de l'afficher.
public struct CashOutAuthorization: Sendable, Equatable {

    public let reference: FinancialReference
    public let channel: CashOutChannel
    public let status: PaymentStatus

    /// Le code à présenter. **Ne jamais journaliser, persister ni notifier.**
    public let code: String

    public let amount: Decimal
    public let currency: String
    public let expiresAt: Date

    public init(
        reference: FinancialReference,
        channel: CashOutChannel,
        status: PaymentStatus,
        code: String,
        amount: Decimal,
        currency: String,
        expiresAt: Date
    ) {
        self.reference = reference
        self.channel = channel
        self.status = status
        self.code = code
        self.amount = amount
        self.currency = currency
        self.expiresAt = expiresAt
    }
}

extension CashOutAuthorization: CustomStringConvertible {

    /// Description **sans le code**.
    ///
    /// Un `print` ou une interpolation dans un log est la manière la plus banale
    /// de faire fuir un porteur de valeur. Le type refuse de se décrire en
    /// entier plutôt que de compter sur la discipline de chaque site d'appel.
    public var description: String {
        "CashOutAuthorization(\(channel.rawValue), \(status.rawValue), code: <redacted>)"
    }
}

public extension CashOutAuthorization {

    func isExpired(asOf now: Date = Date()) -> Bool { now >= expiresAt }

    /// `true` si le code peut encore être présenté à un agent.
    func isPresentable(asOf now: Date = Date()) -> Bool {
        !isExpired(asOf: now) && !status.isTerminal
    }

    /// Version affichable partiellement masquée, pour les récapitulatifs.
    ///
    /// Le code entier ne s'affiche que sur l'écran de retrait, après
    /// authentification. Partout ailleurs — historique, carte de conversation —
    /// seules les deux dernières positions apparaissent.
    var maskedCode: String {
        guard code.count > 2 else { return String(repeating: "•", count: code.count) }
        return String(repeating: "•", count: code.count - 2) + code.suffix(2)
    }
}
