//
//  ExecutionPermitBinding.swift
//  CoreKit
//
//  Les onze dimensions du permis d'exécution — Bloc 7, §56.2.
//
//  **BACKEND CONTRACT REQUIRED** — le permis est signé par le backend ; le
//  client vérifie la liaison, il ne l'accorde pas.
//
//  Complète ``ExecutionPermit`` (Bloc 2 §13.4), qui lie l'exécution à un objet,
//  à un aperçu et à une échéance. Ces trois liens sont nécessaires et ne
//  suffisent pas : ils laissent passer un permis présenté par un autre acteur,
//  depuis un autre canal, ou sur un autre compte débité.
//

import Foundation

/// Par où l'ordre arrive.
///
/// Le canal fait partie de la liaison parce qu'un permis obtenu dans un parcours
/// surveillé ne doit pas pouvoir être rejoué sur un chemin qui ne l'est pas.
public enum ExecutionChannel: String, Codable, Sendable, Hashable, CaseIterable {
    case chat    = "CHAT"
    case wallet  = "WALLET"
    case web     = "WEB"
    case api     = "API"
    case ussd    = "USSD"
    case agent   = "AGENT"
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExecutionChannel(rawValue: raw) ?? .unknown
    }
}

// MARK: - La liaison

/// Ce à quoi un permis est lié.
///
/// Onze dimensions, et chacune ferme un rejeu que les autres laissent ouvert.
/// Le §56.2 les énumère ; les omettre une à une est exactement la façon dont un
/// permis devient un jeton au porteur.
public struct ExecutionPermitBinding: Codable, Sendable, Hashable {

    /// 1. Qui exécute.
    public let actorID: String

    /// 2. Pour le compte de quelle entité.
    public let companyID: String

    /// 3 et 4. Combien, et en quoi.
    ///
    /// `Money` porte les deux, mais la vérification les sépare : « mauvais
    /// montant » et « mauvaise devise » ne se diagnostiquent pas pareil, et
    /// 100 EUR contre 100 XAF n'est pas une erreur de saisie.
    public let amount: Money

    /// 5. Vers qui.
    public let beneficiaryRef: String

    /// 6. Depuis quel compte ou instrument. Un permis pour 100 depuis le compte
    /// A n'autorise pas 100 depuis le compte B.
    public let sourceInstrumentID: String

    /// 7. Par quel chemin.
    public let channel: ExecutionChannel

    /// 8. Quelle opération.
    public let action: FinancialActionClass

    /// 9. Sous quelle version de politique la décision a été prise.
    ///
    /// Une politique qui change entre l'accord et l'exécution invalide le
    /// permis : les plafonds, les frais et les contrôles ont pu bouger.
    public let policyVersion: String

    /// 10. Jusqu'à quand.
    public let expiresAt: Date

    /// 11. Usage unique. Le nonce est ce qui rend le rejeu détectable même
    /// quand tout le reste correspond — c'est la seule dimension qu'un
    /// attaquant qui rejoue une requête légitime ne peut pas satisfaire deux
    /// fois.
    public let nonce: String

    public init(actorID: String, companyID: String, amount: Money,
                beneficiaryRef: String, sourceInstrumentID: String,
                channel: ExecutionChannel, action: FinancialActionClass,
                policyVersion: String, expiresAt: Date, nonce: String) {
        self.actorID = actorID
        self.companyID = companyID
        self.amount = amount
        self.beneficiaryRef = beneficiaryRef
        self.sourceInstrumentID = sourceInstrumentID
        self.channel = channel
        self.action = action
        self.policyVersion = policyVersion
        self.expiresAt = expiresAt
        self.nonce = nonce
    }
}

/// Ce qui est sur le point d'être exécuté.
///
/// Même forme que la liaison, moins l'échéance et le nonce : ceux-là
/// appartiennent au permis, pas à la demande. Un type distinct plutôt qu'une
/// comparaison de deux `ExecutionPermitBinding` — comparer une liaison à une
/// liaison invite à passer la même des deux côtés, ce qui réussit toujours.
public struct ExecutionRequest: Sendable, Hashable {

    public let actorID: String
    public let companyID: String
    public let amount: Money
    public let beneficiaryRef: String
    public let sourceInstrumentID: String
    public let channel: ExecutionChannel
    public let action: FinancialActionClass
    public let policyVersion: String

    public init(actorID: String, companyID: String, amount: Money,
                beneficiaryRef: String, sourceInstrumentID: String,
                channel: ExecutionChannel, action: FinancialActionClass,
                policyVersion: String) {
        self.actorID = actorID
        self.companyID = companyID
        self.amount = amount
        self.beneficiaryRef = beneficiaryRef
        self.sourceInstrumentID = sourceInstrumentID
        self.channel = channel
        self.action = action
        self.policyVersion = policyVersion
    }
}

// MARK: - Les douze rejets (§56.2)

/// Pourquoi un permis ne vaut pas pour cette exécution.
///
/// Les douze cas du §56.2, un par cas. Énumérés plutôt que réduits à un booléen
/// pour que chacun soit **testable nommément** : `wrongActor` et `replayed` ne
/// se corrigent pas de la même façon, et un test qui ne sait dire que « refusé »
/// passerait encore si le contrôle du montant disparaissait.
public enum ExecutionPermitRejection: String, Error, Sendable, Hashable, CaseIterable {

    case wrongActor          = "WRONG_ACTOR"
    case wrongCompany        = "WRONG_COMPANY"
    case wrongAmount         = "WRONG_AMOUNT"
    case wrongCurrency       = "WRONG_CURRENCY"
    case wrongBeneficiary    = "WRONG_BENEFICIARY"
    case wrongInstrument     = "WRONG_INSTRUMENT"
    case wrongChannel        = "WRONG_CHANNEL"
    case wrongAction         = "WRONG_ACTION"
    case stalePolicyVersion  = "STALE_POLICY_VERSION"
    case expired             = "EXPIRED"
    case replayed            = "REPLAYED"

    /// L'aperçu accepté par l'utilisateur ne correspond plus.
    case tamperedSnapshot    = "TAMPERED_SNAPSHOT"

    /// Message affichable. Aucun de ces motifs n'expose de donnée d'un tiers,
    /// mais tous restent des clés — la composition de phrase se fait à
    /// l'affichage.
    public var messageKey: String { "finance.permit.rejected.\(rawValue.lowercased())" }

    /// L'utilisateur peut-il refaire l'opération immédiatement ?
    ///
    /// Un permis périmé se redemande. Un permis rejoué signale soit un bug de
    /// retry, soit une attaque — dans les deux cas, recommencer en boucle est
    /// la mauvaise réaction.
    public var isRetryable: Bool {
        switch self {
        case .expired, .stalePolicyVersion, .tamperedSnapshot:
            return true
        case .wrongActor, .wrongCompany, .wrongAmount, .wrongCurrency,
             .wrongBeneficiary, .wrongInstrument, .wrongChannel, .wrongAction,
             .replayed:
            return false
        }
    }

    /// À remonter comme incident de sécurité.
    ///
    /// Une divergence d'acteur, de société ou d'instrument, et tout rejeu, ne
    /// s'expliquent pas par une erreur d'utilisateur.
    public var isSecurityIncident: Bool {
        switch self {
        case .wrongActor, .wrongCompany, .wrongInstrument, .wrongBeneficiary,
             .replayed, .tamperedSnapshot:
            return true
        case .wrongAmount, .wrongCurrency, .wrongChannel, .wrongAction,
             .stalePolicyVersion, .expired:
            return false
        }
    }
}

// MARK: - Permis lié

/// Un permis et sa liaison.
///
/// ``ExecutionPermit`` reste inchangé — le Bloc 2 s'en sert déjà. Ce type
/// l'enveloppe au lieu de le remplacer, pour que la vérification des onze
/// dimensions s'ajoute sans réécrire les appelants existants.
public struct BoundExecutionPermit: Codable, Sendable, Equatable {

    public let permit: ExecutionPermit
    public let binding: ExecutionPermitBinding

    public init(permit: ExecutionPermit, binding: ExecutionPermitBinding) {
        self.permit = permit
        self.binding = binding
    }

    /// Vérifie les onze dimensions. Rend `nil` si le permis autorise vraiment
    /// cette exécution.
    ///
    /// L'ordre des contrôles est celui du diagnostic le plus utile : l'identité
    /// d'abord — un permis présenté par le mauvais acteur est un incident, pas
    /// une erreur de montant à corriger — puis les valeurs, puis le temps, puis
    /// le rejeu.
    ///
    /// - Parameters:
    ///   - request: ce qui est sur le point d'être exécuté.
    ///   - snapshot: l'aperçu accepté, pour revérifier le lien du Bloc 2.
    ///   - consumedNonces: les nonces déjà consommés connus de ce client.
    ///     Détection locale et **non autoritaire** : le backend reste seul juge
    ///     du rejeu, mais attraper le cas ici évite d'émettre la requête.
    public func validate(
        for request: ExecutionRequest,
        snapshot: ConfirmationSnapshot? = nil,
        consumedNonces: Set<String> = [],
        now: Date = Date()
    ) -> ExecutionPermitRejection? {

        // 1 et 2 — identité.
        guard binding.actorID == request.actorID       else { return .wrongActor }
        guard binding.companyID == request.companyID   else { return .wrongCompany }

        // 3 et 4 — valeur. Séparés : la devise n'est pas un détail du montant.
        guard binding.amount.currency == request.amount.currency else { return .wrongCurrency }
        guard binding.amount.minorUnits == request.amount.minorUnits else { return .wrongAmount }

        // 5 et 6 — destination et origine.
        guard binding.beneficiaryRef == request.beneficiaryRef             else { return .wrongBeneficiary }
        guard binding.sourceInstrumentID == request.sourceInstrumentID     else { return .wrongInstrument }

        // 7 et 8 — chemin et opération.
        guard binding.channel == request.channel  else { return .wrongChannel }
        guard binding.action == request.action    else { return .wrongAction }

        // 9 — politique.
        guard binding.policyVersion == request.policyVersion else { return .stalePolicyVersion }

        // 10 — temps. La plus courte des deux échéances l'emporte : un permis
        // dont la liaison expire avant lui n'est pas prolongé par l'enveloppe.
        guard now < binding.expiresAt, !permit.isExpired(asOf: now) else { return .expired }

        // 11 — usage unique.
        guard !consumedNonces.contains(binding.nonce) else { return .replayed }

        // Le lien du Bloc 2, revérifié quand l'aperçu est fourni.
        if let snapshot, !permit.authorizes(snapshot, asOf: now) {
            return .tamperedSnapshot
        }

        return nil
    }
}

// MARK: - Registre local des nonces

/// Retient les nonces déjà consommés sur cet appareil.
///
/// **Ne remplace pas le contrôle backend.** Un client compromis peut vider ce
/// registre ; c'est pourquoi le rejeu reste refusé côté serveur. L'intérêt est
/// ailleurs : un rejeu accidentel — un retry après timeout, un double tap, une
/// reprise d'outbox — est attrapé avant de partir, et n'a donc aucune chance de
/// se dédoubler dans un intervalle de réplication.
public actor ExecutionPermitLedger {

    private var consumed: Set<String> = []

    /// Borne de rétention. Un registre non borné croît sans fin ; au-delà, les
    /// plus anciens sortent — ils sont de toute façon périmés côté permis.
    private let capacity: Int
    private var order: [String] = []

    public init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    public var consumedNonces: Set<String> { consumed }

    public func isConsumed(_ nonce: String) -> Bool { consumed.contains(nonce) }

    /// Marque un nonce comme consommé. Rend `false` s'il l'était déjà — c'est
    /// la détection de rejeu.
    @discardableResult
    public func markConsumed(_ nonce: String) -> Bool {
        guard consumed.insert(nonce).inserted else { return false }
        order.append(nonce)
        if order.count > capacity {
            let evicted = order.removeFirst()
            consumed.remove(evicted)
        }
        return true
    }

    public func reset() {
        consumed.removeAll()
        order.removeAll()
    }
}

// MARK: - Contrat

/// Émet des permis portant les onze dimensions.
public protocol BoundExecutionPermitIssuing: Sendable {

    /// Demande un permis lié.
    ///
    /// - Parameter idempotency: la clé de l'intention, **pas une neuve** —
    ///   même règle qu'à ``ExecutionPermitIssuing/issue(for:idempotency:stepUp:)``.
    func issueBound(
        for snapshot: ConfirmationSnapshot,
        request: ExecutionRequest,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<BoundExecutionPermit, FinanceError>

    func consume(_ permit: BoundExecutionPermit) async -> Result<Void, FinanceError>
}
