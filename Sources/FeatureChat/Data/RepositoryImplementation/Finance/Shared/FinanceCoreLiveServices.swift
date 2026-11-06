//
//  FinanceCoreLiveServices.swift
//  FeatureChat
//
//  Les contrats financiers servis par Chat Core réel — Phase 1.
//

import Foundation
import WaanguCoreKit

/// Point d'entrée **public** des implémentations Chat Core.
///
/// L'AppTarget construit une instance quand `FinanceBackend.mode == .live` et
/// branche ses propriétés à la place des doublures. Chaque propriété est typée
/// par un contrat CoreKit existant : les écrans ne voient aucune différence.
///
/// Les phases suivantes ajoutent ici leurs services (envoi, facture, …).
public final class FinanceCoreLiveServices: Sendable {

    public let catalog: any ChatFinanceCatalogProviding
    public let capabilityGates: any FinancialCapabilityGateProviding
    public let killSwitch: any OperationalKillSwitchProviding
    public let session: any FinanceSessionProviding
    /// Phase 2 — carte FCO (`GET /objects/{ref}`) et requery en cas de doute.
    public let apiClient: any FinanceAPIClientProtocol
    /// Phase 2 — n'accepte comme succès que ce que Chat Core déclare final.
    public let confirmationGuard: any PaymentConfirmationGuardProtocol
    /// Phase 3 — `send-money/resolve-beneficiary`.
    public let recipientResolver: any RecipientResolving
    /// Phase 3 — `send-money/prepare`, devis gardé jusqu'à l'execute.
    public let transferQuoting: any TransferQuoting
    /// Phase 10 — rembourser (un devis) ou demander l'extourne.
    public let reversals: any OperationReversing
    /// Phase 3 — le permis rendu par le prepare.
    public let executionPermits: any ExecutionPermitIssuing
    /// Phase 4 — `request-money` (création, relance).
    public let moneyRequests: any MoneyRequestCreating
    /// Phase 4 — répondre à une demande : lire sa part, payer (un devis),
    /// refuser, relancer.
    public let moneyRequestResponder: any MoneyRequestResponding
    /// Phase 5.1 — Pay Bill. Pour l'instant : le catalogue, lu et journalisé.
    public let bills: any BillPaying
    /// Phase 5.2 — lire un QR. Pour l'instant : l'appel, journalisé.
    public let qrResolver: any QRResolving
    /// Phase 5.3 — recharge : catalogue, numéro résolu par le serveur, devis.
    public let topUp: any TopUpOrdering
    /// §4 — partage d'addition. Les trois routes du contrat, et rien d'autre.
    public let splitBills: any SplitBillManaging
    /// §6 — espèces. Pour l'instant : les canaux ouverts sur ce marché.
    public let cashIn: any CashInInitiating
    public let cashOut: any CashOutIssuing
    /// Phase 10 — reçus signés par Finance, litiges en fil support isolé.
    public let receipts: any ReceiptAccessProviding
    public let disputes: any DisputeFiling
    /// §5.2 — facture marchande : reste dû, devis, confirmation.
    public let merchantInvoices: any InvoiceProviding
    /// Phase 8 — traduction d'un texte financier, valeurs protégées.
    public let translator: any FinancialTranslating
    /// Phase 5 — socle prepare/execute des opérations quotées. Interne : les
    /// corps de prepare de chaque opération ne sont pas encore publiés.
    let quotedOperations: LiveQuotedOperations

    private let repository: FinanceCoreSessionRepository

    /// - Parameters:
    ///   - apiClient: client HTTP de l'hôte du chat (`chatUrl`).
    ///   - deviceID: identifiant d'appareil — celui du JWT, pour la reprise de session.
    ///   - networkMonitor: économiseur de données, dit au serveur à l'amorçage (§1.1).
    ///   - reducedMotionPreferred: réglage d'accessibilité de l'appareil (§1.1).
    public convenience init(apiClient: any APIClientProtocol,
                            deviceID: @escaping @Sendable () -> String,
                            networkMonitor: (any NetworkMonitoringProtocol)? = nil,
                            reducedMotionPreferred: @escaping @Sendable () async -> Bool? = { nil }) {
        self.init(
            // L'amorçage lit la session : il ne peut pas l'oublier pendant qu'il la construit.
            sessionDataSource: HTTPChatFinanceDataSource(httpClient: apiClient),
            makeDataSource: { onSessionInvalid in
                HTTPChatFinanceDataSource(httpClient: apiClient, onSessionInvalid: onSessionInvalid)
            },
            deviceID: deviceID,
            networkMonitor: networkMonitor,
            reducedMotionPreferred: reducedMotionPreferred
        )
    }

    /// - Parameters:
    ///   - sessionDataSource: source de l'amorçage — sans invalidation de session.
    ///   - makeDataSource: source de tout le reste, qui oublie la session quand
    ///     le serveur la déclare périmée. Fabriquée ici parce que son rappel
    ///     vise le repository de session, construit juste avant.
    init(sessionDataSource: any RemoteChatFinanceDataSourceProtocol,
         makeDataSource: (@escaping @Sendable () async -> Void) -> any RemoteChatFinanceDataSourceProtocol,
         deviceID: @escaping @Sendable () -> String,
         networkMonitor: (any NetworkMonitoringProtocol)? = nil,
         reducedMotionPreferred: @escaping @Sendable () async -> Bool? = { nil }) {
        let repository = FinanceCoreSessionRepository(dataSource: sessionDataSource, deviceID: deviceID,
                                                      networkMonitor: networkMonitor,
                                                      reducedMotionPreferred: reducedMotionPreferred)
        let dataSource = makeDataSource({ await repository.invalidate() })
        let finality = FinanceCoreFinality()
        let prepared = PreparedIntentStore()
        let directory = FinanceCoreDirectory()
        let sendMoney = LiveSendMoney(dataSource: dataSource, prepared: prepared,
                                      session: repository, deviceID: deviceID, directory: directory)
        self.moneyRequests = LiveMoneyRequests(dataSource: dataSource, directory: directory, session: repository)
        // Une lecture de demande partagée entre la carte et le magasin.
        let requestReads = MoneyRequestReadCache()
        self.moneyRequestResponder = LiveMoneyRequestResponder(
            dataSource: dataSource, sendMoney: sendMoney,
            currentUserID: { CurrentSessionInfo.shared.currentUid },
            reads: requestReads)
        self.quotedOperations = LiveQuotedOperations(dataSource: dataSource, prepared: prepared,
                                                     session: repository)
        self.bills = LiveBillPaying(dataSource: dataSource, session: repository,
                                    quoting: quotedOperations, deviceID: deviceID)
        self.reversals = LiveOperationReversal(dataSource: dataSource, quoting: quotedOperations, deviceID: deviceID)
        self.qrResolver = LiveQRResolver(dataSource: dataSource, quoting: quotedOperations, deviceID: deviceID)
        self.topUp = LiveTopUp(dataSource: dataSource, session: repository,
                               quoting: quotedOperations, deviceID: deviceID)
        self.splitBills = LiveSplitBillManaging(dataSource: dataSource, sendMoney: sendMoney,
                                                deviceID: deviceID)
        self.cashIn = LiveCashIn(dataSource: dataSource, quoting: quotedOperations,
                                 deviceID: deviceID)
        self.cashOut = LiveCashOut(dataSource: dataSource, quoting: quotedOperations,
                                   deviceID: deviceID)
        self.receipts = LiveReceiptAccess(dataSource: dataSource)
        self.disputes = LiveDisputeFiling(dataSource: dataSource)
        self.translator = LiveFinancialTranslator(dataSource: dataSource)
        self.merchantInvoices = LiveInvoiceProvider(dataSource: dataSource, quoting: quotedOperations,
                                                    deviceID: deviceID)
        self.repository = repository
        self.recipientResolver = sendMoney
        self.transferQuoting = sendMoney
        self.executionPermits = sendMoney
        self.apiClient = LiveFinanceAPIClient(
            dataSource: dataSource, finality: finality,
            capabilitiesProvider: {
                guard case .success(let snapshot) = await repository.current() else { return FinanceCapabilities() }
                return FinanceGovernanceMapper.financeCapabilities(from: snapshot, context: .unknown)
            },
            prepared: prepared, deviceID: deviceID,
            sessionStatus: { await repository.status() },
            requestReads: requestReads
        )
        self.confirmationGuard = ChatCoreConfirmationGuard(finality: finality)
        self.catalog = LiveFinanceCatalog(repository: repository, dataSource: dataSource)
        self.capabilityGates = LiveCapabilityGates(repository: repository)
        self.killSwitch = LiveKillSwitch(repository: repository)
        self.session = LiveFinanceSession(repository: repository, prepared: prepared,
                                          directory: directory, finality: finality)
    }

    /// Capacités du Bloc 3, pour le résolveur de `FinanceCapabilityProvider`.
    ///
    /// Amorçage impossible ⇒ tout fermé : « une capacité non résolue est une
    /// capacité fermée ».
    public func capabilities(for context: FinanceCapabilityContext) async -> FinanceCapabilities {
        guard case .success(let snapshot) = await repository.current() else {
            return FinanceCapabilities(context: context)
        }
        return FinanceGovernanceMapper.financeCapabilities(from: snapshot, context: context)
    }
}

// MARK: - Implémentations

struct LiveFinanceCatalog: ChatFinanceCatalogProviding {
    let repository: FinanceCoreSessionRepository
    /// Brouillon et handoff (§2.2, §2.3) — hors amorçage, donc la source qui
    /// oublie la session quand le serveur la déclare périmée.
    let dataSource: any RemoteChatFinanceDataSourceProtocol

    func entries(for context: ChatFinanceContext) async -> [FinanceCatalogEntry] {
        // Hub injoignable ⇒ aucune tuile : le Hub est la vérité d'écran.
        (try? await load(for: context).get()) ?? []
    }

    func load(for context: ChatFinanceContext) async -> Result<[FinanceCatalogEntry], FinanceError> {
        let type = FinanceGovernanceMapper.conversationType(for: context.conversationKind)
        switch await repository.hubActions(conversationType: type) {
        case .success(let actions): return .success(FinanceGovernanceMapper.catalogEntries(from: actions))
        case .failure(let error):   return .failure(error.financeError)
        }
    }

    /// §5.1.1 — le dossier que portent les parcours ouverts hors conversation.
    func personalFolder() async -> PersonalFinanceFolder? {
        switch await repository.selfConversation() {
        case .success(let folder):
            return PersonalFinanceFolder(conversationID: folder.conversationId,
                                         membershipEpoch: folder.membershipEpoch,
                                         title: folder.title ?? "")
        case .failure(let error):
            // Sans dossier, facture, recharge et espèces n'ont rien qui porte
            // l'opération et s'arrêtent net. Dire lequel des deux a manqué —
            // la route ou la réponse — évite de relire tout le parcours.
            #if DEBUG
            print("[FinanceSelf] self-conversation unavailable: \(error)")
            #endif
            return nil
        }
    }

    func invalidate() async { await repository.invalidate() }

    // MARK: - §2.2 Brouillon

    /// Le texte lu par le Hub. Un brouillon que le serveur ne marque pas
    /// `draftOnly` n'est pas accepté : ce client ne traite jamais une lecture
    /// de texte comme une commande, même si on la lui présente ainsi.
    func draft(from text: String) async -> Result<FinanceTextDraft, FinanceError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.validation(field: "text")) }
        switch await FinanceCoreError.capture({ try await dataSource.parseIntent(ParseIntentRequest(text: trimmed)) }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let draft):
            guard draft.draftOnly == true else {
                return .failure(FinanceCoreErrorCode(rawValue: "CF_027").financeError)
            }
            return .success(Self.draft(from: draft))
        }
    }

    static func draft(from dto: IntentDraftDTO) -> FinanceTextDraft {
        let amount = dto.amountMinor.flatMap { minor in
            dto.currency.map { FcoCardMapper.amount(minor: minor, currency: $0) }
        }
        return FinanceTextDraft(
            kind: dto.actionCode.flatMap(FinanceGovernanceMapper.entryKind(forActionCode:)),
            amount: amount,
            currency: dto.currency,
            counterpartyHint: dto.counterpartyHint,
            message: dto.message)
    }

    // MARK: - §8 Waangu Copilot

    /// Seuls les outils qui **n'exécutent pas** sont retenus : actifs, et
    /// déclarés `executeForbidden: true` par le serveur. Un outil qui ne le
    /// déclare pas est écarté, pas « fait confiance » (§0.3.6).
    ///
    /// `mutating` n'est **pas** un critère : un PREPARE crée une intention côté
    /// serveur, et le Hub le marque donc `mutating: true` — c'est pourtant
    /// l'outil même du §8 (`send_money.prepare`, `executed=false`, handoff).
    func copilotTools() async -> Result<[FinanceCopilotTool], FinanceError> {
        switch await FinanceCoreError.capture({ try await dataSource.copilotTools() }) {
        case .failure(let error): return .failure(error.financeError)
        case .success(let tools): return .success(tools.compactMap(Self.tool(from:)))
        }
    }

    static func tool(from dto: CopilotToolDTO) -> FinanceCopilotTool? {
        let operation = (dto.operation ?? "").uppercased()
        guard dto.enabled != false, dto.executeForbidden == true,
              !operation.isEmpty, operation != "EXECUTE", operation != "CONFIRM" else { return nil }
        return FinanceCopilotTool(
            name: dto.name, version: dto.version, domain: dto.domain, operation: operation,
            kind: dto.handoffAction.flatMap(FinanceGovernanceMapper.entryKind(forActionCode:)),
            summary: dto.description)
    }

    /// Une réponse qui se dit exécutée viole le contrat : refusée, pas affichée.
    /// De même pour une réponse dont les attributs ne garantissent plus la
    /// préparation seule (`executeForbidden` ou `draftOnly` à `false`).
    func invokeCopilotTool(_ name: String) async -> Result<FinanceCopilotReply, FinanceError> {
        switch await FinanceCoreError.capture({
            try await dataSource.invokeCopilotTool(InvokeCopilotToolRequest(name: name))
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let result):
            guard Self.isPrepareOnly(result) else { return .failure(.forbidden) }
            return .success(FinanceCopilotReply(
                tool: result.tool ?? name, message: result.message,
                kind: result.handoffAction.flatMap(FinanceGovernanceMapper.entryKind(forActionCode:)),
                nextSafeActions: result.nextSafeActions ?? [],
                isAuthoritative: result.authoritative == true))
        }
    }

    /// Absent n'est pas un refus ; seul un `true`/`false` explicite contraire l'est.
    static func isPrepareOnly(_ result: CopilotToolResultDTO) -> Bool {
        result.executed != true
            && result.attributes?.executeForbidden != false
            && result.attributes?.draftOnly != false
    }

    // MARK: - §2.3 Handoff

    var providesHandoff: Bool { true }

    /// Émet puis consomme aussitôt : le jeton ne quitte pas ce client, et le
    /// contexte rendu est celui que le serveur a vérifié pour cet utilisateur.
    func handoff(conversationID: String,
                 actionCode: String) async -> Result<FinanceHandoffContext, FinanceError> {
        let issue = IssueHandoffRequest(conversationId: conversationID, actionCode: actionCode,
                                        financialIntentRef: nil)
        let ticket: HandoffTicketDTO
        switch await FinanceCoreError.capture({ try await dataSource.issueHandoff(issue) }) {
        case .failure(let error): return .failure(error.financeError)
        case .success(let value): ticket = value
        }
        switch await FinanceCoreError.capture({
            try await dataSource.consumeHandoff(ConsumeHandoffRequest(token: ticket.token))
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let payload):
            return .success(FinanceHandoffContext(
                conversationID: payload.conversationId, actionCode: payload.actionCode,
                financialIntentRef: payload.financialIntentRef, country: payload.country))
        }
    }
}

struct LiveCapabilityGates: FinancialCapabilityGateProviding {
    let repository: FinanceCoreSessionRepository

    func capabilities() async -> [FinancialCapability] {
        guard case .success(let snapshot) = await repository.current() else { return [] }
        return FinanceGovernanceMapper.capabilities(from: snapshot)
    }

    func invalidate() async { await repository.invalidate() }
}

struct LiveKillSwitch: OperationalKillSwitchProviding {
    let repository: FinanceCoreSessionRepository

    /// Contrat : « toute erreur donne tout suspendu ».
    func activeSuspensions() async -> KillSwitchState {
        guard case .success(let snapshot) = await repository.current() else { return .everything }
        return FinanceGovernanceMapper.killSwitch(from: snapshot)
    }
}

struct LiveFinanceSession: FinanceSessionProviding {
    let repository: FinanceCoreSessionRepository
    let prepared: PreparedIntentStore
    let directory: FinanceCoreDirectory
    let finality: FinanceCoreFinality

    func status() async -> Result<FinanceSessionStatus, FinanceError> {
        switch await repository.current() {
        case .success(let snapshot): return .success(FinanceGovernanceMapper.status(from: snapshot))
        case .failure(let error):    return .failure(error.financeError)
        }
    }

    /// Déconnexion, changement de compte : **tout** ce que Chat Core a appris
    /// pour le compte précédent disparaît — instantané, Hub, devis préparés,
    /// correspondances jeton → utilisateur, finalités. Un devis confirmable ou
    /// un jeton de bénéficiaire du compte A ne doit jamais servir au compte B.
    func invalidate() async {
        await repository.invalidate()
        await prepared.clear()
        await directory.clear()
        await finality.clear()
        // Un message rédigé pour le compte précédent ne s'affiche pas au suivant.
        FinanceErrorExplanations.shared.clear()
    }
}
