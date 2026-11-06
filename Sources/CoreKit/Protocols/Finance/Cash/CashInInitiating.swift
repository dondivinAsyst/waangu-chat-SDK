//
//  CashInInitiating.swift
//  CoreKit
//
//  Dépôt d'argent — Bloc 3, chapitre 19.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /v1/cash-ins`, `GET /v1/cash-ins/{id}`,
//  `/requery`, `/dispute`.
//

import Foundation

/// Ouvre un dépôt et suit son instruction.
///
/// **L'idempotence côté client ne protège rien ici.** Un cash-in s'exécute hors
/// application — chez un agent, à un guichet, depuis une autre banque. Le geste
/// dupliqué est *physique* : deux dépôts réels de 10 000 sont deux dépôts, pas
/// un rejeu. Seul le backend, via la référence, peut décider si un second
/// versement est une erreur ou une intention.
public protocol CashInInitiating: Sendable {

    /// Canaux ouverts pour cet utilisateur, rendus par le backend.
    func availableChannels() async -> Result<[CashInChannel], FinanceError>

    /// Demande une instruction de dépôt.
    func createInstruction(
        _ request: CashInRequest,
        idempotency: IdempotencyContext
    ) async -> Result<CashInInstruction, FinanceError>

    /// Relit l'état d'un dépôt en attente.
    ///
    /// Le seul moyen de savoir si l'argent est arrivé : le client ne le voit pas
    /// se produire, et une preuve utilisateur n'est jamais une preuve financière.
    func requery(_ reference: FinancialReference) async -> Result<CashInInstruction, FinanceError>

    /// `POST /cash-in/prepare` (§6) — **un devis**, pas un dépôt.
    ///
    /// Le contrat ne crée pas un dépôt d'un appel : il prépare, l'utilisateur
    /// confirme, puis exécute. ``createInstruction`` promettait l'instruction
    /// immédiatement, c'est-à-dire un dépôt lancé sans que personne ait rien
    /// confirmé.
    func quote(_ request: CashInRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError>

    /// `true` si cette implémentation demande un devis au serveur.
    ///
    /// Distingue « je ne sais pas faire de devis » d'un refus serveur, que
    /// `capabilityUnavailable` disait tous les deux.
    var providesQuotes: Bool { get }

    /// `POST /cash-in/verify-agent` (§6) — l'agent est-il bien celui qu'il dit ?
    ///
    /// `CF_037` si le serveur ne le reconnaît pas. Vérifier n'est pas déposer.
    func verifyAgent(_ reference: FinancialReference, conversationID: String?,
                     agentID: String) async -> Result<CashInAgentOverlay, FinanceError>

    /// `POST /cash-in/confirm-physical` (§6) — l'agent a reçu les espèces.
    ///
    /// **Ce n'est pas un crédit.** Le contrat le dit deux fois : « physique
    /// confirmé ≠ argent au ledger », et `creditState` peut rester `PENDING`
    /// après coup. Fusionner les deux, c'est `CF_038`.
    func confirmPhysical(_ reference: FinancialReference,
                         conversationID: String?) async -> Result<CashInAgentOverlay, FinanceError>
}

public extension CashInInitiating {
    func verifyAgent(_ reference: FinancialReference, conversationID: String?,
                     agentID: String) async -> Result<CashInAgentOverlay, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func confirmPhysical(_ reference: FinancialReference,
                         conversationID: String?) async -> Result<CashInAgentOverlay, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func quote(_ request: CashInRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    var providesQuotes: Bool { false }
}

// MARK: - Canaux

public enum CashInChannel: String, Codable, Sendable, CaseIterable {
    case agent, bank, card, mobileMoney, openBanking

    /// Un canal inconnu fait échouer le décodage : proposer un canal qu'on ne
    /// sait pas instruire enverrait l'utilisateur déposer de l'argent sans
    /// pouvoir lui dire comment.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = CashInChannel(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Canal de dépôt inconnu : \(raw)")
            )
        }
        self = value
    }
}

// MARK: - Demande

public struct CashInRequest: Sendable, Hashable, Codable {
    public let channel: CashInChannel
    public let amount: Decimal?
    public let currency: String
    public let conversationID: String?

    /// L'agent chez qui le dépôt se fait, quand le canal en désigne un.
    ///
    /// Publié par `MoneyOpBody` (§6) : c'est lui que `verify-agent` vérifiera
    /// ensuite. `nil` pour les canaux sans agent — une banque, une carte.
    public let agentID: String?

    public init(channel: CashInChannel, amount: Decimal?, currency: String,
                conversationID: String? = nil, agentID: String? = nil) {
        self.channel = channel
        self.amount = amount
        self.currency = currency
        self.conversationID = conversationID
        self.agentID = agentID
    }
}

// MARK: - Instruction

/// Ce que l'utilisateur doit faire, et jusqu'à quand.
public struct CashInInstruction: Sendable, Hashable, Codable {

    public let reference: FinancialReference
    public let channel: CashInChannel
    public let status: PaymentStatus

    /// Référence à présenter à l'agent ou à la banque.
    ///
    /// Opaque et **non secrète** : elle identifie un dépôt attendu, elle
    /// n'autorise aucun retrait. C'est ce qui la distingue d'un code de
    /// cash-out, et pourquoi elle peut s'afficher et se partager.
    public let depositReference: String

    /// Étapes rendues par le backend, sous forme de clés de localisation.
    ///
    /// Jamais composées côté client : les instructions varient par canal, par
    /// partenaire et par pays, et les écrire ici les figerait dans une version
    /// d'application.
    public let instructionKeys: [String]

    public let expiresAt: Date?
    public let amount: Decimal?
    public let currency: String

    public init(
        reference: FinancialReference,
        channel: CashInChannel,
        status: PaymentStatus,
        depositReference: String,
        instructionKeys: [String],
        expiresAt: Date? = nil,
        amount: Decimal? = nil,
        currency: String
    ) {
        self.reference = reference
        self.channel = channel
        self.status = status
        self.depositReference = depositReference
        self.instructionKeys = instructionKeys
        self.expiresAt = expiresAt
        self.amount = amount
        self.currency = currency
    }
}

public extension CashInInstruction {

    func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// `true` si l'instruction peut encore être suivie.
    ///
    /// Une instruction périmée doit être **remplacée**, jamais réutilisée :
    /// déposer sous une référence expirée met l'argent dans un dépôt que
    /// personne n'attend plus.
    func isActionable(asOf now: Date = Date()) -> Bool {
        !isExpired(asOf: now) && !status.isTerminal
    }

    /// `true` si une seconde instruction risquerait un double versement.
    ///
    /// Tant qu'un dépôt reste en attente, en proposer un second sans que le
    /// backend l'ait dit invite à verser deux fois.
    var wouldRiskDoubleDeposit: Bool { status.isInFlight }
}

// MARK: - Dépôt chez un agent

/// Où en est un dépôt en espèces chez un agent — `CashInOverlay` (§6).
///
/// Trois faits **distincts**, et c'est tout l'intérêt du type : l'agent est
/// vérifié, l'agent a reçu les espèces, et l'argent est au compte. Les deux
/// premiers sont des gestes de terrain ; seul le troisième est financier.
///
/// Le contrat en fait une erreur nommée : « **Physique confirmé ≠ argent au
/// ledger. CF_038 si l'UI fusionne les deux.** » Un écran qui annonce « dépôt
/// reçu » quand l'agent a pris les billets affirme un crédit que personne n'a
/// constaté.
public struct CashInAgentOverlay: Sendable, Hashable, Codable {

    public let reference: FinancialReference
    public let conversationID: String?
    public let channel: CashInChannel?
    public let agentID: String?

    /// L'agent est reconnu par le serveur.
    public let agentVerified: Bool

    /// Quand l'agent a déclaré avoir reçu les espèces. **Pas un crédit.**
    public let physicalReceivedAt: Date?

    /// Référence Finance, quand le rail en a produit une.
    public let financeReference: String?

    /// État du crédit, **tel que le serveur l'écrit** — `PENDING`, et ce que ce
    /// client ne connaît pas encore. Gardé brut : seul le serveur le nomme.
    public let creditState: String

    public init(reference: FinancialReference, conversationID: String? = nil,
                channel: CashInChannel? = nil, agentID: String? = nil,
                agentVerified: Bool = false, physicalReceivedAt: Date? = nil,
                financeReference: String? = nil, creditState: String = "") {
        self.reference = reference
        self.conversationID = conversationID
        self.channel = channel
        self.agentID = agentID
        self.agentVerified = agentVerified
        self.physicalReceivedAt = physicalReceivedAt
        self.financeReference = financeReference
        self.creditState = creditState.uppercased()
    }

    /// Les seuls états qui affirment un crédit.
    ///
    /// Liste **fermée** : un état que ce client ne connaît pas n'est pas un
    /// crédit. C'est le sens de `CF_038` — dans le doute, l'argent n'est pas
    /// arrivé, et l'écran le dit ainsi.
    public static let creditedStates: Set<String> = ["CREDITED", "COMPLETED", "SETTLED"]

    /// L'argent est au compte. **Jamais déduit de `physicalReceivedAt`.**
    public var isCredited: Bool { Self.creditedStates.contains(creditState) }

    /// L'agent a les espèces, le compte ne les a pas encore : l'état que
    /// l'écran doit montrer, et qui n'est ni un succès ni un échec.
    public var awaitsCredit: Bool { physicalReceivedAt != nil && !isCredited }
}
