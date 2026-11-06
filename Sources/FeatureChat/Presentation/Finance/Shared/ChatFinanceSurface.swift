//
//  ChatFinanceSurface.swift
//  FeatureChat
//
//  Ce dont une conversation a besoin pour proposer de la finance.
//

import Foundation
import WaanguCoreKit

/// Faisceau de dépendances financières remis aux vues de conversation.
///
/// Un seul paramètre plutôt que quatre enfilés à travers cinq fichiers. Chaque
/// chapitre du Bloc 3 ajoute un service ici, pas une ligne dans chaque
/// constructeur de la chaîne — c'est ce qui rend le chapitre suivant moins cher
/// que le précédent.
///
/// Les vues ne reçoivent toujours que des protocoles : ce faisceau ne donne
/// accès ni à `ChatDependencies`, ni au graphe complet.
public struct ChatFinanceSurface: Sendable {

    public let catalog: any ChatFinanceCatalogProviding
    public let recipientResolver: any RecipientResolving
    public let moneyRequests: any MoneyRequestCreating
    /// Payer, refuser, relancer une demande — voir `MoneyRequestResponding`.
    public let requestResponder: (any MoneyRequestResponding)?
    /// Le PIN du portefeuille, repli de Face ID — vérifié par le serveur.
    public let pinVerifier: any StepUpPINVerifying
    /// Rembourser ou demander l'extourne d'une opération faite.
    public let reversals: any OperationReversing
    public let transferQuoting: any TransferQuoting
    public let qrResolver: any QRResolving
    /// Émission du QR que l'utilisateur présente pour être payé.
    public let qrPresenter: any QRPresenting
    /// Profil marchand et paiement marchand — chapitre 7.
    public let merchantProfiles: any MerchantProfileProviding
    /// Catalogue, panier, commandes, après-vente — chapitre 7.
    public let commerce: any CommerceOrdering
    /// Formulaires dont le backend décide de la forme — chapitre 7.
    public let remoteForms: any RemoteFormProviding
    /// Ouverture d'un dossier de support corrélé — chapitre 7.
    public let support: any SupportCaseOpening
    /// Factures marchandes — chapitre 46.
    public let merchantInvoices: any InvoiceProviding
    /// Liens de paiement — chapitre 46.2.
    public let paymentLinks: any PaymentLinkResolving
    /// Cartes — chapitre 48.
    public let cards: any CardManaging
    /// Transactions cartes, 3DS, contestations — chapitre 49.
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
    /// Identifiant de l'utilisateur courant, pour distinguer sa part
    /// de celles des autres et appliquer la portée de confidentialité.
    public let currentUserID: String
    public let cashIn: any CashInInitiating
    public let cashOut: any CashOutIssuing
    public let bills: any BillPaying
    public let billFieldValidator: BillFieldValidating?
    public let topUp: any TopUpOrdering
    public let disputes: any DisputeFiling
    public let receipts: any ReceiptAccessProviding
    /// Relevé des opérations du compte — écran « Mon portefeuille ».
    public let transactionHistory: any TransactionHistoryProviding

    /// Lecture du solde du compte.
    ///
    /// C'est le contrat partagé `GetBalanceUseCase`, qui préexiste — la même
    /// instance que celle servie au reste de l'application, transportée ici et
    /// non redéclarée. Le faisceau ne s'approprie pas le chiffre : il évite
    /// seulement de le faire descendre à travers six constructeurs pour
    /// atteindre les deux vues qui l'affichent.
    public let balance: any GetBalanceUseCaseProtocol

    /// Sources de financement proposées au moment de payer.
    public let fundingSources: any FundingSourceProviding

    /// Clés d'idempotence des écrans — une instance par session, puisque la
    /// surface elle-même est mémorisée par session.
    public let operationKeys: FinanceOperationKeys

    /// Le brouillon lu par le Hub, en attente du parcours qu'il ouvre (§2.2).
    public let textDrafts: FinanceTextDraftInbox

    /// Magasin des objets financiers, là où la réconciliation regarde.
    ///
    /// Porté par la surface et non plus seulement posé par la salle de
    /// conversation : ouverts depuis les Réglages, les parcours n'avaient aucun
    /// lecteur, et une issue ambiguë — ou une opération tuée en vol — n'était
    /// inscrite nulle part.
    public let objectReader: (any FinancialObjectUseCasesProtocol)?
    public let mandates: any MandateManaging
    public let killSwitch: any OperationalKillSwitchProviding
    /// Satisfait les politiques de step-up exigées par le backend.
    public let stepUp: any StepUpAuthenticating

    // ── Bloc 5 ───────────────────────────────────────────────
    public let capabilityGates: any FinancialCapabilityGateProviding
    /// État de session Chat Core. `nil` ⇒ aucun bandeau de session.
    public let financeSession: (any FinanceSessionProviding)?
    public let remittance: any RemittanceSending
    public let fx: any FXConverting
    public let credit: any CreditLending
    public let savings: any SavingsManaging
    public let investment: any InvestmentTrading
    public let pfm: any PersonalFinanceProviding
    /// Traduction d'un texte financier — la note d'une carte, par exemple.
    public let translator: any FinancialTranslating
    /// Filtre d'injection de l'app, appliqué à ce que l'on écrit à Waangu Copilot.
    /// `nil` ⇒ Waangu Copilot n'accepte pas de texte libre, seulement ses outils.
    public let promptFilter: (any PromptInjectionFilterProtocol)?
    public let sendMoney: SendMoneyUseCase
    /// Invitation des participants d'un partage, puis annonce du partage dans
    /// la conversation de chacun.
    public let splitSharing: any ShareSplitBillUseCaseProtocol

    /// Identifiant d'appareil, pour les clés d'idempotence.
    ///
    /// Sans lui, deux appareils pourraient produire la même clé pour deux
    /// opérations distinctes — exactement ce que la clé doit empêcher.
    public let deviceID: String

    public init(
        catalog: any ChatFinanceCatalogProviding,
        recipientResolver: any RecipientResolving,
        moneyRequests: any MoneyRequestCreating,
        transferQuoting: any TransferQuoting,
        qrResolver: any QRResolving,
        qrPresenter: any QRPresenting,
        merchantProfiles: any MerchantProfileProviding,
        commerce: any CommerceOrdering,
        remoteForms: any RemoteFormProviding,
        support: any SupportCaseOpening,
        merchantInvoices: any InvoiceProviding,
        paymentLinks: any PaymentLinkResolving,
        cards: any CardManaging,
        cardTransactions: any CardTransactionProviding,
        splitBills: any SplitBillManaging,
        proximityPayments: any ProximityPaymentSessioning,
        campaigns: any CampaignManaging,
        nativeApps: any NativeAppObjectProviding,
        reconciliation: any ReconciliationProviding,
        currentUserID: String,
        cashIn: any CashInInitiating,
        cashOut: any CashOutIssuing,
        bills: any BillPaying,
        billFieldValidator: BillFieldValidating? = nil,
        topUp: any TopUpOrdering,
        disputes: any DisputeFiling,
        receipts: any ReceiptAccessProviding,
        transactionHistory: any TransactionHistoryProviding,
        balance: any GetBalanceUseCaseProtocol,
        fundingSources: any FundingSourceProviding,
        operationKeys: FinanceOperationKeys = FinanceOperationKeys(),
        textDrafts: FinanceTextDraftInbox = FinanceTextDraftInbox(),
        objectReader: (any FinancialObjectUseCasesProtocol)? = nil,
        mandates: any MandateManaging,
        killSwitch: any OperationalKillSwitchProviding,
        stepUp: any StepUpAuthenticating,
        capabilityGates: any FinancialCapabilityGateProviding,
        financeSession: (any FinanceSessionProviding)? = nil,
        remittance: any RemittanceSending,
        fx: any FXConverting,
        credit: any CreditLending,
        savings: any SavingsManaging,
        investment: any InvestmentTrading,
        pfm: any PersonalFinanceProviding,
        translator: any FinancialTranslating = ClosedFinancialTranslator(),
        promptFilter: (any PromptInjectionFilterProtocol)? = nil,
        sendMoney: SendMoneyUseCase,
        splitSharing: any ShareSplitBillUseCaseProtocol,
        deviceID: String,
        requestResponder: (any MoneyRequestResponding)? = nil,
        pinVerifier: any StepUpPINVerifying = UnavailableStepUpPINVerifier(),
        reversals: any OperationReversing = ClosedOperationReversing()
    ) {
        self.catalog = catalog
        self.recipientResolver = recipientResolver
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
        self.currentUserID = currentUserID
        self.cashIn = cashIn
        self.cashOut = cashOut
        self.bills = bills
        self.billFieldValidator = billFieldValidator
        self.topUp = topUp
        self.disputes = disputes
        self.receipts = receipts
        self.transactionHistory = transactionHistory
        self.balance = balance
        self.fundingSources = fundingSources
        self.operationKeys = operationKeys
        self.textDrafts = textDrafts
        self.objectReader = objectReader
        self.mandates = mandates
        self.killSwitch = killSwitch
        self.stepUp = stepUp
        self.capabilityGates = capabilityGates
        self.financeSession = financeSession
        self.remittance = remittance
        self.fx = fx
        self.credit = credit
        self.savings = savings
        self.investment = investment
        self.pfm = pfm
        self.translator = translator
        self.promptFilter = promptFilter
        self.sendMoney = sendMoney
        self.splitSharing = splitSharing
        self.deviceID = deviceID
        self.requestResponder = requestResponder
        self.pinVerifier = pinVerifier
        self.reversals = reversals
    }
}
