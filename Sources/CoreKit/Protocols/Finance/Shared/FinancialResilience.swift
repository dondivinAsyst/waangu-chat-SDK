//
//  FinancialResilience.swift
//  CoreKit
//
//  Idempotence, requête d'état, réessai — Bloc 6, §15, §17, §18, §19.
//

import Foundation

// MARK: - Registre d'idempotence (§17)

/// Retient la réponse d'une opération, pour ne pas la refaire.
///
/// Le §17 en donne le squelette ; ce qui suit ajoute la seule chose qui compte
/// vraiment : **l'empreinte de la requête**. Une clé rejouée avec un contenu
/// différent n'est pas un doublon, c'est une collision — et rendre la réponse
/// mémorisée débiterait un montant pour en afficher un autre.
///
/// Le registre est une **première ligne**. L'autorité reste le serveur, qui
/// seul voit les tentatives venues d'un autre appareil. Ici, on évite le
/// double-clic, le retour arrière, et le réessai réflexe après un timeout.
public actor IdempotencyStore {

    public struct Record: Sendable {
        public let key: String
        public let requestHash: String
        public let responseData: Data
        public let createdAt: Date
        public let expiresAt: Date
    }

    private var records: [String: Record] = [:]

    /// Nombre maximal d'entrées retenues.
    ///
    /// Sans borne, un processus de longue durée accumule indéfiniment. La purge
    /// par expiration ne suffit pas : des TTL longs et un usage intense
    /// suffisent à faire grossir la table entre deux expirations.
    private let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    /// Ce que le registre sait d'une clé.
    ///
    /// - `nil` : jamais vue, ou expirée — l'opération peut partir.
    /// - `.success` : déjà exécutée, voici sa réponse.
    /// - `.failure(.requestConflict)` : **même clé, requête différente.**
    public func resolve(key: String, requestHash: String,
                        now: Date = Date()) -> Result<Data, IdempotencyError>? {
        guard let record = records[key] else { return nil }

        guard record.expiresAt > now else {
            records.removeValue(forKey: key)
            return nil
        }

        // Le contrôle qui distingue un doublon d'une collision. Sans lui, deux
        // paiements différents partageant une clé rendraient la même réponse,
        // et le second semblerait avoir abouti sans être jamais parti.
        guard record.requestHash == requestHash else {
            return .failure(.requestConflict)
        }

        return .success(record.responseData)
    }

    public func store(key: String, requestHash: String, responseData: Data,
                      ttl: TimeInterval, now: Date = Date()) {
        purgeExpired(now: now)

        if records.count >= capacity, records[key] == nil {
            // Évince la plus ancienne. Un registre plein qui refuse d'écrire
            // perdrait la protection sur les opérations les plus récentes,
            // c'est-à-dire celles qui sont en cours.
            if let oldest = records.min(by: { $0.value.createdAt < $1.value.createdAt })?.key {
                records.removeValue(forKey: oldest)
            }
        }

        records[key] = Record(
            key: key, requestHash: requestHash, responseData: responseData,
            createdAt: now, expiresAt: now.addingTimeInterval(ttl)
        )
    }

    /// Oublie une clé — après un échec définitif, où la réessayer est légitime.
    public func forget(key: String) {
        records.removeValue(forKey: key)
    }

    public func purgeExpired(now: Date = Date()) {
        records = records.filter { $0.value.expiresAt > now }
    }

    public var count: Int { records.count }
}

public enum IdempotencyError: Error, Sendable, Equatable {
    /// Même clé, contenu différent.
    case requestConflict
}

// MARK: - Vérité financière (§19)

/// L'issue d'une opération financière, telle que le serveur la connaît.
///
/// Quatre inégalités portent tout le §18, et les confondre est la cause
/// mécanique du double débit :
///
///     UNKNOWN    ≠ FAILED
///     PENDING    ≠ FAILED
///     AUTHORIZED ≠ CAPTURED
///     SUBMITTED  ≠ CONFIRMED
public enum FinancialTruth: String, Codable, Sendable, CaseIterable {
    case confirmed
    case processing
    case pending
    case failed
    case reversed
    case unknown

    /// Peut être présenté comme abouti.
    public var isSettled: Bool { self == .confirmed }

    /// **Ne jamais rejouer.** Il faut requêter.
    public var requiresRequery: Bool {
        self == .pending || self == .processing || self == .unknown
    }

    /// Une nouvelle tentative est légitime : rien n'a abouti, rien n'est en vol.
    public var permitsRetry: Bool { self == .failed }

    /// Projette un statut détaillé sur les six issues.
    ///
    /// La projection est **délibérément prudente** : tout ce qui n'est pas un
    /// échec ou un aboutissement avéré devient `pending` ou `unknown`, jamais
    /// `failed`. Se tromper vers `pending` fait attendre ; se tromper vers
    /// `failed` fait payer deux fois.
    public static func from(_ status: PaymentStatus) -> FinancialTruth {
        switch status {
        case .confirmed, .completed:
            return .confirmed
        case .processing, .syncing, .authorized, .pendingProvider:
            return .processing
        case .queued, .pending, .pendingSettlement, .pendingReconciliation,
             .compliancePending, .authorizationRequired, .reconciling,
             .complianceHold, .amlReview, .refundRequested, .refundApproved,
             .refundProcessing, .disputed, .restricted:
            return .pending
        case .failed, .cancelled, .expired, .denied:
            return .failed
        case .reversed, .refunded, .partiallyRefunded:
            return .reversed
        case .unknown, .inDoubt:
            return .unknown
        }
    }
}

// MARK: - Passerelle de paiement marchand (§18)

/// Orchestration d'un paiement marchand.
///
/// Trois opérations, et une règle : `requery` **ne relance jamais**. Un état
/// incertain se clarifie ; le rejouer transforme une réponse perdue en second
/// débit.
public protocol MerchantPaymentGateway: Sendable {

    func createIntent(request: MerchantPaymentIntentRequest) async throws -> MerchantPaymentIntent

    func confirm(intentID: String, idempotencyKey: String) async throws -> MerchantPaymentOutcome

    /// Redemande l'état. **Aucun effet de bord.**
    func requery(intentID: String) async throws -> MerchantPaymentOutcome
}

public struct MerchantPaymentIntentRequest: Sendable, Hashable, Codable {
    public let merchantID: String
    public let amount: Money
    public let reference: String?
    public let conversationID: String?
    /// Identité marchande épinglée — voir `MerchantIdentitySnapshot`.
    public let identity: MerchantIdentitySnapshot

    public init(merchantID: String, amount: Money, reference: String? = nil,
                conversationID: String? = nil, identity: MerchantIdentitySnapshot) {
        self.merchantID = merchantID
        self.amount = amount
        self.reference = reference
        self.conversationID = conversationID
        self.identity = identity
    }

    /// Empreinte stable de la requête, pour le registre d'idempotence.
    ///
    /// Recalculée à chaque tentative : c'est en la comparant qu'on distingue un
    /// réessai légitime d'une clé réutilisée pour autre chose.
    public var requestHash: String {
        var hasher = Hasher()
        hasher.combine(merchantID)
        hasher.combine(amount.minorUnits)
        hasher.combine(amount.currency.code)
        hasher.combine(reference)
        hasher.combine(identity.identityVersion)
        return String(hasher.finalize())
    }
}

public struct MerchantPaymentIntent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let reference: FinancialReference
    public let amount: Money
    public let expiresAt: Date?
    /// Le backend exige-t-il une authentification renforcée ?
    public let requiredStepUpLevel: StepUpLevel?

    public init(id: String, reference: FinancialReference, amount: Money,
                expiresAt: Date? = nil, requiredStepUpLevel: StepUpLevel? = nil) {
        self.id = id
        self.reference = reference
        self.amount = amount
        self.expiresAt = expiresAt
        self.requiredStepUpLevel = requiredStepUpLevel
    }

    public func hasExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

public struct MerchantPaymentOutcome: Codable, Sendable, Hashable {
    public let intentID: String
    public let truth: FinancialTruth
    public let status: PaymentStatus
    public let reference: FinancialReference?
    public let observedAt: Date

    public init(intentID: String, truth: FinancialTruth, status: PaymentStatus,
                reference: FinancialReference? = nil, observedAt: Date) {
        self.intentID = intentID
        self.truth = truth
        self.status = status
        self.reference = reference
        self.observedAt = observedAt
    }
}

// MARK: - Politique de réessai (§15)

/// Quand réessayer, et surtout quand ne pas.
///
/// Le §15 l'écrit en une ligne : « Interdire les retries aveugles sur les
/// opérations financières. » Cette politique rend l'interdiction structurelle —
/// `nextDelay` **rend `nil`** pour une opération qui déplace de l'argent dès
/// que l'issue n'est pas un échec avéré.
public struct RetryPolicy: Sendable, Hashable {

    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    /// Amplitude du bruit, en fraction du délai. `0.2` ⇒ ±20 %.
    ///
    /// Sans bruit, mille clients qui échouent ensemble réessaient ensemble, et
    /// la deuxième vague achève le service que la première a fait tomber.
    public let jitterFactor: Double

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5,
                maxDelay: TimeInterval = 8, jitterFactor: Double = 0.2) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = jitterFactor
    }

    /// Politique des opérations qui **déplacent de l'argent**.
    ///
    /// Une seule tentative. Un paiement qui n'a pas répondu se requête, il ne
    /// se rejoue pas — le contraire est la définition du double débit.
    public static let financialWrite = RetryPolicy(maxAttempts: 1)

    /// Politique des lectures. Réessayer une lecture ne coûte rien.
    public static let read = RetryPolicy(maxAttempts: 4, baseDelay: 0.3, maxDelay: 5)

    /// Délai avant la tentative `attempt` (1 = première nouvelle tentative).
    ///
    /// `nil` quand il ne faut plus réessayer. Le `randomness` est injecté pour
    /// que le bruit soit testable — un `random` interne rendrait le calcul
    /// invérifiable.
    public func nextDelay(afterAttempt attempt: Int,
                          randomness: Double = Double.random(in: 0...1)) -> TimeInterval? {
        guard attempt >= 1, attempt < maxAttempts else { return nil }

        let exponential = baseDelay * pow(2, Double(attempt - 1))
        let capped = min(exponential, maxDelay)

        // Bruit centré : ±jitterFactor autour du délai, jamais négatif.
        let spread = capped * jitterFactor
        let offset = (randomness * 2 - 1) * spread
        return max(0, capped + offset)
    }

    /// Cette issue autorise-t-elle une nouvelle tentative ?
    ///
    /// Le garde-fou du §15. Un `unknown` ou un `pending` ne se rejoue jamais,
    /// quelle que soit la politique : il se requête.
    public func permitsRetry(after truth: FinancialTruth, attempt: Int) -> Bool {
        guard truth.permitsRetry else { return false }
        return attempt < maxAttempts
    }
}

// MARK: - Décision d'exécution

/// Ce qu'il faut faire d'une opération financière dont l'issue est incertaine.
///
/// Rend la décision **explicite et testable**, au lieu de la laisser à un `if`
/// recopié dans chaque écran — c'est dans l'un de ces `if` que finit par
/// s'écrire le rejeu qui double le débit.
public enum FinancialRetryDecision: Sendable, Equatable {

    /// Rien à faire : l'opération a abouti.
    case settled

    /// Requêter après ce délai. **Sans rien renvoyer.**
    case requery(after: TimeInterval)

    /// Réessayer après ce délai — l'échec est avéré.
    case retry(after: TimeInterval)

    /// Abandonner et le dire.
    case giveUp(reason: FinancialGiveUpReason)

    /// Décide, à partir de l'issue et du nombre de tentatives déjà faites.
    public static func decide(
        truth: FinancialTruth,
        attempt: Int,
        policy: RetryPolicy,
        requeryDelay: TimeInterval = 2,
        randomness: Double = Double.random(in: 0...1)
    ) -> FinancialRetryDecision {

        if truth.isSettled { return .settled }
        if truth == .reversed { return .giveUp(reason: .reversed) }

        // Incertain : on interroge, on ne rejoue pas. Ce cas précède
        // volontairement le contrôle du nombre de tentatives — requêter reste
        // légitime même après avoir épuisé les réessais.
        if truth.requiresRequery {
            return .requery(after: requeryDelay)
        }

        guard policy.permitsRetry(after: truth, attempt: attempt) else {
            return .giveUp(reason: attempt >= policy.maxAttempts ? .attemptsExhausted : .notRetryable)
        }

        guard let delay = policy.nextDelay(afterAttempt: attempt, randomness: randomness) else {
            return .giveUp(reason: .attemptsExhausted)
        }
        return .retry(after: delay)
    }
}

public enum FinancialGiveUpReason: String, Sendable, Equatable {
    case attemptsExhausted
    case notRetryable
    case reversed
}
