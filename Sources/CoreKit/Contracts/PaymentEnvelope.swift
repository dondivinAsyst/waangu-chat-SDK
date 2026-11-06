//
//  PaymentEnvelope.swift
//  CoreKit
//
//  Canonical payment envelope with backend signature and rail proof
//  RULE: PaymentEnvelope créé
//

import Foundation

/// Canonical payment envelope
/// All payments must be wrapped in this envelope with backend signature and rail proof
public struct PaymentEnvelope: Codable, Sendable, Identifiable {
    
    public let id: String
    public let paymentType: PaymentType
    public let amount: Decimal
    public let currency: String
    public let timestamp: Date
    public let status: PaymentStatus
    
    // Parties
    public let senderId: String
    public let recipientId: String
    public let merchantId: String?
    
    // Backend authority
    public let backendSignature: String
    public let railProof: RailProof
    public let evidenceRefs: [String]
    public let version: String
    public let truthSource: TruthSource
    
    // Idempotency
    public let idempotencyKey: String
    public let correlationId: String
    public let traceId: String?
    
    // Metadata
    public let description: String?
    public let metadata: [String: String]
    public let feeAmount: Decimal?
    public let feeCurrency: String?
    public let exchangeRate: Decimal?
    public let crossBorder: Bool
    
    public init(
        id: String,
        paymentType: PaymentType,
        amount: Decimal,
        currency: String,
        timestamp: Date,
        status: PaymentStatus,
        senderId: String,
        recipientId: String,
        merchantId: String?,
        backendSignature: String,
        railProof: RailProof,
        evidenceRefs: [String],
        version: String,
        truthSource: TruthSource = .backend,
        idempotencyKey: String,
        correlationId: String,
        traceId: String? = nil,
        description: String?,
        metadata: [String: String],
        feeAmount: Decimal?,
        feeCurrency: String?,
        exchangeRate: Decimal?,
        crossBorder: Bool
    ) {
        self.id = id
        self.paymentType = paymentType
        self.amount = amount
        self.currency = currency
        self.timestamp = timestamp
        self.status = status
        self.senderId = senderId
        self.recipientId = recipientId
        self.merchantId = merchantId
        self.backendSignature = backendSignature
        self.railProof = railProof
        self.evidenceRefs = evidenceRefs
        self.version = version
        self.truthSource = truthSource
        self.idempotencyKey = idempotencyKey
        self.correlationId = correlationId
        self.traceId = traceId
        self.description = description
        self.metadata = metadata
        self.feeAmount = feeAmount
        self.feeCurrency = feeCurrency
        self.exchangeRate = exchangeRate
        self.crossBorder = crossBorder
    }
}

// MARK: - Exigence d'authentification

public extension PaymentEnvelope {

    /// Niveau de step-up exigé par le backend pour cette opération.
    ///
    /// **BACKEND CONTRACT REQUIRED.** Transporté dans `metadata` tant que
    /// l'enveloppe n'a pas de champ dédié. `nil` ⇒ le backend ne s'est pas
    /// prononcé, et l'appelant retient alors le plancher le plus exigeant
    /// atteignable localement — jamais le plus bas.
    var requiredStepUpLevel: StepUpLevel? {
        guard let raw = metadata["required_step_up"], let value = Int(raw) else { return nil }
        return StepUpLevel(rawValue: value)
    }
}

// MARK: - Révision de l'objet

public extension PaymentEnvelope {

    /// Révision de l'objet financier, telle que rendue par le backend.
    ///
    /// `version` est transporté en `String` par l'enveloppe canonique, alors que
    /// la révision qui décide de l'ordre entre deux copies est un entier monotone
    /// (`FinancialObjectDataDTO.version`, contrat backend #2). Cet accesseur est
    /// le seul pont autorisé entre les deux.
    ///
    /// `nil` quand le backend n'a pas rendu de révision exploitable. Un appelant
    /// ne doit alors **jamais** en inventer une : le client n'est pas l'auteur de
    /// ce champ, et une valeur fabriquée fait rejeter la correction backend qui
    /// suivra comme si elle était périmée.
    var objectRevision: Int? { Int(version) }
}

// MARK: - Payment Type

public enum PaymentType: String, Codable, Sendable {
    case p2p = "P2P"
    case merchant = "MERCHANT"
    case qr = "QR"
    case nfc = "NFC"
    case card = "CARD"
    case bankTransfer = "BANK_TRANSFER"
    case mobileWallet = "MOBILE_WALLET"
    case requestToPay = "REQUEST_TO_PAY"
    case splitBill = "SPLIT_BILL"
    case redPacket = "RED_PACKET"
    case subscription = "SUBSCRIPTION"
    case refund = "REFUND"
}

// MARK: - Payment Status

/// Statut canonique d'un objet financier.
///
/// **Enum unique du dépôt.** Toute surface — carte de conversation, historique,
/// notification — consomme celui-ci. Un second enum de statut, même réduit et même
/// local à un écran, réintroduit la traduction lossy que le Bloc 1 supprime.
///
/// Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.1.
public enum PaymentStatus: String, Codable, Sendable, CaseIterable {

    // ── En cours ─────────────────────────────────────────────
    case queued = "QUEUED"
    case syncing = "SYNCING"
    case pending = "PENDING"
    case processing = "PROCESSING"
    case authorized = "AUTHORIZED"

    /// Remis au fournisseur, en attente de sa réponse.
    /// Distinct de `processing` : ici l'autorité n'est plus le backend Waangu.
    case pendingProvider = "PENDING_PROVIDER"

    /// Accepté par le rail, règlement non encore effectué.
    /// L'utilisateur voit un paiement abouti ; la trésorerie, non.
    case pendingSettlement = "PENDING_SETTLEMENT"

    // ── Final ────────────────────────────────────────────────
    case confirmed = "CONFIRMED"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    /// Le devis ou l'intention a dépassé sa validité sans être confirmé.
    /// Impose un parcours complet — jamais une reprise silencieuse.
    case expired = "EXPIRED"

    // ── Facturier (Bloc 4 §7) ────────────────────────────────

    /// En attente d'une décision de conformité **avant** exécution.
    ///
    /// Distinct de `complianceHold`, qui bloque un objet déjà en cours : ici
    /// rien n'a été exécuté, et la conformité peut encore autoriser.
    case compliancePending = "COMPLIANCE_PENDING"

    /// Une autorisation utilisateur supplémentaire est requise — step-up,
    /// approbation d'un tiers, validation hors bande.
    case authorizationRequired = "AUTHORIZATION_REQUIRED"

    /// Débit enregistré, livraison fournisseur non encore rapprochée.
    ///
    /// **Ni abouti, ni échoué.** L'utilisateur a été débité ; le fournisseur
    /// n'a pas confirmé la fourniture. Le présenter comme réussi serait un faux
    /// succès à retardement.
    case pendingReconciliation = "PENDING_RECONCILIATION"

    // ── Cycle de remboursement ───────────────────────────────

    /// L'utilisateur a demandé un remboursement. Rien n'est décidé.
    case refundRequested = "REFUND_REQUESTED"

    /// Le remboursement est accordé, **et pas encore exécuté**.
    ///
    /// Distinct de `refunded` à dessein : l'argent n'est pas revenu. Les
    /// confondre annoncerait un remboursement reçu qui peut encore échouer.
    case refundApproved = "REFUND_APPROVED"

    /// Remboursement en cours d'exécution par le rail.
    case refundProcessing = "REFUND_PROCESSING"

    /// Le backend rapproche cette opération avec le rail.
    ///
    /// Ni abouti, ni échoué : personne ne sait encore. Proche de `unknown`,
    /// mais l'ignorance est ici **côté serveur et assumée**, pas côté client.
    case reconciling = "RECONCILING"

    // ── Après finalité ───────────────────────────────────────
    case refunded = "REFUNDED"

    /// Remboursement partiel : l'objet reste porteur d'un solde.
    case partiallyRefunded = "PARTIALLY_REFUNDED"

    /// Annulé par le rail après finalité, à l'initiative du fournisseur.
    /// Ce n'est pas un remboursement : l'utilisateur ne l'a pas demandé.
    case reversed = "REVERSED"

    case disputed = "DISPUTED"

    // ── Compliance ───────────────────────────────────────────
    case restricted = "RESTRICTED"
    case denied = "DENIED"
    case complianceHold = "COMPLIANCE_HOLD"
    case amlReview = "AML_REVIEW"

    // ── Indéterminé ──────────────────────────────────────────

    /// Le client ne sait pas, et ne peut pas savoir.
    ///
    /// Timeout après soumission, réponse incohérente, statut backend non reconnu.
    /// Obligatoire : sans lui, un timeout doit être traduit en `failed` — qui
    /// invite l'utilisateur à repayer une opération peut-être aboutie — ou en
    /// `pending` — qui masque l'incertitude. Les deux sont des mensonges.
    ///
    /// N'autorise aucune action utilisateur autre qu'actualiser. Seul le backend
    /// le résout, via réconciliation.
    case unknown = "UNKNOWN"

    /// Issue incertaine **déclarée par le serveur** — l'`IN_DOUBT` canonique
    /// (Harness Bloc 2 §28, §62), identique sur Android, iOS et Web.
    ///
    /// Même conduite que `unknown` : interroger le statut, jamais rejouer
    /// l'opération, jamais l'afficher comme un échec. Distinct de `unknown`
    /// parce que ce n'est pas un statut que ce client ignore : c'est le serveur
    /// qui dit ne pas savoir encore.
    case inDoubt = "IN_DOUBT"

    // MARK: Décodage défensif

    /// Un statut backend non reconnu devient `.unknown`, jamais une erreur de
    /// décodage et jamais `.failed`.
    ///
    /// Le backend peut ajouter un statut sans que les clients déjà déployés le
    /// connaissent. Faire échouer le décodage rendrait la carte illisible ; le
    /// traduire en échec afficherait un mensonge. `.unknown` dit la vérité :
    /// l'objet existe, ce client ne sait pas l'interpréter, il faut le demander.
    ///
    /// Déclaré dans le corps de l'enum, et non en extension : la conformance
    /// `Codable` d'un enum à valeur brute vient d'une extension conditionnelle de
    /// la bibliothèque standard, et seul un membre du type lui-même est
    /// certainement retenu comme témoin.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaymentStatus(rawValue: raw) ?? .unknown
    }
}


// MARK: - PaymentStatus — sémantique

public extension PaymentStatus {

    /// L'objet évolue encore ; une mise à jour est attendue sans action utilisateur.
    ///
    /// `unknown` en est volontairement exclu : il n'est pas une étape du cycle de
    /// vie mais un aveu d'ignorance, et il appelle une réconciliation, pas une
    /// attente passive.
    var isInFlight: Bool {
        switch self {
        case .queued, .syncing, .pending, .processing,
             .authorized, .pendingProvider, .pendingSettlement,
             .refundRequested, .refundApproved, .refundProcessing, .reconciling,
             .compliancePending, .authorizationRequired, .pendingReconciliation:
            return true
        default:
            return false
        }
    }

    /// Le cycle de vie est arrêté : plus aucune évolution sans nouvelle opération.
    var isTerminal: Bool {
        switch self {
        case .confirmed, .completed, .failed, .cancelled, .expired,
             .refunded, .partiallyRefunded, .reversed,
             .denied, .restricted:
            return true
        default:
            return false
        }
    }

    /// Compliance a la main. L'utilisateur ne peut rien débloquer depuis le client.
    var isComplianceControlled: Bool {
        switch self {
        case .restricted, .denied, .complianceHold, .amlReview:
            return true
        default:
            return false
        }
    }

    /// Seul le backend peut lever cet état — le client interroge, il ne conclut pas.
    var requiresReconciliation: Bool { self == .unknown || self == .inDoubt }

    /// L'argent a quitté le compte de l'émetteur, du point de vue utilisateur.
    ///
    /// `pendingSettlement` en fait partie : le règlement interbancaire est en
    /// cours, mais l'utilisateur a bien été débité.
    var isDebitVisibleToUser: Bool {
        switch self {
        case .confirmed, .completed, .pendingSettlement,
             .partiallyRefunded, .disputed:
            return true
        default:
            return false
        }
    }

    /// Autorise une nouvelle tentative pour la **même** intention utilisateur.
    ///
    /// `unknown` ne le permet pas : retenter une opération dont l'issue est
    /// inconnue est exactement le chemin du double débit.
    var allowsUserRetry: Bool {
        switch self {
        case .failed, .cancelled, .expired:
            return true
        default:
            return false
        }
    }
}

// MARK: - Rail Proof

/// Preuve remise par le rail de paiement externe.
///
/// `Equatable` : `PaymentConfirmation` en contient une et doit pouvoir être
/// comparée en test.
public struct RailProof: Codable, Sendable, Equatable {
    public let railProvider: String
    public let railTransactionId: String
    public let railSignature: String
    public let railTimestamp: Date
    public let railStatus: String
    public let railMetadata: [String: String]
    
    public init(
        railProvider: String,
        railTransactionId: String,
        railSignature: String,
        railTimestamp: Date,
        railStatus: String,
        railMetadata: [String: String]
    ) {
        self.railProvider = railProvider
        self.railTransactionId = railTransactionId
        self.railSignature = railSignature
        self.railTimestamp = railTimestamp
        self.railStatus = railStatus
        self.railMetadata = railMetadata
    }
}

// MARK: - Verification

public extension PaymentEnvelope {
    
    /// Verify backend signature (HMAC-SHA256)
    ///
    /// - Warning: **Ne vérifiait rien.** Le corps se réduisait à
    ///   `backendSignature.count >= 64`, qu'une chaîne de 64 caractères
    ///   arbitraires franchit. Le paramètre `secret` n'était même pas utilisé —
    ///   et un client ne doit de toute façon pas détenir le secret de signature.
    ///
    ///   Retourne désormais `false` systématiquement, pour qu'aucun appelant
    ///   existant ne puisse croire avoir vérifié quoi que ce soit. La
    ///   vérification réelle passe par `FinancialSignatureVerifying`, dont
    ///   l'implémentation détient une clé de vérification issue du trousseau.
    @available(*, deprecated, message: "Ne vérifie rien. Utiliser FinancialSignatureVerifying.")
    func verifySignature(secret: String) -> Bool {
        false
    }
    
    /// Verify rail proof
    func verifyRailProof() -> Bool {
        return !railProof.railProvider.isEmpty &&
               !railProof.railTransactionId.isEmpty &&
               railProof.railSignature.count >= 64
    }
    
    /// Check if payment is from backend
    var isFromBackend: Bool {
        return truthSource == .backend && !backendSignature.isEmpty
    }
    
    /// Check if payment has evidence
    var hasEvidence: Bool {
        return !evidenceRefs.isEmpty
    }
    
    /// Check if payment has rail proof
    var hasRailProof: Bool {
        return verifyRailProof()
    }
    
    /// Check if payment is final (confirmed by backend and rail)
    var isFinal: Bool {
        return [.confirmed, .completed].contains(status) && isFromBackend && hasRailProof
    }
    
    /// Check if payment is pending
    ///
    /// Délègue à `PaymentStatus.isInFlight` : la liste des statuts en cours vit
    /// sur l'enum, pour qu'un statut ajouté plus tard n'ait qu'un seul endroit à
    /// mettre à jour.
    var isPending: Bool { status.isInFlight }
    
    /// Check if payment is restricted
    var isRestricted: Bool { status.isComplianceControlled }
    
    /// Check if payment requires compliance review
    var requiresComplianceReview: Bool {
        return [.complianceHold, .amlReview].contains(status)
    }

    /// L'issue est inconnue du client : interroger le backend, ne rien conclure.
    ///
    /// Ni `isFinal` ni `isPending` ne sont vrais dans ce cas — c'est délibéré.
    /// Un objet en `unknown` n'a aucune place dans le raisonnement binaire
    /// abouti/en-cours qui produit les doubles débits.
    var requiresReconciliation: Bool { status.requiresReconciliation }
    
    /// Check if payment is cross-border
    var isCrossBorder: Bool {
        return crossBorder
    }
    
    /// Total amount including fees
    var totalAmount: Decimal {
        if let feeAmount = feeAmount, feeCurrency == currency {
            return amount + feeAmount
        }
        return amount
    }
}

// MARK: - Equatable

extension PaymentEnvelope: Equatable {
    public static func == (lhs: PaymentEnvelope, rhs: PaymentEnvelope) -> Bool {
        return lhs.id == rhs.id &&
               lhs.idempotencyKey == rhs.idempotencyKey &&
               lhs.backendSignature == rhs.backendSignature
    }
}

// MARK: - Hashable

extension PaymentEnvelope: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(idempotencyKey)
        hasher.combine(backendSignature)
    }
}
