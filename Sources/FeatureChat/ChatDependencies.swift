//
//  ChatDependencies.swift
//  FeatureChat
//
//  Created by Refactoring on 5/5/26.
//

import Foundation
import WaanguCoreKit

/// External dependencies that FeatureChat needs from the main app
/// These are injected when the feature is loaded
public struct ChatDependencies : Sendable {
    public let apiClient: any APIClientProtocol
    public let uploadApiClient: any APIClientProtocol
    public let logger: any AppLoggerProtocol
    public let networkMonitor: any NetworkMonitoringProtocol
    public let eventBus: any EventBusProtocol
    public let realtime: any RealtimeClientProtocol
    public let chatOutbox: any ChatOutboxEnqueuing
    /// Settles queued actions when the server acknowledges them, and replays the
    /// ones it never did. Separate from `chatOutbox`, which only writes.
    public let chatOutboxMaintenance: any ChatOutboxMaintaining
    public let opusAudioService: any OpusAudioServiceProtocol
    public let opusPlaybackService: any OpusPlaybackServiceProtocol
    public let permissionService: any PermissionServiceProtocol
    public let tokenManager: any TokenManagerProtocol
    public let chatTokenManager: any ChatTokenManagerProtocol
    
    // Security & Compliance
    public let messageConfirmationGuard: any MessageConfirmationGuardProtocol
    public let paymentConfirmationGuard: any PaymentConfirmationGuardProtocol
    public let promptInjectionFilter: any PromptInjectionFilterProtocol
    public let signedPushVerifier: any SignedPushVerifierProtocol
    public let fieldEncryptionService: any FieldEncryptionServiceProtocol
    public let pendingE2EEQueue: any PendingE2EEQueueProtocol

    // MARK: - Finance conversationnelle (Bloc 1)
    //
    // Contrats CoreKit, implémentés dans SecurityKit et DomainKit, injectés par
    // l'AppTarget. FeatureChat ne dépend ni de l'un ni de l'autre — voir
    // BLOC1-CHAT-FINANCE-INTEGRATION.md §4.

    /// Lecture et écriture des objets financiers.
    ///
    /// Optionnel : la cible de test et les configurations sans finance construisent
    /// le graphe sans lui. `nil` équivaut à capacités fermées.
    public let financeAPIClient: (any FinanceAPIClientProtocol)?

    /// Ce que l'utilisateur a le droit de faire. Fermé par défaut.
    public let financeCapabilities: any FinanceCapabilityProviding

    /// Garantit qu'un retry porte la clé de sa première tentative.
    /// **Jamais optionnel.** En `nil`, chaque `preserver?.assertSameKey(...)`
    /// devenait une instruction vide : une tentative rejouée avec un contenu
    /// différent passait sans contrôle, sans même un avertissement de
    /// compilation. Le défaut refuse d'enregistrer, donc rien ne part.
    public let idempotencyPreserver: any IdempotencyKeyPreserving

    /// Résolution du bénéficiaire — chapitre 10.
    ///
    /// Fermé par défaut : tant que `POST /recipient/resolve` n'existe pas, aucune
    /// saisie ne devient un bénéficiaire, donc aucune émission n'est atteignable.
    /// C'est la même protection intérimaire que `ClosedFinanceCapabilities`.
    public let recipientResolver: any RecipientResolving

    /// Permis d'exécution — chapitre 13.
    ///
    /// Fermé par défaut : sans `POST /execution-permits`, aucun permis n'est
    /// émis, donc aucune confirmation n'aboutit.
    public let executionPermits: any ExecutionPermitIssuing

    /// Catalogue des entrées financières d'une conversation — chapitre 16.
    ///
    /// Fermé par défaut : tant que `GET /v1/financial/capabilities` n'existe pas,
    /// aucune entrée n'est proposée. Le menu financier s'affiche, et il est vide
    /// — ce qui est le comportement juste, et non un écran cassé.
    public let financeCatalog: any ChatFinanceCatalogProviding

    /// Émission des demandes d'argent — chapitre 17.
    public let moneyRequests: any MoneyRequestCreating

    /// Devis de transfert — chapitre 18.
    public let transferQuoting: any TransferQuoting

    /// Résolution des QR financiers — chapitre 22.
    public let qrResolver: any QRResolving

    /// Émission des QR présentés pour encaisser — chapitre 7.
    public let qrPresenter: any QRPresenting

    /// Profil marchand et paiement marchand — chapitre 7.
    public let merchantProfiles: any MerchantProfileProviding

    /// Catalogue, panier, commandes, après-vente — chapitre 7.
    public let commerce: any CommerceOrdering

    /// Formulaires distants — chapitre 7.
    public let remoteForms: any RemoteFormProviding

    /// Support corrélé à une transaction — chapitre 7.
    public let support: any SupportCaseOpening

    /// Factures marchandes — chapitre 46.
    public let merchantInvoices: any InvoiceProviding

    /// Liens de paiement — chapitre 46.2.
    public let paymentLinks: any PaymentLinkResolving

    /// Cartes — chapitre 48.
    public let cards: any CardManaging

    /// Transactions cartes — chapitre 49.
    public let cardTransactions: any CardTransactionProviding

    /// Partage d'addition — chapitre 50.
    public let splitBills: any SplitBillManaging

    /// Paiement de proximité — chapitre 47.
    public let proximityPayments: any ProximityPaymentSessioning

    /// Collectes, tontines, cagnottes — chapitre 51.
    public let campaigns: any CampaignManaging

    /// Objets des mini-apps — chapitre 52.
    public let nativeApps: any NativeAppObjectProviding

    /// Rapprochements et incidents — chapitre 53.
    public let reconciliation: any ReconciliationProviding

    /// Litiges — chapitre 25.
    public let disputes: any DisputeFiling

    /// Dépôt — chapitre 19.
    public let cashIn: any CashInInitiating
    /// Retrait — chapitre 20.
    public let cashOut: any CashOutIssuing
    /// Factures — chapitre 21.
    public let bills: any BillPaying
    /// Validation des champs de facturier, injectée par l'app. `nil` ⇒ seule
    /// la validation du serveur s'applique.
    public let billFieldValidator: BillFieldValidating?
    /// Recharges — chapitre 23.
    public let topUp: any TopUpOrdering
    /// Reçus — chapitre 24.
    public let receipts: any ReceiptAccessProviding
    /// Traduction d'un texte financier (§58). Fermée par défaut : le texte
    /// d'origine s'affiche, ce qui est toujours correct.
    public let financialTranslator: any FinancialTranslating

    /// Où le Chat envoie ses mesures (ouverture, envoi, reconnexion, échec de synchro).
    /// Rien par défaut : un hôte qui ne branche rien ne change pas de comportement.
    public let metricsSink: any ChatMetricsSink

    /// Relevé des opérations du compte — l'écran « Historique des transactions ».
    public let transactionHistory: any TransactionHistoryProviding

    /// Sources de financement proposées au moment de payer.
    public let fundingSources: any FundingSourceProviding

    /// Remplace la lecture du solde servie par `sharedFeatureUsecases`.
    ///
    /// `nil` ⇒ le contrat partagé garde la main, ce qui est le cas en
    /// production. N'existe que pour que l'échafaudage de développement puisse
    /// fournir un solde sans toucher au graphe partagé.
    public let financeBalanceOverride: (any GetBalanceUseCaseProtocol)?
    /// Mandats — chapitre 30.
    public let mandates: any MandateManaging
    /// Suspensions opérationnelles — §44.
    public let killSwitch: any OperationalKillSwitchProviding

    /// Persistance des objets financiers — lot 2.1.
    ///
    /// `nil` ⇒ magasin en mémoire seule : une opération en cours ne survit pas
    /// au redémarrage, et la réconciliation à froid ne trouve rien à reprendre.
    /// L'implémentation est fournie par l'AppTarget, seul à connaître le
    /// stockage et le compte courant.
    public let financialObjectPersistence: (any FinancialObjectPersisting)?

    // ── Bloc 5 ───────────────────────────────────────────────
    /// Portes d'activation — §16. Condition de tout le reste.
    public let capabilityGates: any FinancialCapabilityGateProviding
    /// État de session Chat Core — `nil` hors backend réel (doublures).
    public let financeSession: (any FinanceSessionProviding)?
    public let remittance: any RemittanceSending
    public let fx: any FXConverting
    public let credit: any CreditLending
    public let savings: any SavingsManaging
    public let investment: any InvestmentTrading
    public let pfm: any PersonalFinanceProviding

    /// Satisfait les politiques de step-up exigées par le backend.
    /// **Jamais optionnel.** Un `nil` laisserait chaque site d'appel décider
    /// quoi faire de son absence, et il suffit d'un site qui l'interprète
    /// comme « pas de step-up requis » pour ouvrir un chemin non authentifié.
    /// Le défaut refuse ; il ne manque pas.
    public let stepUpAuthenticator: any StepUpAuthenticating
    /// Répondre à une demande d'argent reçue. `nil` ⇒ la carte n'offre ni
    /// « Payer » ni « Refuser » — jamais un bouton qui ne mène nulle part.
    public let moneyRequestResponder: (any MoneyRequestResponding)?
    /// Rembourser ou demander l'extourne. Le défaut n'offre rien.
    public let reversals: any OperationReversing
    
    // MARK: shared feature use cases (main API client)
    public let sharedFeatureUsecases: any SharedFeatureUsecasesProtocol
    
    // MARK: database
    
    public let database: any DatabaseRepositoryProtocol
    public let searchableDatabase: any SearchableDatabaseProtocol
    
    public let deviceInfoProvider: any DeviceInfoProvidingProtocol

    /// Bloc 8, §33 — un appareil révoqué ne synchronise pas de données
    /// sensibles. Injecté par l'AppTarget, seul module qui voit `SecurityKit`.
    public let deviceRevocation: any DeviceRevocationChecking

    /// Bloc 9, §21 — autorité qui horodate et chaîne les faits d'audit.
    public let auditEmitter: any FinancialAuditEmitting

    /// Bloc 9, §9 — rotation et détection de réutilisation des refresh tokens.
    public let tokenRotation: any RefreshTokenRotating

    /// Bloc 9, §13 — vérification d'attestation. Autorité serveur.
    public let attestationVerifier: any DeviceAttestationVerifying
    
    public let appSettings : any AppSettingsProtocol

    /// Translation service — reusable across all features.
    public let translationService: any TranslationServiceProtocol

    /// Main app API base URL (used by legacy upload paths).
    public let mainAPIBaseURL: String

    /// The host app's identifier in Identity, sent as `X-App-Id` on chat login. Identity asks that
    /// app's registered `verify-user` webhook who the signed-in user is, so each app must send its
    /// own. It used to be a literal inside this package, which made every host log in as Waangu User.
    public let appId: String

    /// Sent as `user_identifier` in the chat login body. Required, like `appId`.
    public let userId: String

    /// The parts of chat the host turned on (SDK plan, step 1.10). A part that is off shows no
    /// entry point. Defaults to all, so a caller that says nothing behaves as before.
    public let enabledModules: Set<ChatModule>

    /// Carries call audio and video. Supplied by the app target, which is the
    /// only place that knows CallMediaKit. Optional so the feature still builds
    /// and signals without it — calls simply stay silent.
    public let callMediaEngine: (any CallMediaEngineProtocol)?

    public init(
        apiClient: any APIClientProtocol,
        uploadApiClient: any APIClientProtocol,
        logger: any AppLoggerProtocol,
        networkMonitor: any NetworkMonitoringProtocol,
        eventBus: any EventBusProtocol,
        realtime: any RealtimeClientProtocol,
        chatOutbox: any ChatOutboxEnqueuing,
        chatOutboxMaintenance: any ChatOutboxMaintaining,
        opusAudioService: any OpusAudioServiceProtocol,
        opusPlaybackService: any OpusPlaybackServiceProtocol,
        permissionService: any PermissionServiceProtocol,
        messageConfirmationGuard: any MessageConfirmationGuardProtocol,
        paymentConfirmationGuard: any PaymentConfirmationGuardProtocol,
        promptInjectionFilter: any PromptInjectionFilterProtocol,
        signedPushVerifier: any SignedPushVerifierProtocol,
        fieldEncryptionService: any FieldEncryptionServiceProtocol,
        pendingE2EEQueue: any PendingE2EEQueueProtocol,
        sharedFeatureUsecases: any SharedFeatureUsecasesProtocol,
        tokenManager: any TokenManagerProtocol,
        database: any DatabaseRepositoryProtocol,
        searchableDatabase: any SearchableDatabaseProtocol,
        deviceInfoProvider: any DeviceInfoProvidingProtocol,
        deviceRevocation: any DeviceRevocationChecking = AllowAllDeviceRevocation(),
        auditEmitter: any FinancialAuditEmitting = UnavailableAuditEmitter(),
        tokenRotation: any RefreshTokenRotating = UnavailableTokenRotation(),
        attestationVerifier: any DeviceAttestationVerifying = UnavailableAttestationVerifier(),
        mainAPIBaseURL: String,
        appId: String,
        userId: String,
        appSettings: any AppSettingsProtocol,
        translationService: any TranslationServiceProtocol,
        chatTokenManager: any ChatTokenManagerProtocol,
        callMediaEngine: (any CallMediaEngineProtocol)? = nil,
        financeAPIClient: (any FinanceAPIClientProtocol)? = nil,
        financeCapabilities: any FinanceCapabilityProviding = ClosedFinanceCapabilities(),
        idempotencyPreserver: any IdempotencyKeyPreserving = ClosedIdempotencyKeyPreserver(),
        recipientResolver: any RecipientResolving = ClosedRecipientResolver(),
        executionPermits: any ExecutionPermitIssuing = ClosedExecutionPermitIssuer(),
        financeCatalog: any ChatFinanceCatalogProviding = ClosedChatFinanceCatalog(),
        moneyRequests: any MoneyRequestCreating = ClosedMoneyRequestService(),
        transferQuoting: any TransferQuoting = ClosedTransferQuoting(),
        qrResolver: any QRResolving = ClosedQRResolver(),
        qrPresenter: any QRPresenting = ClosedQRPresenter(),
        merchantProfiles: any MerchantProfileProviding = ClosedMerchantProfileProvider(),
        commerce: any CommerceOrdering = ClosedCommerceOrdering(),
        remoteForms: any RemoteFormProviding = ClosedRemoteFormProvider(),
        support: any SupportCaseOpening = ClosedSupportCaseOpener(),
        merchantInvoices: any InvoiceProviding = ClosedInvoiceProvider(),
        paymentLinks: any PaymentLinkResolving = ClosedPaymentLinkResolver(),
        cards: any CardManaging = ClosedCardManager(),
        cardTransactions: any CardTransactionProviding = ClosedCardTransactionProvider(),
        splitBills: any SplitBillManaging = ClosedSplitBillManager(),
        proximityPayments: any ProximityPaymentSessioning = ClosedProximityPaymentSessioning(),
        campaigns: any CampaignManaging = ClosedCampaignManager(),
        nativeApps: any NativeAppObjectProviding = ClosedNativeAppObjectProvider(),
        reconciliation: any ReconciliationProviding = ClosedReconciliationProvider(),
        disputes: any DisputeFiling = ClosedDisputeFiling(),
        cashIn: any CashInInitiating = ClosedCashIn(),
        cashOut: any CashOutIssuing = ClosedCashOut(),
        bills: any BillPaying = ClosedBillPaying(),
        billFieldValidator: BillFieldValidating? = nil,
        topUp: any TopUpOrdering = ClosedTopUp(),
        receipts: any ReceiptAccessProviding = ClosedReceiptAccess(),
        transactionHistory: any TransactionHistoryProviding = ClosedTransactionHistory(),
        fundingSources: any FundingSourceProviding = ClosedFundingSources(),
        financeBalanceOverride: (any GetBalanceUseCaseProtocol)? = nil,
        mandates: any MandateManaging = ClosedMandateManaging(),
        killSwitch: any OperationalKillSwitchProviding = ClosedKillSwitch(),
        financialObjectPersistence: (any FinancialObjectPersisting)? = nil,
        capabilityGates: any FinancialCapabilityGateProviding = ClosedCapabilityGates(),
        financeSession: (any FinanceSessionProviding)? = nil,
        remittance: any RemittanceSending = ClosedRemittance(),
        fx: any FXConverting = ClosedFX(),
        credit: any CreditLending = ClosedCredit(),
        savings: any SavingsManaging = ClosedSavings(),
        investment: any InvestmentTrading = ClosedInvestment(),
        pfm: any PersonalFinanceProviding = ClosedPFM(),
        stepUpAuthenticator: any StepUpAuthenticating = ClosedStepUpAuthenticator(),
        moneyRequestResponder: (any MoneyRequestResponding)? = nil,
        reversals: any OperationReversing = ClosedOperationReversing(),
        financialTranslator: any FinancialTranslating = ClosedFinancialTranslator(),
        metricsSink: any ChatMetricsSink = NoChatMetrics(),
        enabledModules: Set<ChatModule> = ChatModule.all
    ) {
        self.callMediaEngine = callMediaEngine
        self.apiClient = apiClient
        self.uploadApiClient = uploadApiClient
        self.logger = logger
        self.networkMonitor = networkMonitor
        self.eventBus = eventBus
        self.realtime = realtime
        self.chatOutbox = chatOutbox
        self.chatOutboxMaintenance = chatOutboxMaintenance
        self.opusAudioService = opusAudioService
        self.opusPlaybackService = opusPlaybackService
        self.permissionService = permissionService
        self.messageConfirmationGuard = messageConfirmationGuard
        self.paymentConfirmationGuard = paymentConfirmationGuard
        self.promptInjectionFilter = promptInjectionFilter
        self.signedPushVerifier = signedPushVerifier
        self.fieldEncryptionService = fieldEncryptionService
        self.pendingE2EEQueue = pendingE2EEQueue
        self.sharedFeatureUsecases = sharedFeatureUsecases
        self.tokenManager = tokenManager
        self.database = database
        self.searchableDatabase = searchableDatabase
        self.deviceInfoProvider = deviceInfoProvider
        self.deviceRevocation = deviceRevocation
        self.auditEmitter = auditEmitter
        self.tokenRotation = tokenRotation
        self.attestationVerifier = attestationVerifier
        self.mainAPIBaseURL = mainAPIBaseURL
        self.appId = appId
        self.userId = userId
        self.enabledModules = enabledModules
        self.appSettings = appSettings
        self.translationService = translationService
        self.chatTokenManager = chatTokenManager
        self.financeAPIClient = financeAPIClient
        self.financeCapabilities = financeCapabilities
        self.idempotencyPreserver = idempotencyPreserver
        self.recipientResolver = recipientResolver
        self.executionPermits = executionPermits
        self.financeCatalog = financeCatalog
        self.moneyRequests = moneyRequests
        self.transferQuoting = transferQuoting
        self.qrResolver = qrResolver
        self.qrPresenter = qrPresenter
        self.merchantProfiles = merchantProfiles
        self.commerce = commerce
        self.remoteForms = remoteForms
        self.support = support
        self.merchantInvoices = merchantInvoices
        self.paymentLinks = paymentLinks
        self.cards = cards
        self.cardTransactions = cardTransactions
        self.splitBills = splitBills
        self.proximityPayments = proximityPayments
        self.campaigns = campaigns
        self.nativeApps = nativeApps
        self.reconciliation = reconciliation
        self.disputes = disputes
        self.cashIn = cashIn
        self.cashOut = cashOut
        self.bills = bills
        self.billFieldValidator = billFieldValidator
        self.topUp = topUp
        self.receipts = receipts
        self.financialTranslator = financialTranslator
        self.metricsSink = metricsSink
        self.transactionHistory = transactionHistory
        self.fundingSources = fundingSources
        self.financeBalanceOverride = financeBalanceOverride
        self.mandates = mandates
        self.killSwitch = killSwitch
        self.financialObjectPersistence = financialObjectPersistence
        self.capabilityGates = capabilityGates
        self.financeSession = financeSession
        self.remittance = remittance
        self.fx = fx
        self.credit = credit
        self.savings = savings
        self.investment = investment
        self.pfm = pfm
        self.stepUpAuthenticator = stepUpAuthenticator
        self.moneyRequestResponder = moneyRequestResponder
        self.reversals = reversals
    }
}


// MARK: - Repli fermé

/// Catalogue de capacités qui n'ouvre rien.
///
/// Valeur par défaut de `financeCapabilities`, pour qu'un graphe construit sans
/// finance — cible de test, configuration réduite — se comporte comme un graphe
/// dont le backend a tout fermé, plutôt que d'exiger un paramètre de plus à
/// chaque site de construction.
public struct ClosedFinanceCapabilities: FinanceCapabilityProviding {
    public init() {}
    public func capabilities() async -> FinanceCapabilities { .none }
    public func invalidate() async {}
}

/// Valeur par défaut de `recipientResolver`.
///
/// **BACKEND CONTRACT REQUIRED** — `POST /recipient/resolve`.
///
/// Refuse toute résolution avec `undetermined`, et non `notFound` : dire « ce
/// numéro n'existe pas » serait une affirmation, alors que le client n'en sait
/// rien. La nuance compte pour l'utilisateur, qui ressaisirait sinon un
/// bénéficiaire pourtant correct.
/// Valeur par défaut de `financeCatalog`.
///
/// **BACKEND CONTRACT REQUIRED** — `GET /v1/financial/capabilities`.
///
/// Rend une liste vide, jamais une liste d'entrées désactivées : proposer sept
/// entrées grisées ferait croire que le produit existe et qu'il est en panne,
/// alors qu'il n'est simplement pas encore livré sur ce marché.
public struct ClosedChatFinanceCatalog: ChatFinanceCatalogProviding {
    public init() {}
    public func entries(for context: ChatFinanceContext) async -> [FinanceCatalogEntry] { [] }
    public func invalidate() async {}
}

// MARK: - Parcours fermés par défaut (chapitres 19, 20, 21, 23)
//
// **BACKEND CONTRACT REQUIRED** pour chacun. Les protocoles existent, les écrans
// peuvent être construits et éprouvés, et rien ne s'exécute : c'est la forme que
// prend « continuer l'implémentation autour de l'abstraction ».

public struct ClosedCashIn: CashInInitiating {
    public init() {}
    public func availableChannels() async -> Result<[CashInChannel], FinanceError> {
        // Liste vide, pas erreur : aucun canal ouvert sur ce marché se dit
        // autrement qu'une panne.
        .success([])
    }
    public func createInstruction(_ request: CashInRequest,
                                  idempotency: IdempotencyContext) async -> Result<CashInInstruction, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func requery(_ reference: FinancialReference) async -> Result<CashInInstruction, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedCashOut: CashOutIssuing {
    public init() {}
    public func availableChannels() async -> Result<[CashOutChannel], FinanceError> { .success([]) }
    public func issue(_ request: CashOutRequest, idempotency: IdempotencyContext,
                      stepUp: StepUpAttestation?) async -> Result<CashOutAuthorization, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func revoke(_ reference: FinancialReference,
                       idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        // La révocation échoue aussi — mais l'échec doit être visible : un
        // utilisateur qui croit avoir révoqué un code compromis et ne l'a pas
        // fait est dans une situation pire que s'il le savait.
        .failure(.capabilityUnavailable)
    }
    public func requery(_ reference: FinancialReference) async -> Result<CashOutAuthorization, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedBillPaying: BillPaying {
    public init() {}
    public func categories() async -> Result<[BillerCategory], FinanceError> { .success([]) }
    public func form(for billerID: String) async -> Result<DynamicBiller, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func lookup(billerID: String, fields: [String: String]) async -> Result<Bill, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func pay(_ bill: Bill, amount: Decimal?,
                    idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

// MARK: - Bloc 5 — services fermés par défaut
//
// **BACKEND CONTRACT REQUIRED** pour chacun. Le patron est celui des quatre
// blocs précédents : les contrats existent, les écrans peuvent être construits
// et éprouvés, et rien ne s'exécute.
//
// La règle §16 est portée par `ClosedCapabilityGates` : sans capacité, aucune
// porte n'est ouverte, donc aucune fonctionnalité du Bloc 5 n'est disponible —
// même si son service répondait.

/// Aucune capacité. **Toutes les portes fermées.**
///
/// Une liste vide, et non une liste de capacités désactivées : le §16 dit
/// qu'une fonctionnalité devient disponible quand toutes ses portes sont
/// ouvertes. L'absence de capacité est le refus par défaut, pas une panne.
public struct ClosedCapabilityGates: FinancialCapabilityGateProviding {
    public init() {}
    public func capabilities() async -> [FinancialCapability] { [] }
    public func invalidate() async {}
}

public struct ClosedRemittance: RemittanceSending {
    public init() {}
    public func corridors() async -> Result<[RemittanceCorridor], FinanceError> { .success([]) }
    public func quote(_ request: RemittanceQuoteRequest) async -> Result<FinancialQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func create(quote: FinancialQuote, recipientID: String,
                       idempotency: IdempotencyContext) async -> Result<Remittance, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func fund(_ id: String, method: RemittanceFundingMethod,
                     idempotency: IdempotencyContext,
                     stepUp: StepUpAttestation?) async -> Result<Remittance, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func submit(_ id: String, idempotency: IdempotencyContext) async -> Result<Remittance, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func track(_ id: String) async -> Result<Remittance, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func cancel(_ id: String, idempotency: IdempotencyContext) async -> Result<Remittance, FinanceError> {
        // Échoue **bruyamment** : un utilisateur qui croit avoir annulé un
        // envoi international et ne l'a pas fait est dans une situation qu'il
        // découvrira trop tard.
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedFX: FXConverting {
    public init() {}
    public func wallets() async -> Result<[CurrencyWallet], FinanceError> { .success([]) }
    public func quote(from source: String, to target: String,
                      sourceAmount: Decimal) async -> Result<FinancialQuote, FinanceError> {
        // Le client ne peut pas fabriquer une cotation : il faudrait inventer un
        // taux, exactement le calcul que §10 interdit.
        .failure(.capabilityUnavailable)
    }
    public func convert(quote: FinancialQuote,
                        idempotency: IdempotencyContext) async -> Result<FXConversion, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func automaticRules() async -> Result<[FXAutomaticRule], FinanceError> { .success([]) }
    public func revokeRule(_ ruleID: String,
                           idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedCredit: CreditLending {
    public init() {}
    public func catalog() async -> Result<[CreditProduct], FinanceError> { .success([]) }
    public func simulate(_ request: CreditSimulationRequest) async -> Result<CreditSimulation, FinanceError> {
        // Aucune simulation locale : mensualité, coût total et taux effectif
        // sont des calculs de prêteur.
        .failure(.capabilityUnavailable)
    }
    public func eligibility(productID: String) async -> Result<CreditEligibility, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func apply(_ draft: CreditApplicationDraft,
                      idempotency: IdempotencyContext) async -> Result<CreditApplication, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func application(_ id: String) async -> Result<CreditApplication, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func acceptOffer(applicationID: String, offerID: String, consentVersion: String,
                            idempotency: IdempotencyContext,
                            stepUp: StepUpAttestation?) async -> Result<CreditApplication, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func earlyRepaymentQuote(creditID: String) async -> Result<FinancialQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedSavings: SavingsManaging {
    public init() {}
    public func pockets() async -> Result<[SavingsPocket], FinanceError> { .success([]) }
    public func create(_ draft: SavingsPocketDraft,
                       idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func fund(pocketID: String, amount: Money,
                     idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func withdraw(pocketID: String, amount: Money, idempotency: IdempotencyContext,
                         stepUp: StepUpAttestation?) async -> Result<SavingsPocket, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func pauseRule(pocketID: String, ruleID: String,
                          idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func resumeRule(pocketID: String, ruleID: String,
                           idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func closePocket(_ id: String,
                            idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedInvestment: InvestmentTrading {
    public init() {}
    public func products() async -> Result<[InvestmentProduct], FinanceError> { .success([]) }
    /// `nil` ⇒ profil non établi. **Rien n'est souscriptible** : c'est le
    /// gating de suitability, et il est fermé par défaut.
    public func investorProfile() async -> Result<InvestorProfile?, FinanceError> { .success(nil) }
    public func placeOrder(_ draft: InvestmentOrderDraft, idempotency: IdempotencyContext,
                           stepUp: StepUpAttestation?) async -> Result<InvestmentOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func order(_ id: String) async -> Result<InvestmentOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func cancelOrder(_ id: String,
                            idempotency: IdempotencyContext) async -> Result<InvestmentOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func portfolio() async -> Result<[InvestmentHolding], FinanceError> { .success([]) }
}

public struct ClosedPFM: PersonalFinanceProviding {
    public init() {}
    public func summary(period: PFMPeriod) async -> Result<PFMSummary, FinanceError> {
        // Aucun agrégat local : additionner des transactions côté client
        // divergerait de la comptabilité dès la première opération en vol.
        .failure(.capabilityUnavailable)
    }
    public func budgets() async -> Result<[PFMBudget], FinanceError> { .success([]) }
    public func createBudget(_ draft: PFMBudgetDraft,
                             idempotency: IdempotencyContext) async -> Result<PFMBudget, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func anomalies(period: PFMPeriod) async -> Result<[PFMAnomaly], FinanceError> { .success([]) }
    public func recategorize(operationID: String, categoryID: String,
                             idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedMandateManaging: MandateManaging {
    public init() {}
    public func mandates() async -> Result<[Mandate], FinanceError> { .success([]) }
    public func create(_ draft: MandateDraft,
                       idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func suspend(_ id: String, idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func resume(_ id: String, idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func revoke(_ id: String, idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError> {
        // La révocation échoue **bruyamment**. Un utilisateur qui croit avoir
        // révoqué une autorisation de débit permanente et ne l'a pas fait est
        // dans la pire situation du bloc.
        .failure(.capabilityUnavailable)
    }
}

/// Valeur par défaut du kill switch.
///
/// **Ne suspend rien** — et ce choix mérite d'être justifié, car il va contre
/// la fermeture par défaut adoptée partout ailleurs.
///
/// Les services financiers sont **déjà tous fermés** par leurs propres défauts :
/// rien ne s'exécute. Un kill switch qui suspendrait tout par défaut
/// n'ajouterait aucune protection et masquerait, le jour du branchement, la
/// différence entre « suspendu par décision » et « suspendu faute de réponse ».
///
/// L'implémentation réelle, elle, doit rendre `.everything` sur erreur de
/// lecture — c'est écrit dans le protocole.
public struct ClosedKillSwitch: OperationalKillSwitchProviding {
    public init() {}
    public func activeSuspensions() async -> KillSwitchState { .none }
}

public struct ClosedReceiptAccess: ReceiptAccessProviding {
    public init() {}
    public func receipt(for reference: FinancialReference,
                        variant: ReceiptVariant) async -> Result<SignedReceipt, FinanceError> {
        // Aucun repli : un reçu ne se fabrique pas localement, même dégradé.
        .failure(.capabilityUnavailable)
    }
}

/// Valeur par défaut du relevé.
///
/// **BACKEND CONTRACT REQUIRED** — `GET /v1/accounts/{id}/transactions`.
///
/// Échoue plutôt que de rendre une page vide. Un relevé vide se lit « vous
/// n'avez fait aucune opération » ; c'est une affirmation, et elle est fausse.
/// L'absence de service doit se dire comme telle.
/// Valeur par défaut des sources de financement.
///
/// **BACKEND CONTRACT REQUIRED** — `GET /v1/funding-sources`.
///
/// Rend une liste vide plutôt qu'une erreur : n'avoir aucune source à proposer
/// est un état normal — compte neuf, aucune carte enregistrée — et l'écran sait
/// le dire. Le backend choisira alors la source par défaut.
public struct ClosedFundingSources: FundingSourceProviding {
    public init() {}
    public func sources(for currency: String) async -> Result<[FundingSource], FinanceError> {
        .success([])
    }
}

public struct ClosedTransactionHistory: TransactionHistoryProviding {
    public init() {}
    public func history(cursor: String?,
                        limit: Int) async -> Result<TransactionHistoryPage, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedTopUp: TopUpOrdering {
    public init() {}
    public func catalog(for msisdn: String) async -> Result<[TopUpProduct], FinanceError> { .success([]) }
    public func order(_ request: TopUpOrderRequest,
                      idempotency: IdempotencyContext) async -> Result<TopUpOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func requery(_ reference: FinancialReference) async -> Result<TopUpOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Valeur par défaut de `disputes`.
///
/// **BACKEND CONTRACT REQUIRED** — `POST /v1/disputes`.
///
/// Le dépôt échoue, mais le **préremplissage fonctionne** : c'est du calcul
/// local sur des données que le client possède déjà. L'écran peut donc être
/// construit et éprouvé avant que le backend existe.
public struct ClosedDisputeFiling: DisputeFiling {
    public init() {}
    public func file(_ draft: DisputeDraft,
                     idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func allowedEvidence(for reason: DisputeReason) async -> Result<[EvidenceKind], FinanceError> {
        // Aucune preuve acceptée sans contrat : le client ne décide pas de ce
        // qui constitue une preuve recevable.
        .success([])
    }
}

/// Valeur par défaut de `qrResolver`.
///
/// **BACKEND CONTRACT REQUIRED** — `POST /v1/qr/resolve`.
///
/// Refuse toute résolution. C'est ce qui rend la règle « aucun QR n'est
/// exécutable sans résolution serveur » vraie **par conception** et non plus par
/// absence de scanner : le scanner peut exister, rien ne s'exécutera.
public struct ClosedQRResolver: QRResolving {
    public init() {}
    public func resolve(payload: String, nonce: String) async -> Result<ResolvedQR, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Valeur par défaut de `transferQuoting`.
///
/// **BACKEND CONTRACT REQUIRED** — `POST /v1/transfers/quote`.
///
/// Refuse d'émettre un devis. Le client ne peut pas en fabriquer un : il faudrait
/// inventer des frais et un taux, c'est-à-dire exactement le calcul financier
/// local que l'architecture interdit.
public struct ClosedTransferQuoting: TransferQuoting {
    public init() {}
    public func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Valeur par défaut de `moneyRequests`.
///
/// **BACKEND CONTRACT REQUIRED** — `POST /v1/requests`.
///
/// Rend la politique **fermée** plutôt qu'une erreur : la surface doit pouvoir
/// afficher pourquoi elle est fermée, et un échec technique ne dirait pas la
/// même chose à l'utilisateur qu'une borne atteinte.
public struct ClosedMoneyRequestService: MoneyRequestCreating {
    public init() {}

    public func policy(towards recipientID: String) async -> Result<MoneyRequestPolicy, FinanceError> {
        .success(.closed)
    }

    public func createRequest(
        _ draft: MoneyRequestDraft,
        idempotency: IdempotencyContext
    ) async -> Result<FinancialReference, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func remind(_ reference: FinancialReference,
                       idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func revoke(_ reference: FinancialReference,
                       idempotency: IdempotencyContext) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Valeur par défaut de `executionPermits`.
///
/// **BACKEND CONTRACT REQUIRED** — `POST /execution-permits`.
///
/// Refuse d'émettre avec `capabilityUnavailable` : ce n'est ni une expiration ni
/// une consommation, et présenter l'absence de contrat comme l'un des deux
/// enverrait l'utilisateur reprendre une opération qui n'a jamais pu commencer.
public struct ClosedExecutionPermitIssuer: ExecutionPermitIssuing {
    public init() {}

    public func issue(
        for snapshot: ConfirmationSnapshot,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<ExecutionPermit, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

public struct ClosedRecipientResolver: RecipientResolving {
    public init() {}
    public func resolve(_ input: RecipientInput) async -> Result<ResolvedRecipient, FinanceError> {
        .failure(.recipientUnresolved(reason: .undetermined))
    }
}
