//
//  ChatFeature.swift
//  FeatureChat
//
//  Created by Refactoring on 5/5/26.
//

import Foundation
import SwiftUI
import WaanguCoreKit
import Combine

/// Composition root for the Chat module
/// Builds the complete Domain + Data graph from injected dependencies

public final class ChatFeature: FeatureLoadable {
    
    public typealias Dependencies = ChatDependencies
    
    public nonisolated static var loadPriority: FeatureLoadPriority { .standard }
    
    // MARK: - Injected Dependencies
    private let dependencies: ChatDependencies

    /// The parts of chat the host turned on.
    public var enabledModules: Set<ChatModule> { dependencies.enabledModules }
    
    private var cancellables = Set<AnyCancellable>()
    private var presenceLifecycleTasks: [Task<Void, Never>] = []
    private var inboxRealtimeTasks: [Task<Void, Never>] = []
    /// One delta sync at a time after a live event was refused (N-02).
    private lazy var liveEventRecovery = LiveEventRecovery { [weak self] in
        guard let repository = self?.discussionRepository else { return }
        try? await repository.performFullSync(limit: 50)
        await repository.deduplicateConversationsIfNeeded()
    }
    /// Re-binds the call inbox when the session changes.
    private var callLifecycleTasks: [Task<Void, Never>] = []
    /// Garde la surface financière alignée sur la session et sur le réseau.
    private var financeLifecycleTasks: [Task<Void, Never>] = []
    private var inboxSubscriptionToken: (any RealtimeSubscriptionToken)?
    private let e2eeKeysSyncedKey = "com.waangu.e2ee.keysSynced"
    
    // MARK: - Event Bus
    private lazy var chatEventBus: ChatDomainEventBusProtocol = {
        return InMemoryEventBus()
    }()
    
    // MARK: - E2EE (Encryption)
    
    // PendingE2EEQueue - Use injected dependency instead of creating new instance
    public lazy var pendingE2EEQueue: any PendingE2EEQueueProtocol = {
        return dependencies.pendingE2EEQueue
    }()
    
    // Temporarily commented out due to missing E2EE dependencies
    /*
    private lazy var e2eeKeyStore: E2EEKeyStoreProtocol = {
        return E2EEKeyStore.shared
    }()
    
    private lazy var e2eeService: E2EEService = {
        return E2EEService(keyStore: e2eeKeyStore)
    }()
    
    public lazy var e2eeUseCases: E2EEUseCasesProtocol = {
        return E2EEUseCases(service: e2eeService, repository: e2eeRepository)
    }()
    
    private lazy var e2eeRepository: E2EERepositoryProtocol = {
        return E2EERepository(httpDataSource: e2eeHttpDataSource)
    }()
    */
    
    // Temporarily commented out due to missing E2EE dependencies
    /*
    private lazy var e2eeHttpDataSource: HTTPE2EEDataSourceProtocol = {
        return HTTPE2EEDataSource(apiClient: dependencies.apiClient)
    }()
    */
    
    // MARK: - Upload Client
    private lazy var uploadClient: UploadClient = {
        return UploadClient()
    }()
    
    // MARK: - Local Data Sources
    private lazy var localMessageDataSource: LocalMessageDataSourceProtocol = {
        MessageDataSourceFactory.create(
            store: dependencies.database,
            fieldEncryptionService: dependencies.fieldEncryptionService
        )
    }()
    
    private lazy var localDiscussionDataSource: LocalDiscussionDataSourceProtocol = {
        DiscussionDataSourceFactory.create(
            store: dependencies.database,
            fieldCrypto: dependencies.fieldEncryptionService
        )
    }()

    private lazy var localContactsDataSource: LocalContactsDataSourceProtocol = {
        ContactsDataSourceFactory.makeDataSource(
            store: dependencies.database,
            fieldEncryptionService: dependencies.fieldEncryptionService
        )
    }()
    
    private lazy var localContactSyncStateDataSource: LocalContactSyncStateDataSourceProtocol = {
        ContactSyncStateDataSourceFactory.create(store: dependencies.database)
    }()
    
    private lazy var localStatusDataSource: LocalStatusDataSourceProtocol = {
        StatusDataSourceFactory.create(
            store: dependencies.database,
            fieldCrypto: dependencies.fieldEncryptionService
        )
    }()
    
    private lazy var localChatActionsDataSource: LocalChatActionsDataSourceProtocol = {
        ChatActionsDataSourceFactory.shared.makeLocalDataSource(store: dependencies.database)
    }()
    
    // MARK: - MQTT Data Sources (stub — realtime not yet connected)
    // MQTTStatusDataSource is not implemented yet. StatusRepository handles live
    // updates via the event bus instead.
    
    // MARK: - Sync Infrastructure
    private lazy var syncCursorStore: SyncCursorStore = {
        return SyncCursorStore()
    }()
    
    // MARK: - Repositories
    private lazy var messagesRepository: MessagesRepositoryProtocol = {
        return MessageRepository(localDataSource: localMessageDataSource)
    }()
    
    public lazy var discussionRepository: DiscussionRepositoryProtocol = {
        let remoteConversationSyncDataSource: RemoteConversationSyncDataSourceProtocol = HTTPConversationSyncDataSource(apiClient: dependencies.apiClient)
        return DiscussionRepository(
            localDataSource: localDiscussionDataSource,
            remoteConversationSyncDataSource: remoteConversationSyncDataSource,
            database: dependencies.database,
            syncCursorStore: syncCursorStore,
            fieldCrypto: dependencies.fieldEncryptionService,
            chatActionsDataSource: localChatActionsDataSource,
            // Bloc 8 — §33 : le garde vient de l'AppTarget, seul module qui
            // voit `SecurityKit`.
            revocationGuard: dependencies.deviceRevocation,
            deviceInfoProvider: dependencies.deviceInfoProvider
        )
    }()
    
    public lazy var contactsRepository: ContactsRepositoryProtocol = {
        let httpDataSource: HTTPContactsDataSourceProtocol = HTTPContactsDataSource(apiClient: dependencies.apiClient)
        let mapper: ContactsMappersProtocol = ContactsMappers(fieldEncryptionService: dependencies.fieldEncryptionService)
        let contactManager: ContactsManagerProtocol = ContactsManager()
        return ContactsRepository(
            localDataSource: localContactsDataSource,
            httpDataSource: httpDataSource,
            mapper: mapper,
            ContactManager: contactManager,
            syncStateDataSource: localContactSyncStateDataSource
        )
    }()
    public lazy var authRepository: AuthRepositoryProtocol = {
        let httpDataSource: HTTPAuthDataSourceProtocol = HTTPAuthDataSource(
            apiClient: dependencies.apiClient,
            appId: dependencies.appId,
            logger: dependencies.logger
        )
        return AuthRepository(
            deviceInfoProvider: dependencies.deviceInfoProvider,
            httpDataSource: httpDataSource,
            chatTokenManager:dependencies.chatTokenManager
        )
    }()
    
    private lazy var fileUploadRepository: FileUploadRepository = {
        let httpDataSource: HTTPFileUploadDataSource = HTTPFileUploadDataSource(apiClient: dependencies.apiClient)
        return FileUploadRepository(
            httpDataSource: httpDataSource,
            uploadClient: uploadClient,
            mapper: FileUploadMapper()
        )
    }()
    
    private lazy var statusRepository: StatusRepository = {
        let httpDataSource: HTTPStatusDataSource = HTTPStatusDataSource(apiClient: dependencies.apiClient)
        let mapper: StatusMappersProtocol = StatusMappers()
        return StatusRepository(
            localDataSource: localStatusDataSource,
            httpDataSource: httpDataSource,
            mapper: mapper,
            eventBus: chatEventBus,
            syncCursorStore: syncCursorStore,
            database: dependencies.database
        )
    }()
    
    // MARK: - Use Cases
    public lazy var authUseCases: AuthUseCasesProtocol = {
        let appSettings = dependencies.appSettings
        return AuthUseCases(repository: authRepository,appSettings: appSettings)
    }()
    
    public lazy var messagesUseCases: MessagesUseCasesProtocol = {
        return MessagesUseCases(repository: messagesRepository)
    }()
    
    public lazy var discussionUseCases: DiscussionUseCasesProtocol = {
        return DiscussionUseCases(repository: discussionRepository)
    }()

    private lazy var presenceRepository: PresenceRepositoryProtocol = {
        PresenceRepository(
            realtime: dependencies.realtime,
            database: dependencies.database
        )
    }()

    private lazy var chatSyncDelegate: ChatSyncDelegate = {
        // Le handler financier capture les cas d'usage, pas `self` : le délégué
        // de sync survit à la feature et retenir celle-ci créerait un cycle.
        let objects = financialObjectUseCases
        let logger = dependencies.logger
        let projection = GRDBFinancialMessageProjection(store: dependencies.database)
        return ChatSyncDelegate(
            fieldCrypto: dependencies.fieldEncryptionService,
            realtime: dependencies.realtime,
            outbox: dependencies.chatOutbox,
            outboxMaintenance: dependencies.chatOutboxMaintenance,
            onFinancialObjectChanged: { pointer in
                // Le pointeur ne dit pas la nature de l'objet : celle du message
                // qui le porte, s'il existe, choisit la bonne route de lecture.
                let reference = await projection.storedType(forObjectID: pointer.id).map {
                    FinancialReference(type: $0, id: pointer.id, version: pointer.version,
                                       correlationID: pointer.correlationID)
                } ?? pointer
                // Le backend envoie chaque changement deux fois — sans révision,
                // puis avec. La seconde arrive après la relecture déclenchée par
                // la première : le magasin tient déjà cette révision, la relire
                // ne rapprendrait rien. La révision du pointeur ne sert qu'à ça.
                if ChatFeature.pointerIsAlreadyKnown(reference,
                                                     current: await objects.current(for: reference)) {
                    return
                }
                // Une notification ne porte aucun état : on relit auprès du
                // serveur, et le garde de version décide si la réponse s'applique.
                let result = await objects.refresh(reference)
                // L'acteur ne reçoit pas ce MQTT (§11) : ce chemin est celui de
                // la contrepartie.
                await ChatFeature.logCounterpartyReadRefusal(
                    result, reference: reference, trigger: "MQTT object_changed", logger: logger)
            },
            onFinancialMessageReceived: { reference in
                // Détaché : la lecture serveur ne doit pas retenir le traitement
                // des événements de sync qui suivent.
                Task {
                    // Pointeur arrivé avant le message : le magasin tient déjà
                    // l'état serveur, mais aucune bulle n'existait pour le
                    // recevoir. On le recopie tout de suite — le garde de
                    // version de la projection empêche tout recul.
                    if let known = await objects.current(for: reference) {
                        _ = try? await projection.project(known)
                    }
                    // Puis la lecture que le Bloc 1 §11.2 exige : c'est elle qui
                    // fait foi, pas l'état publié par l'expéditeur.
                    let result = await objects.refresh(reference)
                    await ChatFeature.logCounterpartyReadRefusal(
                        result, reference: reference, trigger: "ISMONEY message received", logger: logger)
                }
            },
            metricsSink: dependencies.metricsSink
        )
    }()

    /// `true` si le magasin tient déjà la révision que le pointeur annonce.
    ///
    /// Un pointeur **sans** révision (0) déclenche toujours une lecture : rien
    /// ne dit ce qu'il annonce. Avec une révision, une lecture n'apprendrait
    /// rien si le magasin l'a déjà — ou plus récente.
    static func pointerIsAlreadyKnown(_ pointer: FinancialReference,
                                      current: FinancialCardPayload?) -> Bool {
        guard pointer.version > 0, let current else { return false }
        return current.reference.version >= pointer.version
    }

    /// Refus de lecture d'un objet financier, marqué pour être retrouvé.
    ///
    /// La lecture part avec `reasonForAccess=SELF`, réservé au propriétaire
    /// (contrat, Phase 7). Côté contrepartie, un refus laisse la carte figée
    /// sur l'état publié dans le message.
    static func logCounterpartyReadRefusal(
        _ result: Result<FinancialCardPayload, FinanceError>,
        reference: FinancialReference,
        trigger: String,
        logger: any AppLoggerProtocol
    ) async {
        guard case .failure(let error) = result, isReadRefusal(error) else { return }
        let context = FinanceLogContext(reference: reference, operation: "counterparty_read")
        await logger.log(
            "[FinanceRead] COUNTERPARTY READ REFUSED — GET /financial/objects/{ref}"
            + "?reasonForAccess=SELF after \(trigger); card stays on its"
            + " published status. \(context) error=\(error.technicalDetail)",
            level: .warning
        )
    }

    /// Refus d'accès à la lecture d'un objet : un code métier rendu `.forbidden`
    /// (dont `CF_065`, raison d'accès invalide), ou un 401/403 HTTP sans enveloppe.
    static func isReadRefusal(_ error: FinanceError) -> Bool {
        switch error {
        case .forbidden, .unauthorized:        return true
        case .server(let status?):             return status == 401 || status == 403
        default:                               return false
        }
    }

    // MARK: - Finance conversationnelle (Bloc 1)
    //
    // Tâche 12.1. Ces composants étaient livrés et testés mais construits nulle
    // part : la surface financière compilait sans qu'aucun chemin d'exécution ne
    // l'atteigne. Ouvrir les drapeaux n'y aurait rien changé.

    /// État courant des objets financiers, avec garde de version.
    ///
    /// Un seul magasin pour toute la feature : c'est ce qui garantit qu'une
    /// révision reçue par MQTT et une révision lue par HTTP se comparent au même
    /// endroit. Deux magasins laisseraient chacun ignorer l'autre.
    public lazy var financialObjectStore: FinancialObjectStore = {
        FinancialObjectStore(
            persistence: dependencies.financialObjectPersistence,
            onStaleRejected: { [telemetry = financeTelemetry] reference, current in
                await telemetry.recordStaleRejected(
                    reference: reference,
                    currentVersion: current
                )
            }
        )
    }()

    public lazy var financeTelemetry: FinanceTelemetry = {
        FinanceTelemetry(
            analytics: NoopFinanceAnalytics(),
            logger: dependencies.logger
        )
    }()

    /// Faisceau financier remis aux vues de conversation — Bloc 3.
    ///
    /// Exposé pour que les vues le reçoivent sans connaître `ChatDependencies` :
    /// une vue ne doit voir que ce qu'elle utilise.
    public var financeSurface: ChatFinanceSurface {
        // Mémorisée, et **réémise dès que la session change**.
        //
        // Elle était recalculée à chaque lecture. Une vue qui la lit dans son
        // `body` — c'est le cas de la destination des Réglages — reconstruisait
        // donc quarante dépendances, allouait un `SendMoneyUseCase`, relisait
        // l'identifiant de session et rappelait `captureDeviceContext()` à
        // chaque réévaluation, soit plusieurs fois par ouverture d'écran. D'où
        // le temps d'ouverture des Paiements depuis les Réglages.
        //
        // La clé du cache est l'identifiant de session, ce qui préserve la
        // raison d'être de l'ancien calcul systématique : la session suivante
        // n'hérite pas de la surface de la précédente.
        let uid = CurrentSessionInfo.shared.currentUid
        if let cached = financeSurfaceCache, cached.uid == uid { return cached.surface }

        // Les libellés financiers passent par TranslationKit. Branché ici parce
        // que c'est le seul point traversé par toute la surface financière.
        FinanceLocalization.configure(dependencies.translationService)

        let surface = ChatFinanceSurface(
            catalog: dependencies.financeCatalog,
            recipientResolver: dependencies.recipientResolver,
            moneyRequests: dependencies.moneyRequests,
            transferQuoting: dependencies.transferQuoting,
            qrResolver: dependencies.qrResolver,
            qrPresenter: dependencies.qrPresenter,
            merchantProfiles: dependencies.merchantProfiles,
            commerce: dependencies.commerce,
            remoteForms: dependencies.remoteForms,
            support: dependencies.support,
            merchantInvoices: dependencies.merchantInvoices,
            paymentLinks: dependencies.paymentLinks,
            cards: dependencies.cards,
            cardTransactions: dependencies.cardTransactions,
            splitBills: dependencies.splitBills,
            proximityPayments: dependencies.proximityPayments,
            campaigns: dependencies.campaigns,
            nativeApps: dependencies.nativeApps,
            reconciliation: dependencies.reconciliation,
            // Identifiant de la session en cours — c'est aussi la clé du
            // cache ci-dessus, donc un changement de session reconstruit la
            // surface au lieu d'en resservir une qui porterait l'ancien.
            currentUserID: uid,
            cashIn: dependencies.cashIn,
            cashOut: dependencies.cashOut,
            bills: dependencies.bills,
            billFieldValidator: dependencies.billFieldValidator,
            topUp: dependencies.topUp,
            disputes: dependencies.disputes,
            receipts: dependencies.receipts,
            transactionHistory: dependencies.transactionHistory,
            balance: dependencies.financeBalanceOverride
                ?? dependencies.sharedFeatureUsecases.getBalance,
            fundingSources: dependencies.fundingSources,
            operationKeys: FinanceOperationKeys(preserver: dependencies.idempotencyPreserver),
            objectReader: financialObjectUseCases,
            mandates: dependencies.mandates,
            killSwitch: dependencies.killSwitch,
            stepUp: dependencies.stepUpAuthenticator,
            capabilityGates: dependencies.capabilityGates,
            financeSession: dependencies.financeSession,
            remittance: dependencies.remittance,
            fx: dependencies.fx,
            credit: dependencies.credit,
            savings: dependencies.savings,
            investment: dependencies.investment,
            pfm: dependencies.pfm,
            translator: dependencies.financialTranslator,
            promptFilter: dependencies.promptInjectionFilter,
            sendMoney: SendMoneyUseCase(
                quoting: dependencies.transferQuoting,
                permits: dependencies.executionPermits,
                client: dependencies.financeAPIClient,
                preserver: dependencies.idempotencyPreserver,
                logger: dependencies.logger,
                audit: dependencies.auditEmitter
            ),
            splitSharing: ShareSplitBillUseCase(
                contacts: contactUseCases,
                discussions: discussionUseCases,
                publisher: publishFinanceMessage,
                currentUserId: { CurrentSessionInfo.shared.currentUid }
            ),
            deviceID: dependencies.deviceInfoProvider.captureDeviceContext().deviceId,
            requestResponder: dependencies.moneyRequestResponder,
            pinVerifier: Self.pinVerifier,
            reversals: dependencies.reversals
        )
        financeSurfaceCache = (uid, surface)
        return surface
    }

    /// Le PIN du portefeuille, repli de Face ID. **Provisoire :** en Debug, tout
    /// PIN est accepté en attendant la route serveur ; en Release, tout est refusé.
    private static var pinVerifier: any StepUpPINVerifying {
        #if DEBUG
        DevelopmentPINVerifier()
        #else
        UnavailableStepUpPINVerifier()
        #endif
    }

    /// Surface financière mémorisée, avec la session à laquelle elle appartient.
    private var financeSurfaceCache: (uid: String, surface: ChatFinanceSurface)?

    /// Lecture, application et réconciliation des objets financiers.
    public lazy var financialObjectUseCases: any FinancialObjectUseCasesProtocol = {
        FinancialObjectUseCases(
            store: financialObjectStore,
            client: dependencies.financeAPIClient,
            guardian: dependencies.paymentConfirmationGuard,
            capabilities: dependencies.financeCapabilities,
            logger: dependencies.logger
        )
    }()

    /// Émission d'un paiement depuis une conversation.
    public lazy var paymentIntentUseCases: any PaymentIntentUseCasesProtocol = {
        PaymentIntentUseCases(
            client: dependencies.financeAPIClient,
            capabilities: dependencies.financeCapabilities,
            preserver: dependencies.idempotencyPreserver,
            // Le risque de session n'a pas de conformeur injecté : `nil` laisse
            // le plancher backend s'appliquer seul, jamais un défaut permissif.
            riskEvaluator: nil,
            store: financialObjectStore,
            deviceID: dependencies.deviceInfoProvider.captureDeviceContext().deviceId,
            logger: dependencies.logger
        )
    }()

    /// Réponses sans effet monétaire à une demande d'argent.
    public lazy var moneyRequestUseCases: any MoneyRequestUseCasesProtocol = {
        MoneyRequestUseCases(
            client: dependencies.financeAPIClient,
            capabilities: dependencies.financeCapabilities,
            objects: financialObjectUseCases,
            logger: dependencies.logger
        )
    }()

    /// Décide quand reprendre les objets dont l'issue est ambiguë.
    public lazy var financialReconciliationScheduler: FinancialReconciliationScheduler = {
        FinancialReconciliationScheduler(
            useCases: financialObjectUseCases,
            logger: dependencies.logger
        )
    }()

    /// File des actions financières différables. Distincte de l'outbox du chat :
    /// celle-ci republie jusqu'à acquittement, ce qui est correct pour un message
    /// et dangereux pour un paiement.
    public lazy var financeOutbox: ChatFinanceOutbox = {
        ChatFinanceOutbox(
            preserver: dependencies.idempotencyPreserver,
            logger: dependencies.logger,
            // Lot 2.3 — la file survit au kill, rangée par compte.
            storage: GRDBFinanceOutboxStore(store: dependencies.database),
            currentAccountID: {
                let uid = CurrentSessionInfo.shared.currentUid
                return uid.isEmpty ? nil : uid
            }
        )
    }()

    /// Envoie les actions différées — au retour du réseau et à la connexion.
    ///
    /// Seule `cancelOwnRequest` peut être en file (`FinanceOfflinePolicy`) ;
    /// les autres cas ne sont jamais enfilés ni restaurés, et une réponse
    /// `false` les garderait intacts plutôt que de les exécuter ici.
    private func flushFinanceOutbox() async {
        let requests = dependencies.moneyRequests
        let objects = financialObjectUseCases
        await financeOutbox.flush { item in
            switch item.action {
            case .cancelOwnRequest:
                guard case .success = await requests.revoke(item.reference, idempotency: item.idempotency) else {
                    return false
                }
                // La carte de la demande passe à « annulée » par la seule
                // lecture serveur, jamais par une écriture locale.
                _ = await objects.refresh(item.reference)
                return true
            default:
                return false
            }
        }
    }

    lazy var conversationRoomUseCases: ConversationRoomUseCasesProtocol = {
        ConversationRoomUseCases(
            messagesRepository: messagesRepository,
            discussionRepository: discussionRepository,
            presenceRepository: presenceRepository,
            outbox: dependencies.chatOutbox,
            outboxInspector: chatOutboxInspector,
            realtime: dependencies.realtime,
            metricsSink: dependencies.metricsSink
        )
    }()

    /// La conversation Waangu Copilot, sur l'appareil — celle que la liste des
    /// discussions montre et que les boutons flottants ouvrent.
    lazy var copilotConversationStore: any CopilotConversationStoring = GRDBCopilotConversationStore(
        store: dependencies.database,
        fieldCrypto: dependencies.fieldEncryptionService
    )

    /// Annonce d'une opération financière dans un fil, depuis un fil ouvert ou
    /// depuis les Réglages.
    ///
    /// Une seule instance : c'est elle qui fait partager un envoi à deux
    /// demandes simultanées pour la même référence.
    public lazy var publishFinanceMessage: any PublishFinanceMessageUseCaseProtocol = {
        PublishFinanceMessageUseCase(
            discussions: discussionUseCases,
            messages: messagesUseCases,
            publishOutgoing: conversationRoomUseCases.publishOutgoingMessage,
            objects: financialObjectUseCases,
            currentUserId: { CurrentSessionInfo.shared.currentUid }
        )
    }()

    /// Read-only view of the outbound queues, for the realtime monitor screen.
    private lazy var chatOutboxInspector: any ChatOutboxInspecting = {
        ChatOutboxInspector(
            database: dependencies.database,
            realtime: dependencies.realtime
        )
    }()

    @MainActor
    func makeChatRoomMessagesStore() -> ChatRoomMessagesStore {
        ChatRoomMessagesStore()
    }
    
    public lazy var contactUseCases: ContactsUseCasesProtocol = {
        return ContactsUseCases(repository: contactsRepository)
    }()
    
    public lazy var shareContentProcessor: ShareContentProcessorProtocol = {
        return ShareContentProcessor(contactsUseCases: contactUseCases)
    }()
    
    public lazy var fileUplaodUseCases: FileUplaodUseCasesProtocol = {
        return FileUplaodUseCases(repository: fileUploadRepository)
    }()

    lazy var userProfileRepository: UserProfileRepositoryProtocol = {
        let httpDataSource = HTTPUserProfileDataSource(apiClient: dependencies.apiClient)
        return UserProfileRepository(remoteDataSource: httpDataSource)
    }()

    public lazy var userProfileUseCases: UserProfileUseCasesProtocol = {
        return UserProfileUseCases(
            repository: userProfileRepository,
            uploadProfileImage: fileUplaodUseCases.uploadProfileImageUseCase
        )
    }()

    public lazy var statusUseCases: StatusUseCases = {
        return StatusUseCases(
            repository: statusRepository,
            uploadFileUseCase: fileUplaodUseCases.uploadFileUseCase,
            outbox: dependencies.chatOutbox,
            realtime: dependencies.realtime
        )
    }()
    
    public lazy var chatActionsUseCase: ChatActionsUseCaseProtocol = {
        ChatActionsDataSourceFactory.shared.makeChatActionsUseCase(
            store: dependencies.database
        )
    }()
    
    public lazy var groupUseCases: GroupUseCasesProtocol = {
        return GroupUseCases(
            repository: groupRepository,
            discussionRepository: discussionRepository
        )
    }()

    lazy var callSignalingRepository: CallSignalingRepositoryProtocol = {
        CallSignalingRepository(
            realtime: dependencies.realtime,
            deviceInfoProvider: dependencies.deviceInfoProvider
        )
    }()

    public lazy var callUseCases: CallUseCasesProtocol = {
        let localDataSource = CallDataSourceFactory.makeDataSource(
            store: dependencies.database
        )
        let remoteSyncDataSource = HTTPCallSyncDataSource(apiClient: dependencies.apiClient)
        return CallUseCases(
            repository: CallRepository(
                localDataSource: localDataSource,
                remoteSyncDataSource: remoteSyncDataSource,
                syncCursorStore: syncCursorStore,
                database: dependencies.database
            )
        )
    }()

    public lazy var groupPermissionsUseCases: GroupPermissionsUseCasesProtocol = {
        let localDataSource = GRDBGroupPermissionsDataSource(store: dependencies.database)
        let remoteDataSource = HTTPGroupPermissionsDataSource(httpClient: dependencies.apiClient)
        let repository = GroupPermissionsRepository(
            localDataSource: localDataSource,
            remoteDataSource: remoteDataSource
        )
        return GroupPermissionsUseCases(repository: repository)
    }()
    
    // MARK: - Communities & channels
    //
    // Identity owns the structure; the conversations these hang off are the same
    // ones the inbox already syncs. No local table on purpose — see
    // `CommunityRepository`.

    public lazy var communityUseCases: CommunityUseCasesProtocol = {
        CommunityUseCases(repository: communityRepository)
    }()

    /// Views per broadcast post, counted from read receipts.
    lazy var channelPostViews: any ChannelPostViewCounting = {
        GRDBChannelPostViewsDataSource(store: dependencies.database)
    }()

    public lazy var channelUseCases: ChannelUseCasesProtocol = {
        ChannelUseCases(repository: channelRepository)
    }()

    /// Whether the room being opened is one this user may write in.
    ///
    /// Shared by every room: the answer is only interesting for a broadcast
    /// channel or a community's announcements group, and it is nil for
    /// everything else.
    public lazy var conversationWriteAccess: any ConversationWriteAccessResolving = {
        ConversationWriteAccessResolver(
            channelRepository: channelRepository,
            communityRepository: communityRepository,
            currentUserId: { CurrentSessionInfo.shared.currentUid }
        )
    }()

    private lazy var communityRepository: CommunityRepositoryProtocol = {
        CommunityRepository(
            remoteDataSource: HTTPCommunityDataSource(httpClient: dependencies.apiClient),
            logger: dependencies.logger
        )
    }()

    private lazy var channelRepository: ChannelRepositoryProtocol = {
        ChannelRepository(
            remoteDataSource: HTTPChannelDataSource(httpClient: dependencies.apiClient),
            database: dependencies.database,
            logger: dependencies.logger
        )
    }()

    private lazy var groupRepository: GroupRepositoryProtocol = {
        let localDataSource = GroupDataSourceFactory.makeDataSource(
            store: dependencies.database,
            fieldCrypto: dependencies.fieldEncryptionService
        )
        let remoteDataSource: RemoteGroupDataSourceProtocol = HTTPGroupDataSource(httpClient: dependencies.apiClient)
        let joinRequestLocalDataSource = GroupJoinRequestDataSourceFactory.makeDataSource(
            store: dependencies.database
        )
        return GroupRepository(
            localDataSource: localDataSource,
            remoteDataSource: remoteDataSource,
            discussionRepository: discussionRepository,
            contactsRepository: contactsRepository,
            chatActionsUseCase: chatActionsUseCase,
            joinRequestLocalDataSource: joinRequestLocalDataSource
        )
    }()
    
    public lazy var currentUserUseCase: CurrentUserUseCaseProtocol = {
        return CurrentUserUseCase(appSettings: dependencies.appSettings)
    }()

    public lazy var currentSessionUseCase: CurrentSessionUseCaseProtocol = {
        return CurrentSessionUseCase(appSettings: dependencies.appSettings)
    }()
    
    // MARK: - Media Management
    public lazy var phMediaManager: PHMediaManagerProtocol = {
        return PHMediaManager()
    }()
    
    public lazy var phMediaManagerViewModel: PHMediaManagerViewModel = {
        return PHMediaManagerViewModel(mediaManager: phMediaManager)
    }()
    
    // MARK: - Upload & Audio
    @MainActor
    public lazy var uploadViewModel: FileUploadViewModel = {
        return FileUploadViewModel(fileUplaodUseCases: fileUplaodUseCases)
    }()
    
    public lazy var globalAudioManager: GlobalAudioPlaybackManager = {
        return GlobalAudioPlaybackManager.shared
    }()
    
    // MARK: - Shared View Models (Singleton instances)
    @MainActor
    public lazy var chatPartnerPickerViewModel: ChatPartnerPickerViewModel = {
        return ChatPartnerPickerViewModel(contactUseCases: contactUseCases)
    }()
    
    // MARK: - Init
    private init(dependencies: ChatDependencies) {
        self.dependencies = dependencies
    }
    
    public static func load(dependencies: ChatDependencies) async throws -> ChatFeature {
        let feature = ChatFeature(dependencies: dependencies)
        await feature.bootstrap()
        return feature
    }
    
    // MARK: - Bootstrap
    private func bootstrap() async {
        // Configure legacy adapters with AppSettings
        CurrentUser.shared.configure(appSettings: dependencies.appSettings)
        CurrentSessionInfo.shared.configure(appSettings: dependencies.appSettings)
        
        await syncRuntimeCredentials()
        registerE2EEKeysIfNeeded()
        presenceLifecycleTasks = ChatPresenceLifecycle.start(
            repository: presenceRepository,
            eventBus: dependencies.eventBus
        )
        startInboxRealtime()
        await configureVoip()
        startCallSessionLifecycle()
        await resumeLiveLocationShares()
        await startFinanceSurface()
        await scrubLegacyPlaintext()
    }

    /// F-13: clears the plaintext message copy (`searchText`) and encrypts the plaintext
    /// conversation preview (`lastMessageText`) and sender name (`lastMessageSenderName`)
    /// on rows saved before. Re-saving writes the new shape. Runs once per install; a
    /// failed save leaves the flag unset so the next launch retries. A value counts as
    /// plaintext when decrypting leaves it unchanged.
    /// Paged by `id`, which is unique: `timestamp` and `lastMessageAt` tie, and tied rows can
    /// swap places between pages and be skipped.
    nonisolated static func scrubLegacyPlaintext(
        database: any DatabaseRepositoryProtocol,
        crypto: any FieldEncryptionServiceProtocol,
        defaults: UserDefaults = .standard
    ) async {
        let key = legacyPlaintextScrubKey
        guard !defaults.bool(forKey: key) else { return }
        let batch = 500
        var offset = 0
        while true {
            let query = QuerySpec(
                sort: [SortSpec("id", ascending: true)],
                limit: batch,
                offset: offset
            )
            guard let rows = try? await database.fetch(MessageModel.self, query: query) else { return }
            for var row in rows where row.searchText != nil {
                row.searchText = nil
                do { try await database.save(row) } catch { return }
            }
            if rows.count < batch { break }
            offset += batch
        }
        offset = 0
        while true {
            let query = QuerySpec(
                sort: [SortSpec("id", ascending: true)],
                limit: batch,
                offset: offset
            )
            guard let rows = try? await database.fetch(ConversationModel.self, query: query) else { return }
            for var row in rows {
                var changed = false
                if let text = row.lastMessageText, !text.isEmpty, crypto.decrypt(text) == text {
                    row.lastMessageText = crypto.encrypt(text)
                    changed = true
                }
                if let name = row.lastMessageSenderName, !name.isEmpty, crypto.decrypt(name) == name {
                    row.lastMessageSenderName = crypto.encrypt(name)
                    changed = true
                }
                if changed {
                    do { try await database.save(row) } catch { return }
                }
            }
            if rows.count < batch { break }
            offset += batch
        }
        defaults.set(true, forKey: key)
    }

    static let legacyPlaintextScrubKey = "chat.legacyPlaintextScrubbed.v1"

    private func scrubLegacyPlaintext() async {
        await Self.scrubLegacyPlaintext(database: dependencies.database, crypto: dependencies.fieldEncryptionService)
    }

    /// Met la surface financière en service — tâche 12.1.
    ///
    /// Deux gestes, et le premier est indispensable même quand toutes les
    /// capacités sont fermées : sans enregistrement des rendus, un message
    /// `ISMONEY` déjà en base retomberait sur la carte générique. Le catalogue de
    /// capacités décide de ce que l'utilisateur peut *faire*, jamais de ce qu'il
    /// peut *voir* de ce qu'il a déjà reçu.
    private func startFinanceSurface() async {
        await MainActor.run { FinancialCardRegistry.registerBuiltInCards() }

        // Reprend les objets restés ambigus lors de la session précédente. Un
        // paiement laissé en `unknown` par un kill d'application ne se résout pas
        // tout seul : personne ne le rafraîchira si on ne le fait pas ici.
        await financialReconciliationScheduler.applicationDidBecomeActive()

        startFinanceLifecycle()
    }

    /// Branche les trois déclencheurs de réconciliation et la purge de session.
    ///
    /// Le planificateur exposait quatre points d'entrée dont un seul était
    /// appelé — le démarrage à froid. Les trois autres décrivaient un
    /// comportement qui n'existait pas : un objet ambigu ne se reprenait ni au
    /// retour du réseau, ni au retour au premier plan, ni au bout du délai de
    /// grâce, et l'état financier d'un compte survivait à sa déconnexion.
    private func startFinanceLifecycle() {
        financeLifecycleTasks.forEach { $0.cancel() }
        financeLifecycleTasks = [

            // 1. Retour du réseau — traité par `runReconnectLoop` (Bloc 8 §20, B64) :
            //    la réconciliation financière et l'envoi des actions différées
            //    font partie de la séquence ordonnée de reconnexion, après la
            //    vérification de session et la synchronisation, pas dans un
            //    observateur à part.

            // 2. Retour au premier plan.
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.dependencies.eventBus.subscribe(to: AppDidEnterForegroundEvent.self) {
                    await self.financialReconciliationScheduler.applicationDidBecomeActive()
                }
            },

            // 3. Passe périodique.
            //
            // C'est ce qui rend le délai de grâce observable : un objet basculé
            // en `unknown` alors que l'application est déjà au premier plan et
            // connectée n'a aucun autre déclencheur. Le planificateur écarte
            // lui-même les objets trop récents et ne journalise pas les passes
            // vides, donc un tick sans rien à faire ne coûte qu'une lecture.
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(Self.financeSweepInterval * 1_000_000_000))
                    guard !Task.isCancelled, let self else { break }
                    await self.financialReconciliationScheduler.periodicSweep()
                }
            },

            // 4. Fin de session.
            Task { [weak self] in
                guard let self else { return }
                for await event in self.dependencies.eventBus.subscribe(to: UserDidLogoutEvent.self) {
                    await Self.handleLogout(
                        event,
                        resetFinancialState: { userId in
                            await self.resetFinancialState(purgingKeysOf: userId,
                                                           erasingPersistedObjects: true)
                        },
                        purgeConversations: { await self.purgeConversations() }
                    )
                }
            },

            // 5. Ouverture de session.
            //
            // Un changement de compte ne passe pas toujours par un logout
            // observable — reconnexion sur un autre compte, session restaurée
            // au lancement. Purger aussi ici est la seule garantie que les
            // cartes affichées appartiennent à l'utilisateur courant.
            Task { [weak self] in
                guard let self else { return }
                for await event in self.dependencies.eventBus.subscribe(to: UserChatDidLoginEvent.self) {
                    await Self.handleChatLogin(
                        userId: event.userId,
                        environment: URL(string: self.dependencies.mainAPIBaseURL)?.host ?? "",
                        // Enregistré avant l'événement, à la connexion comme à la restauration.
                        tenant: self.dependencies.appSettings.currentUserTenantId ?? "",
                        purgeConversations: { await self.purgeConversations() },
                        restoreFinance: {
                            // La mémoire est purgée, **pas le disque** : cet événement
                            // part aussi à chaque lancement sur session restaurée, et la
                            // persistance — rangée par compte — porte les opérations
                            // qu'un kill a laissées en vol. L'effacer ici les perdait
                            // toutes avant que quiconque ait pu les reprendre.
                            await self.resetFinancialState(erasingPersistedObjects: false)
                            await self.financialObjectStore.hydrate()
                            await self.financialObjectUseCases.restoreHydrated()
                            // Lot 2.3 — actions différées du compte, reprises sous leur
                            // clé d'origine. Hors ligne, elles restent en file jusqu'au
                            // retour du réseau.
                            await self.financeOutbox.restore()
                            await self.flushFinanceOutbox()
                        }
                    )
                }
            },

            // 6. Projection dans la timeline — Bloc 1, lot 1.4.
            //
            // Chaque révision acceptée par le store est recopiée dans les
            // messages qui l'affichent ; la conversation, qui observe ces
            // lignes, redessine la bulle. Le flux du store n'est jamais clos
            // par une réinitialisation de session : un seul abonné suffit.
            Task { [weak self] in
                guard let self else { return }
                let projector = FinancialTimelineProjector(
                    store: self.financialObjectStore,
                    projection: GRDBFinancialMessageProjection(store: self.dependencies.database),
                    logger: self.dependencies.logger
                )
                await projector.run()
            }
        ]
    }

    /// Intervalle entre deux passes périodiques de réconciliation.
    ///
    /// Plus court que le délai de grâce du planificateur (120 s) pour qu'un objet
    /// devenu éligible soit repris dans la minute, sans jamais court-circuiter ce
    /// délai — c'est le planificateur qui décide, pas la cadence du réveil.
    private static let financeSweepInterval: TimeInterval = 60

    /// Oublie tout ce que le compte précédent a laissé derrière lui.
    ///
    /// Les trois gestes vont ensemble. Purger le magasin sans réinitialiser le
    /// planificateur laisserait son `lastRun` étouffer la première passe du
    /// compte suivant ; garder le catalogue de capacités laisserait le nouveau
    /// compte hériter des droits de l'ancien.
    ///
    /// - Parameter erasingPersistedObjects: `true` à la déconnexion seulement.
    private func resetFinancialState(purgingKeysOf userID: String? = nil,
                                     erasingPersistedObjects: Bool) async {
        if erasingPersistedObjects {
            await financialObjectUseCases.purge()
        } else {
            await financialObjectStore.clear(erasingPersistence: false)
        }
        await financialReconciliationScheduler.reset()
        await dependencies.financeCapabilities.invalidate()
        // Chat Core réel : instantané, Hub, devis préparés du compte précédent.
        await dependencies.financeSession?.invalidate()

        // Les actions différées du compte précédent ne sont pas rejouables par
        // le suivant : elles portent ses clés d'idempotence et ses bénéficiaires.
        // Les jeter est le seul comportement correct — les rejouer débiterait le
        // mauvais compte, les garder les rendrait rejouables plus tard.
        //
        // Lot 2.3 : la mémoire est toujours vidée ; le disque seulement à la
        // déconnexion, pour le compte qui part. À la connexion, le disque porte
        // les actions que `restore()` reprend — et il ne rend que celles du
        // compte courant.
        await financeOutbox.clear(erasingPersistenceOf: erasingPersistedObjects ? userID : nil)

        // Les clés d'idempotence vivent dans le trousseau, qui survit à la
        // déconnexion. Sans cette purge, l'identifiant d'opération du compte
        // suivant retrouve la clé du précédent — refus injustifié, ou rejeu.
        if let userID {
            await dependencies.idempotencyPreserver.purge(userID: userID)
        }
    }

    /// Picks up any live location share that was still running when the app was
    /// last killed.
    ///
    /// Their anchor bubbles are already in the feed saying live, and the ticks
    /// that moved them were never persisted — so without this the share would
    /// go on claiming to be live while nothing published a position.
    @MainActor
    private func resumeLiveLocationShares() async {
        let manager = LiveLocationSessionManager.shared
        manager.configure(
            publisher: conversationRoomUseCases.publishLiveLocation,
            sessionStore: LiveLocationSessionStore()
        )
        manager.resumeStoredShares()
    }

    /// Keeps the call inbox bound to the signed-in user.
    ///
    /// The topic is `waangu-chat/{userId}`, so a subscription made during
    /// bootstrap — before login has produced a user id — listens to the wrong
    /// topic for the rest of the run and no call event ever arrives. Chat's own
    /// inbox already re-attaches on these events; calls need the same.
    private func startCallSessionLifecycle() {
        callLifecycleTasks.forEach { $0.cancel() }
        callLifecycleTasks = [
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.dependencies.eventBus.subscribe(to: UserChatDidLoginEvent.self) {
                    await MainActor.run { VoipManager.shared.refreshSignalingSubscription() }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.dependencies.eventBus.subscribe(to: UserDidLogoutEvent.self) {
                    // Leave any room *before* the subscription is rebuilt, while
                    // the session is still valid enough to publish with.
                    await MainActor.run { VoipManager.shared.handleSignOut() }
                    await MainActor.run { VoipManager.shared.refreshSignalingSubscription() }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.dependencies.eventBus.subscribe(to: AppDidEnterForegroundEvent.self) {
                    // A background disconnect kills the subscription without
                    // ending the app, so returning has to re-attach it.
                    await MainActor.run { VoipManager.shared.refreshSignalingSubscription() }
                }
            }
        ]
    }

    /// Hands the call manager the use cases it needs to record call history.
    /// Without this every finished call is dropped on the floor.
    @MainActor
    private func configureVoip() {
        VoipManager.shared.callUseCases = callUseCases
        VoipManager.shared.contactUseCases = contactUseCases
        VoipManager.shared.discussionsUseCases = discussionUseCases
        VoipManager.shared.discussionRepository = discussionRepository
        VoipManager.shared.permissionService = dependencies.permissionService
        VoipManager.shared.configureSignaling(
            callSignalingRepository,
            deviceId: dependencies.deviceInfoProvider.captureDeviceContext().deviceId
        )
        if let engine = dependencies.callMediaEngine {
            VoipManager.shared.configureMedia(engine)
        }
    }

    /// Asks for mic + camera when Chat is opened, so call start does not race
    /// system permission sheets. Already-decided statuses return immediately.
    @MainActor
    public func primeCallCapturePermissions() async {
        let service = dependencies.permissionService
        _ = await service.request(.microphone)
        _ = await service.request(.camera)
    }

    /// Uses existing `ChatSyncDelegate.realtimeSubscription` — not SyncCoordinator.
    private func startInboxRealtime() {
        inboxRealtimeTasks.forEach { $0.cancel() }
        inboxRealtimeTasks = [
            Task { [weak self] in
                await self?.runInboxRealtimeLoop()
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.dependencies.eventBus.subscribe(to: UserChatDidLoginEvent.self) {
                    // Detach so the supervisor loop can subscribe with the new session.
                    await self.detachInboxRealtime()
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.dependencies.eventBus.subscribe(to: UserDidLogoutEvent.self) {
                    await self.detachInboxRealtime()
                    // A share must not outlive the account that started it —
                    // and the next user must not inherit one on resume.
                    await MainActor.run {
                        LiveLocationSessionManager.shared.stopAll()
                        LiveLocationStore.shared.clearAll()
                    }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.dependencies.eventBus.subscribe(to: AppDidEnterForegroundEvent.self) {
                    // Background disconnect cancels registry streams — bump detach so the
                    // supervisor re-subscribes after SessionManager reconnects.
                    await self.detachInboxRealtime()
                }
            },
            Task { [weak self] in
                await self?.runReconnectLoop()
            }
        ]
    }

    // MARK: - Outbox replay

    /// How long an action waits for its acknowledgement before a reconnect
    /// replays it. Long enough that a live publish settles on its own first.
    private static let outboxReplayGrace: TimeInterval = 30

    /// Runs the reconnect sequence each time the socket comes back.
    ///
    /// Only the transition into `connected` triggers it — the stream also
    /// reports authenticating and reconnecting, and replaying on each of those
    /// would send the same action several times per reconnect.
    private func runReconnectLoop() async {
        // The first connection after launch is a startup (outbox only); every
        // later transition into connected is a reconnection (the full sequence).
        var wasConnected = false
        var hasConnectedBefore = false
        for await state in dependencies.realtime.observeConnectionState() {
            guard !Task.isCancelled else { break }

            let isConnected = state.isConnected
            let trigger = ChatReconnectSequence.trigger(
                wasConnected: wasConnected,
                hasConnectedBefore: hasConnectedBefore,
                isConnected: isConnected
            )
            wasConnected = isConnected
            if isConnected { hasConnectedBefore = true }

            guard let trigger else { continue }
            let started = ContinuousClock.now
            if let report = await reconnectSequence.run(trigger) {
                let elapsed = ChatMetric.elapsedMs(since: started)
                for metric in report.metrics(trigger: trigger, durationMs: elapsed) {
                    dependencies.metricsSink.record(metric)
                }
            }
        }
    }

    /// Bloc 8 §20 — the reconnect work as one ordered routine (B64).
    private lazy var reconnectSequence = ChatReconnectSequence(
        steps: .init(
            needsReauthentication: { [weak self] in
                try await self?.currentSessionUseCase.shouldReauthenticate() ?? false
            },
            deltaSync: { [weak self] in
                guard let repository = self?.discussionRepository else { return }
                try await repository.performFullSync(limit: 50)
                // After the sync, not before: the server rows have to be here
                // before the local ones can be folded into them.
                await repository.deduplicateConversationsIfNeeded()
            },
            reconcileFinance: { [weak self] in
                await self?.financialReconciliationScheduler.networkDidBecomeAvailable()
            },
            drainFinanceOutbox: { [weak self] in
                // Lot 2.3 — deferred actions leave when the network is back.
                await self?.flushFinanceOutbox()
            },
            drainChatOutbox: { [weak self] in
                await self?.sweepUnacknowledgedOutbox()
            }
        ),
        log: { message in debugLog(message, category: "sync") }
    )

    private func sweepUnacknowledgedOutbox() async {
        let stale = await dependencies.chatOutboxMaintenance.pending(
            olderThan: Self.outboxReplayGrace
        )
        guard !stale.isEmpty else { return }

        #if DEBUG
        print("[Outbox] Reconnected — replaying \(stale.count) unacknowledged action(s)")
        #endif

        for item in stale {
            guard !Task.isCancelled else { break }
            do {
                try await ChatOutboxRepublisher.republish(item, realtime: dependencies.realtime)
                // A replay is an attempt, not a settlement — only the server's
                // acknowledgement clears the row. Counting it here is what stops
                // an action the server never answers from being replayed forever.
                await dependencies.chatOutboxMaintenance.noteAttempt(
                    id: item.id,
                    error: "Replayed, awaiting acknowledgement"
                )
            } catch {
                await dependencies.chatOutboxMaintenance.noteAttempt(
                    id: item.id,
                    error: error.localizedDescription
                )
            }
        }
    }

    /// Keeps the user inbox subscribed across disconnects and reconnects.
    private func runInboxRealtimeLoop() async {
        var backoffNanoseconds: UInt64 = 500_000_000
        while !Task.isCancelled {
            let userId = CurrentSessionInfo.shared.currentUid
            guard !userId.isEmpty else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            do {
                try await attachInboxRealtimeUntilStreamEnds()
                backoffNanoseconds = 500_000_000
            } catch {
                #if DEBUG
                print("[ChatFeature] Inbox realtime failed: \(error)")
                #endif
            }

            guard !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: backoffNanoseconds)
            backoffNanoseconds = min(backoffNanoseconds * 2, 8_000_000_000)
        }
    }

    private func attachInboxRealtimeUntilStreamEnds() async throws {
        await detachInboxRealtime()
        // Le compte est lu **avant** l'abonnement : le sujet MQTT est construit
        // depuis la session courante, donc le propriétaire du flux est celui-ci.
        let owner = CurrentSessionInfo.shared.currentUid
        guard let sync = try await chatSyncDelegate.realtimeSubscription(
            realtime: dependencies.realtime
        ) else {
            return
        }

        inboxSubscriptionToken = sync.token
        // Read here, on this one task, before any event can need it: the first access to
        // a lazy property from two event handlers at once could build two of them.
        let recovery = liveEventRecovery
        let metrics = dependencies.metricsSink
        // La boucle appelante se réabonne sous le compte courant (F-04).
        await Self.apply(sync.stream, ownedBy: owner,
                         currentUserId: { CurrentSessionInfo.shared.currentUid }) { [chatSyncDelegate, database = dependencies.database] event in
            // The session was revoked by Identity: end it, but keep the local conversations.
            if event.isSessionRevocation {
                await self.handleRemoteRevocation()
                return
            }
            // N-02: a live event whose write was refused is not stored and nothing else
            // will bring it back, so the same delta sync a reconnect runs fetches it again.
            await Self.applyLiveEvent(event, using: chatSyncDelegate, database: database) { reason in
                debugLog("live event refused (\(reason)) — delta sync scheduled", category: "sync")
                // Le motif peut citer des données : seule la source est mesurée.
                metrics.record(ChatMetric(name: ChatMetricName.syncFailure,
                                          attributes: ["source": "live_event"]))
                await recovery.schedule()
            }
        }
    }

    /// Applies one live event and reports a refused write instead of swallowing it.
    nonisolated static func applyLiveEvent(
        _ event: ChatSyncEventDTO,
        using delegate: ChatSyncDelegate,
        database: any DatabaseRepositoryProtocol,
        onRefused: (String) async -> Void
    ) async {
        if case .failed(let reason) = await delegate.applyEvent(event, database: database) {
            await onRefused(reason)
        }
    }


    /// Applique les événements d'un flux tant que le compte qui l'a ouvert est
    /// encore la session courante. Un événement livré après une déconnexion ou
    /// un changement de compte n'est pas appliqué, et le flux est abandonné.
    nonisolated static func apply(
        _ stream: AsyncStream<ChatSyncEventDTO>,
        ownedBy owner: String,
        currentUserId: () -> String,
        process: (ChatSyncEventDTO) async -> Void
    ) async {
        for await event in stream {
            guard currentUserId() == owner else { break }
            await process(event)
        }
    }

    private func detachInboxRealtime() async {
        await inboxSubscriptionToken?.cancel()
        inboxSubscriptionToken = nil
    }

    private func syncRuntimeCredentials() async {
        CurrentSessionInfo.shared.baseUrl = dependencies.mainAPIBaseURL
        if let token = try? await dependencies.tokenManager.getAccessToken() {
            CurrentSessionInfo.shared.token = token ?? ""
        }
    }
    

    
    // MARK: - E2EE Key Management
    private func registerE2EEKeysIfNeeded() {
        // Temporarily disabled due to missing E2EE dependencies
        /*
        let alreadySynced = UserDefaults.standard.bool(forKey: e2eeKeysSyncedKey)
        
        Task {
            do {
                _ = try await e2eeUseCases.generateKeyBundle.execute()
                await dependencies.logger.log("E2EE keys generated locally", level: .debug)
            } catch {
                await dependencies.logger.log("E2EE local key generation failed: \(error)", level: .error)
                return
            }
            
            guard !alreadySynced else {
                await dependencies.logger.log("E2EE keys already synced to server", level: .debug)
                return
            }
            
            await uploadE2EEKeysToServer()
        }
        */
    }
    
    private func uploadE2EEKeysToServer() async {
        // Temporarily disabled due to missing E2EE dependencies
        /*
        do {
            try await e2eeUseCases.uploadKeyBundle.execute()
            UserDefaults.standard.set(true, forKey: e2eeKeysSyncedKey)
            await dependencies.logger.log("E2EE key bundle uploaded to server", level: .info)
        } catch {
            await dependencies.logger.log("E2EE key upload failed: \(error)", level: .error)
        }
        */
    }
    
    // MARK: - View Model Factories
    
    @MainActor
    public func makeChatAuthInitViewModel() -> ChatAuthInitViewModel {
        return ChatAuthInitViewModel(
            authUseCases: authUseCases,
            currentSessionUseCase: currentSessionUseCase,
            eventBus: dependencies.eventBus,
            discussionRepository: discussionRepository
        )
    }
    
    // Cached view models to prevent recreation
    @MainActor
    private lazy var _storiesViewModel: StoriesViewModel = {
        return StoriesViewModel(
            statusUseCases: statusUseCases,
            phMediaManager: phMediaManager,
            conversationRoomUseCases: conversationRoomUseCases,
            discussionUseCases: discussionUseCases,
            contactsUseCases: contactUseCases
        )
    }()
    
    @MainActor
    public func makeStoriesViewModel() -> StoriesViewModel {
        return _storiesViewModel
    }
    
    @MainActor
    private lazy var _channelTabViewModel: ChannelTabViewModel = {
        ChannelTabViewModel(
            discussionsUseCases: discussionUseCases,
            groupUseCases: groupUseCases,
            translationService: dependencies.translationService,
            fileUploadUseCases: fileUplaodUseCases
        )
    }()

    @MainActor
    public func makeChannelTabViewModel() -> ChannelTabViewModel {
        _channelTabViewModel
    }
    
    @MainActor
    private lazy var _communitiesViewModel: CommunitiesViewModel = {
        CommunitiesViewModel(
            useCases: communityUseCases,
            discussionUseCases: discussionUseCases,
            uploadAvatar: userProfileUseCases.uploadProfilePhoto,
            translationService: dependencies.translationService
        )
    }()

    /// One view model for the tab, so the list survives a push and a pop.
    @MainActor
    public func makeCommunitiesViewModel() -> CommunitiesViewModel {
        _communitiesViewModel
    }

    /// A fresh one per community: it holds one community's groups and members,
    /// and reusing it across two different ids would show the wrong one first.
    @MainActor
    public func makeCommunityDetailViewModel(communityId: String) -> CommunityDetailViewModel {
        CommunityDetailViewModel(
            communityId: communityId,
            useCases: communityUseCases,
            discussionUseCases: discussionUseCases,
            groupUseCases: groupUseCases,
            uploadAvatar: userProfileUseCases.uploadProfilePhoto,
            translationService: dependencies.translationService
        )
    }

    @MainActor
    private lazy var _channelsViewModel: ChannelsViewModel = {
        ChannelsViewModel(
            useCases: channelUseCases,
            discussionUseCases: discussionUseCases,
            conversationRoomUseCases: conversationRoomUseCases,
            uploadAvatar: userProfileUseCases.uploadProfilePhoto,
            translationService: dependencies.translationService
        )
    }()

    /// The chat engine behind a channel's room.
    ///
    /// A broadcast conversation is an ordinary Core conversation, so posting into
    /// one — text, photo, voice, the upload pipeline, the outbox — is the chat
    /// room's job and is not worth a second implementation. The channel room
    /// borrows this for its composer and its messages, and supplies its own
    /// header and its own way of drawing a post.
    ///
    /// `ChatRoomViewModel` wants a chats-tab coordinator; the channel room lives
    /// in Updates, so it gets one of its own here. `ChatRoomScreen` does the
    /// same thing in reverse with `UpdatesTabCoordinator`.
    @MainActor
    func makeCommunitySettingsViewModel(communityId: String) -> CommunitySettingsViewModel {
        CommunitySettingsViewModel(
            communityId: communityId,
            useCases: communityUseCases,
            translationService: dependencies.translationService
        )
    }

    /// The gallery behind a channel room's attachment sheet.
    @MainActor
    func makeChannelGalleryViewModel(channelId: String) -> GalleryViewModel {
        GalleryViewModel(
            user: UserRoom(
                idContact: channelId,
                userId: channelId,
                phone: nil,
                name: nil,
                avatar: nil,
                description: nil,
                onlineStatus: UserOnline(status: .offline, lastSeen: "", userId: channelId),
                isBlocked: false
            ),
            isGroup: true,
            conversationId: channelId,
            discussionsUseCase: discussionUseCases,
            devicesContacts: chatPartnerPickerViewModel.deviceContacts,
            waanguContacts: chatPartnerPickerViewModel.waanguUsers
        )
    }

    /// A channel's broadcast room. Not cached: it is keyed on a channel and
    /// holds a live observation of that channel's conversation.
    @MainActor
    public func makeChannelRoomViewModel(channelId: String) -> ChannelRoomViewModel {
        ChannelRoomViewModel(
            channelId: channelId,
            channelUseCases: channelUseCases,
            uploadAvatar: userProfileUseCases.uploadProfilePhoto,
            roomUseCases: conversationRoomUseCases,
            messagesUseCases: messagesUseCases,
            voiceRecordingViewModel: makeVoiceRecordingViewModel(),
            discussionUseCases: discussionUseCases,
            postViews: channelPostViews,
            translationService: dependencies.translationService,
            channelsViewModel: _channelsViewModel
        )
    }

    @MainActor
    public func makeChannelsViewModel() -> ChannelsViewModel {
        _channelsViewModel
    }

    @MainActor
    public func makeCallsTabViewModel() -> CallsTabViewModel {
        return CallsTabViewModel(callUseCases: callUseCases)
    }
    
    @MainActor
    public func makeChatPartnerPickerViewModel() -> ChatPartnerPickerViewModel {
        // Return the shared instance instead of creating a new one
        return chatPartnerPickerViewModel
    }
    
    @MainActor
    public func makeVoiceRecordingViewModel() -> VoiceRecordingViewModel {
        return VoiceRecordingViewModel(
            opusAudioService: dependencies.opusAudioService,
            logger: dependencies.logger
        )
    }
    
    public func makeShareContentProcessor() -> ShareContentProcessorProtocol {
        return shareContentProcessor
    }
    
    public var opusPlaybackService: any OpusPlaybackServiceProtocol {
        return dependencies.opusPlaybackService
    }

    public var translationService: (any TranslationServiceProtocol)? {
        return dependencies.translationService
    }
    
    // MARK: - View Factories (Following FeatureWallet Pattern)
    
    @MainActor
    func makeMessageSearchViewModel() -> MessageSearchViewModel {
        MessageSearchViewModel(
            searchableStore: dependencies.searchableDatabase,
            fieldCrypto: dependencies.fieldEncryptionService
        )
    }

    @MainActor
    public func makeChatsListView(
        coordinator: ChatsTabCoordinator
    ) -> some View {
        ChatListNativeView(
            viewModel: makeChannelTabViewModel(),
            chatPartnerPickerViewModel: makeChatPartnerPickerViewModel(),
            navigationCoord: coordinator,
            messageSearchViewModel: makeMessageSearchViewModel()
        )
    }
    
    @MainActor
    public func makeUpdatesView(
        onNavigate: @escaping (UpdatesTabRoute) -> Void,coordinator:UpdatesTabCoordinator
        
    ) -> some View {
        StoriesView(
            statusStore: makeStoriesViewModel(),
            channelsViewModel: makeChannelsViewModel(),
            viewModel: phMediaManagerViewModel,
            navigationCoordinator: coordinator,
            translationService: dependencies.translationService
        )
           
           
    }
    
    @MainActor
    public func makeCallsView(
        onNavigate: @escaping (CallsTabRoute) -> Void
    ) -> some View {
        CallsTabScreen(
            viewModel: makeCallsTabViewModel(),
            contactsUseCase: contactUseCases,
            translationService: dependencies.translationService
        )
    }
    
    @MainActor
    public func makeCommunitiesView(
        onNavigate: @escaping (CommunitiesTabRoute) -> Void
    ) -> some View {
        CommunityTabScreen(
            viewModel: makeCommunitiesViewModel(),
            onNavigate: onNavigate
        )
    }
    
    @MainActor
    public func makeSettingsView(
        onNavigate: @escaping (SettingsTabRoute) -> Void,
        onExitToMainApp: (() -> Void)? = nil
    ) -> some View {
        let currentUserItem = UserItem(
            uid: CurrentSessionInfo.shared.currentUid,
            username: CurrentSessionInfo.shared.userName.isEmpty ? "User" : CurrentSessionInfo.shared.userName,
            email: CurrentSessionInfo.shared.email.isEmpty ? "" : CurrentSessionInfo.shared.email,
            bio: CurrentSessionInfo.shared.bio.isEmpty ? nil : CurrentSessionInfo.shared.bio,
            phoneNumber: CurrentSessionInfo.shared.userPhoneNumber,
            profileImageURL: CurrentSessionInfo.shared.userProfile.isEmpty ? nil : CurrentSessionInfo.shared.userProfile
        )
        return SettingsTabScreen(
            currentUserItem,
            appSettings: dependencies.appSettings,
            translationService: dependencies.translationService,
            onNavigate: onNavigate,
            onExitToMainApp: onExitToMainApp,
            onSignOut: { [weak self] in
                guard let self else { return }
                Task { await self.signOut() }
            }
        )
    }

    // MARK: - Déconnexion

    /// « Se déconnecter » dans les Réglages (Harness Bloc 2 §16, M1).
    ///
    /// Le bouton ne faisait rien (« handled by React Native side ») et rien
    /// n'émettait `UserDidLogoutEvent` : ses cinq abonnés — purge financière,
    /// présence, appels, temps réel, session de l'AppTarget — ne tournaient
    /// jamais.
    func signOut() async {
        await Self.signOut(
            userId: CurrentSessionInfo.shared.currentUid,
            eventBus: dependencies.eventBus,
            clearSession: { [currentUserUseCase] in try await currentUserUseCase.logout() }
        )
    }

    /// `MESSAGE` : `purgeOnLogout` du serveur vaut pour la déconnexion **voulue**.
    /// Une session expirée, suspendue ou révoquée garde les conversations : ce
    /// n'est pas l'utilisateur qui a choisi de partir.
    nonisolated static func purgesConversations(onLogout reason: UserDidLogoutEvent.Reason) -> Bool {
        reason == .userInitiated
    }

    /// Fin de session, dans l'ordre — sortie de l'abonné pour être testée (plan SDK, étape 1.14).
    nonisolated static func handleLogout(
        _ event: UserDidLogoutEvent,
        resetFinancialState: (_ userId: String) async -> Void,
        purgeConversations: () async -> Void
    ) async {
        // L'identifiant vient de l'événement, jamais de la session :
        // au moment où cet abonné réagit, la session courante peut
        // déjà avoir été effacée, et on purgerait alors le mauvais
        // espace de noms.
        await resetFinancialState(event.userId)
        // Politique de cache `MESSAGE` : les conversations s'effacent quand
        // l'utilisateur se déconnecte — jamais à l'expiration de session.
        if purgesConversations(onLogout: event.reason) {
            await purgeConversations()
        }
    }

    /// Ouverture de session, dans l'ordre — sortie de l'abonné pour être testée (plan SDK, étape 1.14).
    nonisolated static func handleChatLogin(
        userId: String,
        environment: String,
        tenant: String = "",
        defaults: UserDefaults = .standard,
        purgeConversations: () async -> Void,
        restoreFinance: () async -> Void
    ) async {
        // Avant tout le reste : la base appartient-elle à ce compte, dans ce locataire ? (F-12, 1.4)
        await reconcileDatabaseOwner(loginUserId: userId,
                                     environment: environment,
                                     tenant: tenant,
                                     defaults: defaults,
                                     purge: purgeConversations)
        await restoreFinance()
    }

    /// Tout ce que l'appareil garde des conversations : messages, participants, lignes de
    /// conversation, Waangu Copilot, et tout ce qui s'y rattache — réactions, accusés,
    /// épingles, actions, préférences, groupes, appels, statuts, file d'envoi, médias,
    /// curseurs de synchro. Les contacts restent : c'est le carnet d'adresses.
    func purgeConversations() async {
        let database = dependencies.database
        try? await localDiscussionDataSource.deleteAllDiscussions()
        try? await database.deleteAll(CopilotMessageModel.self, query: nil)
        try? await database.deleteAll(MessageReactionModel.self, query: nil)
        try? await database.deleteAll(ReadReceiptModel.self, query: nil)
        try? await database.deleteAll(PinnedMessageModel.self, query: nil)
        try? await database.deleteAll(ChatActionModel.self, query: nil)
        try? await database.deleteAll(ChatPreferenceModel.self, query: nil)
        try? await database.deleteAll(GroupSettingsModel.self, query: nil)
        try? await database.deleteAll(GroupPermissionsModel.self, query: nil)
        try? await database.deleteAll(GroupJoinRequestModel.self, query: nil)
        try? await database.deleteAll(CallLogModel.self, query: nil)
        try? await database.deleteAll(StatusViewerModel.self, query: nil)
        try? await database.deleteAll(StatusModel.self, query: nil)
        // Messages écrits mais pas encore partis : ils ne passent pas au compte suivant.
        try? await database.deleteAll(ChatOutboxItem.self, query: nil)
        DiskMediaManager.shared.deleteEverything(in: .CHAT)
        DiskMediaManager.shared.deleteEverything(in: .STATUS)
        syncCursorStore.clearAllSyncCursors()
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        UserDefaults.standard.removeObject(forKey: Self.databaseOwnerKey)
        await Self.clearSyncWatermarks(in: database)
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }

    // MARK: - Propriétaire de la base locale (F-12)

    /// Compte auquel appartiennent les conversations stockées sur l'appareil.
    static let databaseOwnerKey = "chatDatabaseOwnerUserId"

    enum DatabaseOwnerDecision: Equatable { case keep, adopt, purgeThenAdopt }

    /// La base locale n'est pas rangée par compte : seule la purge de déconnexion volontaire
    /// l'empêche de passer au suivant. Une session expirée, suspendue ou révoquée garde les
    /// conversations — donc un autre compte qui se connecte ensuite les verrait. On compare
    /// donc le compte qui se connecte à celui qui a rempli la base.
    ///
    /// Sans repère (installation antérieure), la base est adoptée par le compte courant :
    /// rien n'est perdu, mais le premier changement de compte avant cette mise à jour n'est
    /// pas rattrapé.
    ///
    /// Le repère nomme aussi l'environnement (hôte de l'API) : un build repointé vers un
    /// autre serveur ne montre pas ce qu'un autre serveur a mis en cache (ADD-3). Un repère
    /// d'avant, sans environnement, garde ses données et reçoit l'environnement courant.
    ///
    /// Le locataire (plan SDK, étape 1.4) : le même identifiant utilisateur dans un autre locataire
    /// n'est pas la même personne pour le serveur (les conversations dépendent du locataire, de
    /// l'organisation et des appartenances). Le repère devient `utilisateur|serveur|locataire`.
    /// - un locataire **différent** de celui du repère efface les données locales ;
    /// - un repère d'avant, sans locataire, **garde** ses données et reçoit le locataire courant ;
    /// - un locataire **inconnu** à cette connexion (la réponse n'en contient pas) ne change rien :
    ///   on ne peut pas dire qu'il a changé, et le repère n'est pas réécrit.
    /// La version de schéma attend toujours le contrat de Chat Core.
    nonisolated static func databaseOwnerDecision(
        stored: String?,
        loginUserId: String,
        environment: String = "",
        tenant: String = ""
    ) -> DatabaseOwnerDecision {
        guard !loginUserId.isEmpty else { return .keep }
        guard let stored, !stored.isEmpty else { return .adopt }
        let parts = stored.components(separatedBy: "|")
        guard parts[0] == loginUserId else { return .purgeThenAdopt }
        guard !environment.isEmpty else { return .keep }
        let storedEnvironment = parts.count > 1 ? parts[1] : ""
        if storedEnvironment.isEmpty { return .adopt }
        guard storedEnvironment == environment else { return .purgeThenAdopt }
        let tenant = ownerMarkerPart(tenant)
        guard !tenant.isEmpty else { return .keep }
        let storedTenant = parts.count > 2 ? parts[2] : ""
        if storedTenant.isEmpty { return .adopt }
        return storedTenant == tenant ? .keep : .purgeThenAdopt
    }

    /// Le séparateur du repère ne peut pas figurer dans une de ses parties : un locataire qui le
    /// contiendrait serait relu tronqué et effacerait les données à chaque connexion.
    nonisolated static func ownerMarkerPart(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "_")
    }

    nonisolated static func reconcileDatabaseOwner(
        loginUserId: String,
        environment: String = "",
        tenant: String = "",
        defaults: UserDefaults = .standard,
        purge: () async -> Void
    ) async {
        var marker = loginUserId
        if !environment.isEmpty {
            marker += "|\(environment)"
            let tenantPart = ownerMarkerPart(tenant)
            if !tenantPart.isEmpty { marker += "|\(tenantPart)" }
        }
        switch databaseOwnerDecision(
            stored: defaults.string(forKey: databaseOwnerKey),
            loginUserId: loginUserId,
            environment: environment,
            tenant: tenant
        ) {
        case .keep:
            return
        case .adopt:
            defaults.set(marker, forKey: databaseOwnerKey)
        case .purgeThenAdopt:
            await purge()
            defaults.set(marker, forKey: databaseOwnerKey)
        }
    }

    /// Les repères de synchro (`chat`, `chat.conversations`, `chat.calls`) sont rangés
    /// par flux, pas par compte : sans cet effacement, le compte suivant reprendrait
    /// la tirée du précédent et ne recevrait jamais son propre historique (F-10).
    static func clearSyncWatermarks(in database: any DatabaseRepositoryProtocol) async {
        try? await database.deleteAll(SyncState.self, query: nil)
    }

    /// Identity revoked this session (`SESSION_REVOKED`, plan SDK step 1.6).
    ///
    /// The session ends the way a sign-out does: the logout event first, then the session is
    /// cleared. Two differences, both on purpose:
    /// - the reason is `remoteRevocation`, **not** `userInitiated`, so the local conversations
    ///   are kept: only a deliberate logout clears the local database (`purgesConversations`);
    /// - the chat tokens are cleared too, because the session they carry is known to be dead and
    ///   the realtime connection would otherwise keep presenting it.
    ///
    /// Nothing happens when no user is signed in: a second event, or one that arrives after a
    /// logout, has nothing left to end. Returns whether a session was ended.
    @discardableResult
    nonisolated static func handleSessionRevoked(
        userId: String,
        eventBus: any EventBusProtocol,
        clearSession: () async throws -> Void,
        clearChatTokens: () async throws -> Void
    ) async -> Bool {
        guard !userId.isEmpty else { return false }
        await eventBus.publish(UserDidLogoutEvent(userId: userId, reason: .remoteRevocation))
        try? await clearSession()
        try? await clearChatTokens()
        return true
    }

    private func handleRemoteRevocation() async {
        let ended = await Self.handleSessionRevoked(
            userId: CurrentSessionInfo.shared.currentUid,
            eventBus: dependencies.eventBus,
            clearSession: { [currentUserUseCase] in try await currentUserUseCase.logout() },
            clearChatTokens: { [chatTokenManager = dependencies.chatTokenManager] in try await chatTokenManager.clearTokens() }
        )
        if ended { debugLog("session revoked by Identity: session ended, conversations kept", category: "session") }
    }

    /// L'ordre est le contrat : l'événement **avant** l'effacement de session.
    /// La purge financière lit l'identifiant dans l'événement ; l'abonné des
    /// appels a besoin d'une session encore valide pour quitter une salle.
    static func signOut(
        userId: String,
        eventBus: any EventBusProtocol,
        clearSession: () async throws -> Void
    ) async {
        await eventBus.publish(UserDidLogoutEvent(userId: userId, reason: .userInitiated))
        try? await clearSession()
    }

    /// The signed-in user's own profile screen, reached from the settings header.
    @MainActor
    public func makeProfileView() -> some View {
        ProfileEditView(
            useCases: userProfileUseCases,
            translationService: dependencies.translationService
        )
    }
    
    // Legacy view factories (deprecated - for backward compatibility)
    @MainActor
    public func makeRootView() -> some View {
        Text("Chat Conversations")
    }
    
    @MainActor
    public func makeChatRoomView(conversationId: String) -> some View {
        Text("Chat Room: \(conversationId)")
    }
    
    @MainActor
    public func makeContactsView() -> some View {
        Text("Contacts")
    }
}
