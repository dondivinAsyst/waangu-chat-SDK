//
//  WaanguChat.swift
//  WaanguChatSDK
//
//  The entry point for a host app (SDK plan, step 1.9, D-01 = b).
//
//  Everything below was written by hand in the Waangu app's dependency container, session
//  manager and coordinator. A host now gives its configuration, its database and its token
//  manager, and calls one method per event.
//

import Foundation
import UIKit
import WaanguCoreKit
import WaanguAuthKit
import WaanguDeviceKit
import WaanguNetworkKit
import WaanguStorageKit
import WaanguSecurityKit
import WaanguPermissionKit
import WaanguOpusKit
import WaanguCallMediaKit
import WaanguRealtimeTransportKit
import WaanguTranslationKit
import WaanguDomainKit
import WaanguFeatureChat

/// Chat for a host app: messaging and calls, and payments when the configuration turns them on.
///
/// ```swift
/// let database = await WaanguChat.makeDatabase(hostRegistrations: [MyAppTables.self])
/// let chat = WaanguChat(configuration: configuration, database: database, tokenManager: auth.tokenManager)
/// await chat.prepare()                      // once, at launch
/// await chat.startSession()                 // at launch if signed in, and after each sign-in
/// let coordinator = try await chat.makeCoordinator()   // then present ChatCoordinatorView
/// await chat.appDidEnterForeground()        // and appDidEnterBackground()
/// await chat.endSession()                   // on sign-out
/// ```
///
/// Chat signs the user in with the host's access token the first time its start screen appears,
/// so `startSession()` does not log in: it connects what is already signed in.
public final class WaanguChat: @unchecked Sendable {

    // MARK: - Inputs

    private let configuration: WaanguChatConfiguration
    private let database: any SearchableDatabaseProtocol
    private let tokenManager: any TokenManagerProtocol
    private let metricsSink: any ChatMetricsSink
    private let overridesProvider: () async throws -> ChatDependencyOverrides
    private let logger: AppLogger = .shared

    // MARK: - Built once

    private let chatTokenManager: any ChatTokenManagerProtocol
    private let keychain: any KeychainStoreProtocol
    private let networkMonitor: any NetworkMonitoringProtocol = NetworkMonitor.shared
    private let performanceMonitor: any PerformanceMonitorProtocol = PerformanceMonitor.shared
    private let deviceInfoProvider: any DeviceInfoProvidingProtocol = DeviceInfoProviding()
    private let appSettings: any AppSettingsProtocol
    private let preferenceStore: any PreferenceStoreProtocol

    private let realtimeClient: any RealtimeClientProtocol
    private let outbox: DatabaseOutbox<ChatOutboxItem>
    private let outboxAdapter: ChatOutboxAdapter
    private let lifecycle: ChatSessionLifecycle
    private let engine: FeatureSyncEngine<ChatSyncDelegate>

    private let lock = NSLock()
    private var hasPrepared = false
    private var registered = false

    // MARK: - Init

    /// - Parameters:
    ///   - database: the host's own store (D-15 a). Its migrations must include chat's:
    ///     build it with `makeDatabase(hostRegistrations:)`, or add
    ///     `ChatDatabaseRegistration.migrationSteps` to your own configuration.
    ///   - tokenManager: the host's login tokens. Chat sends them as `Authorization: Bearer`.
    ///   - metricsSink: receives the chat metrics (`conversation_open`, `send_to_ack`, ...).
    ///   - appSettings: the host's settings object, if it has one. Chat stores the signed-in
    ///     account in it. `nil` makes chat use the standard preference store.
    ///   - overrides: called when chat is first built; returns services to use instead of the ones
    ///     the facade chooses (see `ChatDependencyOverrides`). It is async because a host may need
    ///     to build clients. Most hosts pass nothing.
    public init(
        configuration: WaanguChatConfiguration,
        database: any SearchableDatabaseProtocol,
        tokenManager: any TokenManagerProtocol,
        metricsSink: any ChatMetricsSink = NoChatMetrics(),
        appSettings: (any AppSettingsProtocol)? = nil,
        overrides: @escaping () async throws -> ChatDependencyOverrides = { ChatDependencyOverrides() }
    ) {
        self.configuration = configuration
        self.database = database
        self.tokenManager = tokenManager
        self.metricsSink = metricsSink
        self.overridesProvider = overrides

        let keychain = KeychainStore(serviceName: configuration.keychainService)
        self.keychain = keychain
        let chatTokens = TokenManager(keychain: keychain, keys: .chat)
        self.chatTokenManager = chatTokens
        let preferences = PreferenceStore()
        self.preferenceStore = preferences
        self.appSettings = appSettings ?? AppSettings(store: preferences)

        let authBridge = RealtimeAuthBridge(tokenManager: chatTokens, eventBus: EventBus.shared)
        let deviceContext = deviceInfoProvider.captureDeviceContext()
        let deviceTier = DeviceTier(
            deviceInfoSnapshot: deviceInfoProvider.captureSnapshot(),
            logger: logger
        )
        let realtime = RealtimeAssembly.make(config: RealtimeConfiguration(
            transport: .mqtt,
            host: configuration.realtime.host,
            port: configuration.realtime.port,
            useTLS: configuration.realtime.useTLS,
            authDelegate: authBridge,
            deviceInfo: RealtimeDeviceInfo(
                deviceId: deviceContext.deviceId,
                platform: deviceContext.platformOS,
                appVersion: deviceContext.appVersion,
                deviceModel: deviceContext.deviceModel
            ),
            networkMonitor: networkMonitor,
            deviceTier: deviceTier,
            performanceMonitor: performanceMonitor,
            userId: nil,
            reconnectionPolicy: .standard,
            heartbeatInterval: 15,
            maxSubscriptions: 50,
            maxPayloadSize: 256 * 1024,
            defaultMessageTTL: 3600,
            offlineQueueConfig: .default,
            metricsDelegate: RealtimeMetricsCollector.shared,
            mqttSessionExpiryInterval: 3600,
            // 0 = inbound topic aliases disabled. CocoaMQTT does not resolve inbound aliases, so
            // allowing them makes the broker send empty topic names for aliased messages, which
            // are then dropped as "unsubscribed topic".
            mqttTopicAliasMaximum: 0
        ))
        self.realtimeClient = realtime

        let makeChatClient: @Sendable () async throws -> any APIClientProtocol = { [configuration, logger, performanceMonitor, networkMonitor, deviceInfoProvider, tokenManager] in
            try await APIClientFactoryProvider.makeClient(
                baseURL: configuration.chatBaseURL,
                doctorBaseURL: nil,
                appConfiguration: ChatAppConfiguration(configuration),
                logger: logger,
                performanceMonitor: performanceMonitor,
                networkMonitor: networkMonitor,
                deviceInfoProvider: deviceInfoProvider,
                tokenManager: tokenManager,
                basicAuthToken: configuration.basicAuthToken,
                certificatePins: WaanguPinProvider()
            )
        }
        self.makeChatClient = makeChatClient

        let outbox = DatabaseOutbox<ChatOutboxItem>(
            database: database,
            config: .default,
            flush: ChatOutboxFlush.makeHandler(apiClient: makeChatClient)
        )
        self.outbox = outbox
        let adapter = ChatOutboxAdapter(outbox: outbox)
        self.outboxAdapter = adapter

        let engine = FeatureSyncEngine(
            delegate: ChatSyncDelegate(
                fieldCrypto: FieldEncryptionService.shared,
                realtime: realtime,
                outbox: adapter,
                outboxMaintenance: adapter,
                metricsSink: metricsSink
            ),
            outbox: outbox,
            apiClient: LazyAPIClient(make: makeChatClient),
            database: database,
            realtime: realtime,
            syncPriority: .high,
            pullConfig: .default,
            currentOwner: { CurrentSessionInfo.shared.currentUid },
            // ChatFeature keeps its own live inbox subscription; a second one here would apply
            // every live event twice.
            liveUpdates: false
        )
        self.engine = engine
        self.lifecycle = ChatSessionLifecycle(
            realtime: realtime,
            sync: ChatSyncRunner(sync: engine),
            chatTokenManager: chatTokens
        )
    }

    private let makeChatClient: @Sendable () async throws -> any APIClientProtocol

    // MARK: - Parts a host may still need

    /// The realtime client chat uses. A host that disconnects realtime itself (for example at
    /// sign-out) must use this one, not build another.
    public var realtime: any RealtimeClientProtocol { realtimeClient }

    /// Chat's sync engine, for a host that runs its own sync coordinator over several features.
    public var syncEngine: any FeatureSyncProtocol { engine }

    /// Chat's own token store (the `.chat` keys), for a host that needs to know whether a chat
    /// session exists.
    public var chatTokens: any ChatTokenManagerProtocol { chatTokenManager }

    // MARK: - Database

    /// A SQLite store that holds chat's tables and the host's own.
    ///
    /// Migrations are fixed when a store is created, which is why chat cannot add its tables to a
    /// store that already exists: build the store here, or add chat's migrations yourself.
    public static func makeDatabase(
        hostRegistrations: [any DatabaseRegistrable.Type] = []
    ) async -> any SearchableDatabaseProtocol {
        // Chat's own registration is always first and only once: migrations with the same name
        // twice, or the same table registered twice, stop the app when the store is first used.
        let chat = ObjectIdentifier(ChatDatabaseRegistration.self)
        let registrations: [any DatabaseRegistrable.Type] = [ChatDatabaseRegistration.self]
            + hostRegistrations.filter { ObjectIdentifier($0) != chat }
        let store = DatabaseAssembly.makeSearchable(config: .init(
            engine: .sqlite,
            migrationSteps: registrations.flatMap { $0.migrationSteps }
        ))
        for registration in registrations {
            await DatabaseAssembly.register(registration, in: store)
        }
        ChatTablesRegistry.markRegistered(store)
        return store
    }

    // MARK: - Launch

    /// Once, at launch, before anything else: registers chat's tables and its realtime topics.
    public func prepare() async {
        let first: Bool = lock.withLock {
            defer { hasPrepared = true }
            return !hasPrepared
        }
        guard first else { return }
        await logger.log("WaanguChatSDK \(WaanguChatVersion.current)", level: .info)
        // A store from `makeDatabase` already has chat's tables registered; registering them
        // again stops the app when the store is first used.
        if ChatTablesRegistry.markRegistered(database) {
            await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: database)
        }
        await realtimeClient.register(ChatRealtimeRegistration.topicRegistrations)
    }

    /// The chat screens' coordinator. Present `ChatCoordinatorView(coordinator:)` with it. The
    /// first call builds chat; later calls return the same one until `endSession()`.
    @MainActor
    public func makeCoordinator() async throws -> ChatCoordinator {
        await registerFeature()
        let feature = try await FeatureRegistry.shared.feature(ChatFeature.self)
        return ChatCoordinator(feature: feature)
    }

    // MARK: - Session

    /// The user is signed in (at launch with a saved session, or just after signing in).
    public func startSession() async {
        await lifecycle.userDidSignIn()
    }

    public func appDidEnterForeground() async {
        await lifecycle.appDidEnterForeground()
    }

    public func appDidEnterBackground() async {
        await lifecycle.appDidEnterBackground()
    }

    /// The user signs out: stops the sync, then the realtime connection. Chat stays loaded. A host
    /// that must drop its `ChatCoordinator` before chat is unloaded calls this first, then
    /// `FeatureRegistry.shared.unload(ChatFeature.self)` itself, after the coordinator is gone.
    public func userDidSignOut() async {
        await lifecycle.userDidSignOut()
    }

    /// The user signs out, all at once: `userDidSignOut()`, then unloads chat so the next account
    /// does not inherit its state. Drop your `ChatCoordinator` first.
    public func endSession() async {
        await userDidSignOut()
        await FeatureRegistry.shared.unload(ChatFeature.self)
    }

    /// The user chose to sign out. This is the only call that clears the conversations kept on the
    /// device: chat announces a user-initiated logout (its subscribers purge the local data and the
    /// finance state), then `endSession()`. A session that expired or was revoked never comes
    /// through here, so it keeps the conversations. Drop your `ChatCoordinator` first.
    public func signOut() async {
        await EventBus.shared.publish(
            UserDidLogoutEvent(userId: CurrentSessionInfo.shared.currentUid, reason: .userInitiated)
        )
        await endSession()
    }

    // MARK: - Dependencies

    /// Tells the feature registry how to build chat, so it can be preloaded at launch. Safe to
    /// call more than once. `makeCoordinator()` calls it too.
    public func registerFeature() async {
        let first: Bool = lock.withLock {
            defer { registered = true }
            return !registered
        }
        guard first else { return }
        await FeatureRegistry.shared.registerDependencies(
            for: ChatFeature.self,
            priority: ChatFeature.loadPriority
        ) { [weak self] in
            guard let self else { throw WaanguCoreKit.AppError.cancelled }
            return try await self.makeChatDependencies()
        }
    }

    func makeChatDependencies() async throws -> ChatDependencies {
        // Call video rendering is main-actor work; it cannot travel inside `ChatDependencies`.
        // Without the calls module there is no call engine and nothing to render.
        let callsOn = configuration.modules.contains(.calls)
        if callsOn {
            await MainActor.run { CallVideoRendering.factory = MediasoupVideoRendererFactory() }
        }
        let callEngine: (any CallMediaEngineProtocol)? = callsOn ? MediasoupCallEngine() : nil

        let apiClient = try await makeChatClient()
        let uploadClient = try await APIClientFactoryProvider.makeClient(
            baseURL: configuration.chatUploadBaseURL,
            doctorBaseURL: nil,
            appConfiguration: ChatAppConfiguration(configuration),
            logger: logger,
            performanceMonitor: performanceMonitor,
            networkMonitor: networkMonitor,
            deviceInfoProvider: deviceInfoProvider,
            tokenManager: tokenManager,
            basicAuthToken: configuration.basicAuthToken,
            certificatePins: WaanguPinProvider()
        )
        let opusAudio = try await OpusAudioService(logger: logger)
        let opusPlayback = try await OpusPlaybackService(logger: logger)
        let permissions = await MainActor.run { PermissionCenter.shared }
        let signatureVerifier = HMACFinancialSignatureVerifier(keychain: keychain, logger: logger)
        let languageCode = appSettings.languageCode.rawValue
        let overrides = try await overridesProvider()
        let finance = configuration.modules.contains(.payments) ? makeLiveFinance(chatClient: apiClient) : nil
        // One typed local per value: the whole list inline is too much for the type checker.
        // A host override always wins; then the live Chat Core service (payments on); then closed.
        // With payments on, only what Chat Core declares final counts as confirmed.
        let paymentGuard: any PaymentConfirmationGuardProtocol = overrides.paymentConfirmationGuard
            ?? finance?.live.confirmationGuard
            ?? PaymentConfirmationGuard(logger: logger, verifier: signatureVerifier)
        var billFieldValidator: BillFieldValidating? = overrides.billFieldValidator
        if billFieldValidator == nil, finance != nil {
            billFieldValidator = { field, values in
                DynamicBillerFormLogic.issue(field: field, formated: values)
            }
        }
        let financeAPIClient: (any FinanceAPIClientProtocol)? = overrides.financeAPIClient ?? finance?.live.apiClient
        let financialObjectPersistence: (any FinancialObjectPersisting)? = overrides.financialObjectPersistence ?? finance?.persistence
        let financeSession: (any FinanceSessionProviding)? = overrides.financeSession ?? finance?.live.session
        let moneyRequestResponder: (any MoneyRequestResponding)? = overrides.moneyRequestResponder ?? finance?.live.moneyRequestResponder
        let financeBalanceOverride: (any GetBalanceUseCaseProtocol)? = overrides.financeBalanceOverride
        let financeCapabilities: any FinanceCapabilityProviding = overrides.financeCapabilities ?? finance?.capabilities ?? ClosedFinanceCapabilities()
        let idempotencyPreserver: any IdempotencyKeyPreserving = overrides.idempotencyPreserver ?? finance?.idempotency ?? ClosedIdempotencyKeyPreserver()
        let recipientResolver: any RecipientResolving = overrides.recipientResolver ?? finance?.live.recipientResolver ?? ClosedRecipientResolver()
        let executionPermits: any ExecutionPermitIssuing = overrides.executionPermits ?? finance?.live.executionPermits ?? ClosedExecutionPermitIssuer()
        let financeCatalog: any ChatFinanceCatalogProviding = overrides.financeCatalog ?? finance?.live.catalog ?? ClosedChatFinanceCatalog()
        let moneyRequests: any MoneyRequestCreating = overrides.moneyRequests ?? finance?.live.moneyRequests ?? ClosedMoneyRequestService()
        let transferQuoting: any TransferQuoting = overrides.transferQuoting ?? finance?.live.transferQuoting ?? ClosedTransferQuoting()
        let qrResolver: any QRResolving = overrides.qrResolver ?? finance?.live.qrResolver ?? ClosedQRResolver()
        let merchantInvoices: any InvoiceProviding = overrides.merchantInvoices ?? finance?.live.merchantInvoices ?? ClosedInvoiceProvider()
        let splitBills: any SplitBillManaging = overrides.splitBills ?? finance?.live.splitBills ?? ClosedSplitBillManager()
        let disputes: any DisputeFiling = overrides.disputes ?? finance?.live.disputes ?? ClosedDisputeFiling()
        let cashIn: any CashInInitiating = overrides.cashIn ?? finance?.live.cashIn ?? ClosedCashIn()
        let cashOut: any CashOutIssuing = overrides.cashOut ?? finance?.live.cashOut ?? ClosedCashOut()
        let bills: any BillPaying = overrides.bills ?? finance?.live.bills ?? ClosedBillPaying()
        let topUp: any TopUpOrdering = overrides.topUp ?? finance?.live.topUp ?? ClosedTopUp()
        let receipts: any ReceiptAccessProviding = overrides.receipts ?? finance?.live.receipts ?? ClosedReceiptAccess()
        let killSwitch: any OperationalKillSwitchProviding = overrides.killSwitch ?? finance?.live.killSwitch ?? ClosedKillSwitch()
        let capabilityGates: any FinancialCapabilityGateProviding = overrides.capabilityGates ?? finance?.live.capabilityGates ?? ClosedCapabilityGates()
        let stepUpAuthenticator: any StepUpAuthenticating = overrides.stepUpAuthenticator ?? finance?.stepUp ?? ClosedStepUpAuthenticator()
        let reversals: any OperationReversing = overrides.reversals ?? finance?.live.reversals ?? ClosedOperationReversing()
        let financialTranslator: any FinancialTranslating = overrides.financialTranslator ?? finance?.live.translator ?? ClosedFinancialTranslator()
        let qrPresenter: any QRPresenting = overrides.qrPresenter ?? ClosedQRPresenter()
        let merchantProfiles: any MerchantProfileProviding = overrides.merchantProfiles ?? ClosedMerchantProfileProvider()
        let commerce: any CommerceOrdering = overrides.commerce ?? ClosedCommerceOrdering()
        let remoteForms: any RemoteFormProviding = overrides.remoteForms ?? ClosedRemoteFormProvider()
        let support: any SupportCaseOpening = overrides.support ?? ClosedSupportCaseOpener()
        let paymentLinks: any PaymentLinkResolving = overrides.paymentLinks ?? ClosedPaymentLinkResolver()
        let cards: any CardManaging = overrides.cards ?? ClosedCardManager()
        let cardTransactions: any CardTransactionProviding = overrides.cardTransactions ?? ClosedCardTransactionProvider()
        let proximityPayments: any ProximityPaymentSessioning = overrides.proximityPayments ?? ClosedProximityPaymentSessioning()
        let campaigns: any CampaignManaging = overrides.campaigns ?? ClosedCampaignManager()
        let nativeApps: any NativeAppObjectProviding = overrides.nativeApps ?? ClosedNativeAppObjectProvider()
        let reconciliation: any ReconciliationProviding = overrides.reconciliation ?? ClosedReconciliationProvider()
        let transactionHistory: any TransactionHistoryProviding = overrides.transactionHistory ?? ClosedTransactionHistory()
        let fundingSources: any FundingSourceProviding = overrides.fundingSources ?? ClosedFundingSources()
        let mandates: any MandateManaging = overrides.mandates ?? ClosedMandateManaging()
        let remittance: any RemittanceSending = overrides.remittance ?? ClosedRemittance()
        let fx: any FXConverting = overrides.fx ?? ClosedFX()
        let credit: any CreditLending = overrides.credit ?? ClosedCredit()
        let savings: any SavingsManaging = overrides.savings ?? ClosedSavings()
        let investment: any InvestmentTrading = overrides.investment ?? ClosedInvestment()
        let pfm: any PersonalFinanceProviding = overrides.pfm ?? ClosedPFM()
        let auditEmitter: any FinancialAuditEmitting = overrides.auditEmitter ?? UnavailableAuditEmitter()
        let tokenRotation: any RefreshTokenRotating = overrides.tokenRotation ?? UnavailableTokenRotation()
        let attestationVerifier: any DeviceAttestationVerifying = overrides.attestationVerifier ?? UnavailableAttestationVerifier()

        return ChatDependencies(
            apiClient: apiClient,
            uploadApiClient: uploadClient,
            logger: logger,
            networkMonitor: networkMonitor,
            eventBus: EventBus.shared,
            realtime: realtimeClient,
            chatOutbox: outboxAdapter,
            chatOutboxMaintenance: outboxAdapter,
            opusAudioService: opusAudio,
            opusPlaybackService: opusPlayback,
            permissionService: permissions,
            messageConfirmationGuard: MessageConfirmationGuard(logger: logger),
            paymentConfirmationGuard: paymentGuard,
            promptInjectionFilter: PromptInjectionFilter.shared,
            signedPushVerifier: SignedPushVerifier.shared,
            fieldEncryptionService: FieldEncryptionService.shared,
            pendingE2EEQueue: PendingE2EEQueue(),
            sharedFeatureUsecases: overrides.sharedFeatureUsecases ?? ClosedSharedFeatureUsecases(),
            tokenManager: tokenManager,
            database: database,
            searchableDatabase: database,
            deviceInfoProvider: deviceInfoProvider,
            deviceRevocation: DeviceRevocationGuard.shared,
            auditEmitter: auditEmitter,
            tokenRotation: tokenRotation,
            attestationVerifier: attestationVerifier,
            mainAPIBaseURL: configuration.mainAPIBaseURL,
            appId: configuration.appId,
            userId: configuration.userId,
            appSettings: appSettings,
            translationService: TranslationService(locale: languageCode),
            chatTokenManager: chatTokenManager,
            callMediaEngine: callEngine,
            financeAPIClient: financeAPIClient,
            financeCapabilities: financeCapabilities,
            idempotencyPreserver: idempotencyPreserver,
            recipientResolver: recipientResolver,
            executionPermits: executionPermits,
            financeCatalog: financeCatalog,
            moneyRequests: moneyRequests,
            transferQuoting: transferQuoting,
            qrResolver: qrResolver,
            qrPresenter: qrPresenter,
            merchantProfiles: merchantProfiles,
            commerce: commerce,
            remoteForms: remoteForms,
            support: support,
            merchantInvoices: merchantInvoices,
            paymentLinks: paymentLinks,
            cards: cards,
            cardTransactions: cardTransactions,
            splitBills: splitBills,
            proximityPayments: proximityPayments,
            campaigns: campaigns,
            nativeApps: nativeApps,
            reconciliation: reconciliation,
            disputes: disputes,
            cashIn: cashIn,
            cashOut: cashOut,
            bills: bills,
            billFieldValidator: billFieldValidator,
            topUp: topUp,
            receipts: receipts,
            transactionHistory: transactionHistory,
            fundingSources: fundingSources,
            financeBalanceOverride: financeBalanceOverride,
            mandates: mandates,
            killSwitch: killSwitch,
            financialObjectPersistence: financialObjectPersistence,
            capabilityGates: capabilityGates,
            financeSession: financeSession,
            remittance: remittance,
            fx: fx,
            credit: credit,
            savings: savings,
            investment: investment,
            pfm: pfm,
            stepUpAuthenticator: stepUpAuthenticator,
            moneyRequestResponder: moneyRequestResponder,
            reversals: reversals,
            financialTranslator: financialTranslator,
            metricsSink: metricsSink,
            enabledModules: configuration.modules
        )
    }

    // MARK: - Payments

    /// Everything payments need, built from the host's chat client. Services that have no live
    /// version yet (cards, mandates, remittance, FX, savings, ...) are left closed: nothing is
    /// simulated, so no screen shows an invented value.
    private struct LiveFinance {
        let live: FinanceCoreLiveServices
        let capabilities: FinanceCapabilityProvider
        let idempotency: SecurityKitIdempotencyPreserver
        let stepUp: StepUpAuthenticator
        let persistence: AccountScopedFinancialObjectPersistence
    }

    private func makeLiveFinance(chatClient: any APIClientProtocol) -> LiveFinance {
        let deviceContext = deviceInfoProvider.captureDeviceContext()
        let deviceID = deviceContext.deviceId
        let live = FinanceCoreLiveServices(
            apiClient: chatClient,
            deviceID: { deviceID },
            networkMonitor: networkMonitor,
            reducedMotionPreferred: { await MainActor.run { UIAccessibility.isReduceMotionEnabled } }
        )
        let appVersion = deviceContext.appVersion
        let capabilities = FinanceCapabilityProvider(
            logger: logger,
            contextProvider: {
                // country, tenant, user and risk fields stay unset until the capability contract
                // defines them; an unresolved context yields no capability.
                FinanceCapabilityContext(channel: "ios", appVersion: appVersion)
            },
            resolve: { context in await live.capabilities(for: context) }
        )
        // The account is read at each use, not captured: keys and saved operations of one
        // account must never be served to another on the same device.
        let account = CurrentAccountReader(store: preferenceStore)
        let idempotency = SecurityKitIdempotencyPreserver(
            keychain: keychain,
            logger: logger,
            currentUserID: { account.userID }
        )
        let stepUp = StepUpAuthenticator(
            deviceID: deviceID,
            logger: logger,
            defaultReason: { FinanceStrings.stepUpReasonDefault }
        )
        let persistence = AccountScopedFinancialObjectPersistence(
            database: database,
            currentAccountID: { account.userID }
        )
        return LiveFinance(live: live, capabilities: capabilities, idempotency: idempotency,
                           stepUp: stepUp, persistence: persistence)
    }
}

// MARK: - API client configuration

/// The API client factory keeps an `AppConfigurationProviding` but reads nothing from it today;
/// it is built from the host's values so a host does not have to provide one.
private struct ChatAppConfiguration: AppConfigurationProviding {
    let environment: AppEnvironment = .production
    let baseURL: String
    let basicAuthToken: String
    let chatUrl: String
    let chatUploadUrl: String
    let realtimeHost: String
    let realtimePort: UInt16
    let realtimeUsesTLS: Bool
    let insuranceUrl: String = ""
    let sentryDSN: String = ""

    init(_ configuration: WaanguChatConfiguration) {
        baseURL = configuration.mainAPIBaseURL
        basicAuthToken = configuration.basicAuthToken ?? ""
        chatUrl = configuration.chatBaseURL
        chatUploadUrl = configuration.chatUploadBaseURL
        realtimeHost = configuration.realtime.host
        realtimePort = configuration.realtime.port
        realtimeUsesTLS = configuration.realtime.useTLS
    }
}

// MARK: - Registered stores

/// Which stores already have chat's tables registered. Weak, so a store that goes away is
/// forgotten (a new store must not be mistaken for an old one).
private enum ChatTablesRegistry {
    private static let lock = NSLock()
    private static let stores = NSHashTable<AnyObject>.weakObjects()

    /// `true` when the store was not marked before, and is now.
    @discardableResult
    static func markRegistered(_ store: any SearchableDatabaseProtocol) -> Bool {
        let object = store as AnyObject
        return lock.withLock {
            if stores.contains(object) { return false }
            stores.add(object)
            return true
        }
    }
}
