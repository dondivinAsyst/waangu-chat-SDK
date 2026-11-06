//
//  LiveCashServices.swift
//  FeatureChat
//
//  Espèces — dépôt et retrait, INTEGRATION_CHAT_FINANCE.md §6.
//

import Foundation
import WaanguCoreKit

/// `CashInInitiating` servi par Chat Core — étape 1 : les canaux.
///
/// `createInstruction` reste **fermé**. Le contrat ne crée pas un dépôt d'un
/// appel : il prépare, l'utilisateur confirme, puis exécute — et la confirmation
/// physique d'un agent n'est toujours pas un crédit (`CF_038`). Rendre une
/// instruction ici laisserait croire le dépôt lancé alors que rien ne l'est.
struct LiveCashIn: CashInInitiating {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let quoting: LiveQuotedOperations
    let deviceID: @Sendable () -> String

    /// Ce service demande toujours un devis : `/cash-in/prepare`, puis la
    /// confirmation humaine. Un refus du prepare est **le** résultat.
    var providesQuotes: Bool { true }

    func availableChannels() async -> Result<[CashInChannel], FinanceError> {
        switch await FinanceCoreError.capture({ try await dataSource.cashInChannels() }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceCash] cash-in channels failed: \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let channels):
            #if DEBUG
            print("[FinanceCash] cash-in channels: \(channels)")
            #endif
            return .success(CashChannelMapper.cashIn(channels))
        }
    }

    /// `POST /cash-in/prepare` — un devis à confirmer, jamais un dépôt lancé.
    ///
    /// Corps `MoneyOpBody`, tel que le contrat le publie désormais (§6, DTOs) :
    /// `conversationId` (optionnel ⇒ dossier `SELF`), `idempotencyKey`,
    /// `currency`, `amountMinor` **ou** `amount`, `channel` — le canal de dépôt,
    /// `AGENT` — `agentId` et `deviceId`.
    ///
    /// La première version envoyait `channel: "MOBILE"` et un `cashChannel`
    /// inventé : `channel` **est** le canal d'espèces, et le canal applicatif
    /// n'a pas sa place dans ce corps.
    func quote(_ request: CashInRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        var body: [String: Any] = [
            "currency": request.currency,
            "channel": CashChannelMapper.wire(request.channel),
            "deviceId": deviceID()
        ]
        if let amount = request.amount {
            body["amountMinor"] = LiveSendMoney.minorUnits(amount, currency: request.currency)
        }
        if let conversation = request.conversationID, !conversation.isEmpty {
            body["conversationId"] = conversation
        }
        if let agent = request.agentID, !agent.isEmpty {
            body["agentId"] = agent
        }
        let outcome = await quoting.prepare(.cashIn, body: body, idempotency: idempotency)
        #if DEBUG
        if case .failure(let error) = outcome {
            print("[FinanceCash] cash-in prepare failed (channel=\(request.channel.rawValue)): \(error)")
        }
        #endif
        return outcome
    }

    /// **Jamais un dépôt direct.** Le parcours passe par ``quote`` puis la
    /// confirmation explicite — §6, et §0.3.1.
    func createInstruction(_ request: CashInRequest,
                           idempotency: IdempotencyContext) async -> Result<CashInInstruction, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func requery(_ reference: FinancialReference) async -> Result<CashInInstruction, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    // MARK: - Dépôt chez un agent

    func verifyAgent(_ reference: FinancialReference, conversationID: String?,
                     agentID: String) async -> Result<CashInAgentOverlay, FinanceError> {
        let request = CashAgentRequest(
            financialIntentRef: reference.id,
            conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 },
            agentId: agentID)
        return await overlay(reference) {
            // `CF_037` : agent non vérifié.
            try await dataSource.verifyAgent(request)
        }
    }

    func confirmPhysical(_ reference: FinancialReference,
                         conversationID: String?) async -> Result<CashInAgentOverlay, FinanceError> {
        let request = CashRefRequest(
            financialIntentRef: reference.id,
            conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 })
        return await overlay(reference) {
            try await dataSource.confirmPhysical(request)
        }
    }

    private func overlay(_ reference: FinancialReference,
                         _ call: () async throws -> CashInOverlayDTO)
    async -> Result<CashInAgentOverlay, FinanceError> {
        switch await FinanceCoreError.capture(call) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceCash] agent step failed (ref=\(reference.id)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let dto):
            #if DEBUG
            print("[FinanceCash] cash-in overlay: verified=\(dto.agentVerified ?? false) "
                  + "received=\(dto.physicalReceivedAt ?? "nil") credit=\(dto.creditState ?? "nil")")
            #endif
            return .success(CashChannelMapper.overlay(dto, reference: reference))
        }
    }
}

/// `CashOutIssuing` servi par Chat Core — étape 1 : les canaux.
///
/// `issue` reste **fermé**. Un retrait se prépare, se confirme, puis s'exécute,
/// et le jeton de retrait est **émis par Finance** — « Chat n'invente plus de
/// jeton local » (§6). En rendre un ici fabriquerait un code qui n'autorise rien.
struct LiveCashOut: CashOutIssuing {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let quoting: LiveQuotedOperations
    let deviceID: @Sendable () -> String

    var providesQuotes: Bool { true }

    func availableChannels() async -> Result<[CashOutChannel], FinanceError> {
        switch await FinanceCoreError.capture({ try await dataSource.cashOutChannels() }) {
        case .failure(let error):
            // `CF_068` : retrait à haut risque sans service Risk câblé.
            #if DEBUG
            print("[FinanceCash] cash-out channels failed: \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let channels):
            #if DEBUG
            print("[FinanceCash] cash-out channels: \(channels)")
            #endif
            return .success(CashChannelMapper.cashOut(channels))
        }
    }

    /// `POST /cash-out/prepare` — même `MoneyOpBody` que le dépôt (§6).
    ///
    /// Retrait = haut risque : `LiveQuotedOperations` refuse d'avance sans le
    /// droit de session `CASH_OUT` (`CF_068`), avant tout appel réseau.
    func quote(_ request: CashOutRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        var body: [String: Any] = [
            "currency": request.currency,
            "amountMinor": LiveSendMoney.minorUnits(request.amount, currency: request.currency),
            "channel": CashChannelMapper.wire(request.channel),
            "deviceId": deviceID()
        ]
        if let conversation = request.conversationID, !conversation.isEmpty {
            body["conversationId"] = conversation
        }
        let outcome = await quoting.prepare(.cashOut, body: body, idempotency: idempotency)
        #if DEBUG
        if case .failure(let error) = outcome {
            print("[FinanceCash] cash-out prepare failed (channel=\(request.channel.rawValue)): \(error)")
        }
        #endif
        return outcome
    }

    /// **Jamais un jeton local.** Le code vient de Finance — §6 : « Chat
    /// n'invente plus de jeton local ». Voir ``issueToken``.
    func issue(_ request: CashOutRequest, idempotency: IdempotencyContext,
               stepUp: StepUpAttestation?) async -> Result<CashOutAuthorization, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func revoke(_ reference: FinancialReference,
                idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        await revokeToken(reference, conversationID: nil).map { _ in () }
    }

    func requery(_ reference: FinancialReference) async -> Result<CashOutAuthorization, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    // MARK: - Le jeton de retrait

    /// `POST /cash-out/token` — émis par Finance, rendu **une seule fois**.
    func issueToken(_ reference: FinancialReference, conversationID: String?,
                    agentID: String) async -> Result<CashOutToken, FinanceError> {
        let request = CashAgentRequest(
            financialIntentRef: reference.id,
            conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 },
            agentId: agentID)
        switch await FinanceCoreError.capture({ try await dataSource.issueCashOutToken(request) }) {
        case .failure(let error):
            // `CF_051` : Finance non câblé — aucun jeton, et surtout pas un local.
            #if DEBUG
            print("[FinanceCash] cash-out token failed (ref=\(reference.id)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let dto):
            // Le code **ne se journalise pas** : seule son échéance est tracée.
            #if DEBUG
            print("[FinanceCash] cash-out token issued, expires=\(dto.expiresAt ?? "nil")")
            #endif
            return .success(CashOutToken(code: dto.token,
                                         expiresAt: FinanceCoreDates.parse(dto.expiresAt),
                                         message: dto.message))
        }
    }

    func consumeToken(_ reference: FinancialReference, conversationID: String?,
                      token: String, agentID: String) async -> Result<CashOutTokenOverlay, FinanceError> {
        let request = CashTokenRequest(
            financialIntentRef: reference.id,
            conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 },
            token: token, agentId: agentID)
        // `CF_039` : rejoué, expiré, révoqué ou refusé par Finance.
        return await overlay(reference) { try await dataSource.consumeCashOutToken(request) }
    }

    func revokeToken(_ reference: FinancialReference,
                     conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError> {
        await overlay(reference) {
            try await dataSource.revokeCashOutToken(Self.ref(reference, conversationID))
        }
    }

    func confirmRemittance(_ reference: FinancialReference,
                           conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError> {
        await overlay(reference) {
            try await dataSource.confirmRemittance(Self.ref(reference, conversationID))
        }
    }

    func reportIncident(_ reference: FinancialReference,
                        conversationID: String?) async -> Result<CashOutTokenOverlay, FinanceError> {
        await overlay(reference) {
            try await dataSource.cashOutIncident(Self.ref(reference, conversationID))
        }
    }

    private static func ref(_ reference: FinancialReference, _ conversationID: String?) -> CashRefRequest {
        CashRefRequest(financialIntentRef: reference.id,
                       conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 })
    }

    private func overlay(_ reference: FinancialReference,
                         _ call: () async throws -> CashOutOverlayDTO)
    async -> Result<CashOutTokenOverlay, FinanceError> {
        switch await FinanceCoreError.capture(call) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceCash] cash-out step failed (ref=\(reference.id)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let dto):
            #if DEBUG
            print("[FinanceCash] cash-out overlay: consumed=\(dto.consumedAt ?? "nil") "
                  + "remitted=\(dto.remittedAt ?? "nil") revoked=\(dto.revoked ?? false)")
            #endif
            return .success(CashChannelMapper.overlay(dto, reference: reference))
        }
    }
}

// MARK: - Les canaux

/// Le code du serveur vers le canal que l'écran sait instruire.
///
/// Le serveur rend une **liste de codes** — `["AGENT","BANK_BRANCH"]` (§6,
/// DTOs). Une première version attendait des objets `{code,label,enabled,…}`,
/// inventés faute de contrat publié : le décodage échouait, et aucun canal
/// n'arrivait à l'écran.
///
/// **Une liste vide reste vide.** Sur un marché sans canal d'espèces — le
/// Canada aujourd'hui — le serveur rend `[]`, et l'écran n'affiche rien. Le
/// contrat l'écrit noir sur blanc : « ne pas coder un `if CA` ». Aucun pays
/// n'est nommé nulle part ici, et un test le vérifie.
enum CashChannelMapper {

    static func cashIn(_ codes: [String]) -> [CashInChannel] {
        codes.compactMap { code in
            switch normalized(code) {
            case "AGENT":                              return .agent
            // `BANK_BRANCH` est celui que le serveur rend ; les autres
            // orthographes restent acceptées.
            case "BANKBRANCH", "BANK", "BANKTRANSFER": return .bank
            case "CARD":                               return .card
            case "MOBILEMONEY", "MOMO":                return .mobileMoney
            case "OPENBANKING":                        return .openBanking
            // Un canal que cette version ne sait pas instruire n'est pas
            // proposé : on n'envoie personne déposer sans pouvoir lui dire où.
            default:                                   return nil
            }
        }
    }

    static func cashOut(_ codes: [String]) -> [CashOutChannel] {
        codes.compactMap { code in
            switch normalized(code) {
            case "AGENT":                              return .agent
            case "ATM":                                return .atm
            case "BANKBRANCH", "BANK", "BANKTRANSFER": return .bank
            case "MERCHANT":                           return .merchant
            default:                                   return nil
            }
        }
    }

    /// `CashInOverlay` du serveur vers le modèle de l'écran.
    ///
    /// `creditState` est repris **tel quel** : c'est le serveur qui nomme
    /// l'état du crédit, et `CashInAgentOverlay.isCredited` n'accorde le crédit
    /// qu'à une liste fermée. Un état inconnu n'est donc pas un crédit —
    /// `CF_038` dans l'autre sens.
    static func overlay(_ dto: CashInOverlayDTO,
                        reference: FinancialReference) -> CashInAgentOverlay {
        CashInAgentOverlay(
            reference: reference,
            conversationID: dto.conversationId,
            channel: dto.channel.flatMap { cashIn([$0]).first },
            agentID: dto.agentId,
            agentVerified: dto.agentVerified ?? false,
            physicalReceivedAt: FinanceCoreDates.parse(dto.physicalReceivedAt),
            financeReference: dto.financeRef,
            creditState: dto.creditState ?? "")
    }

    /// `CashOutOverlay` du serveur vers le modèle de l'écran.
    static func overlay(_ dto: CashOutOverlayDTO,
                        reference: FinancialReference) -> CashOutTokenOverlay {
        CashOutTokenOverlay(
            reference: reference,
            conversationID: dto.conversationId,
            channel: dto.channel.flatMap { cashOut([$0]).first },
            agentID: dto.agentId,
            tokenHash: dto.tokenHash,
            tokenExpiresAt: FinanceCoreDates.parse(dto.tokenExpiresAt),
            revoked: dto.revoked ?? false,
            consumedAt: FinanceCoreDates.parse(dto.consumedAt),
            remittedAt: FinanceCoreDates.parse(dto.remittedAt),
            incidentOpened: dto.incidentOpened ?? false)
    }

    /// Le code à renvoyer au serveur pour ce canal — celui qu'il a lui-même
    /// rendu dans `channels`.
    static func wire(_ channel: CashInChannel) -> String {
        switch channel {
        case .agent:       return "AGENT"
        case .bank:        return "BANK_BRANCH"
        case .card:        return "CARD"
        case .mobileMoney: return "MOBILE_MONEY"
        case .openBanking: return "OPEN_BANKING"
        }
    }

    static func wire(_ channel: CashOutChannel) -> String {
        switch channel {
        case .agent:    return "AGENT"
        case .atm:      return "ATM"
        case .bank:     return "BANK_BRANCH"
        case .merchant: return "MERCHANT"
        }
    }

    /// `MOBILE_MONEY`, `mobile-money` et `mobileMoney` désignent le même canal.
    private static func normalized(_ code: String) -> String {
        code.uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
