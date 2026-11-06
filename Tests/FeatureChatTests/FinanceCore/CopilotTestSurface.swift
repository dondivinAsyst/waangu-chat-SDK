//
//  CopilotTestSurface.swift
//  FeatureChatTests
//
//  Une surface financière pour les tests de Waangu Copilot : les services de
//  Chat Core sur le serveur scripté, tout le reste fermé.
//

import Foundation
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Contacts scriptés, et aucune diffusion.
struct FakeContactsSharing: ShareSplitBillUseCaseProtocol {
    var contacts: [UserContactProps] = []
    func participantCandidates() async -> [UserContactProps] { contacts }
    func share(_ split: SplitBill, correlationID: CorrelationId,
               with participants: [UserContactProps]) async -> SplitBillShareReport {
        SplitBillShareReport(sharedWith: [], failed: [])
    }
}

/// Le solde n'est pas l'objet de ces tests.
struct UnavailableBalance: GetBalanceUseCaseProtocol {
    func execute(forceRefresh: Bool) async -> Result<GetBalance, AppError> { .failure(.noInternetConnection) }
}

/// Compte les élévations demandées — rien ne doit s'exécuter sans elles.
actor StepUpLog {
    private(set) var reasons: [String] = []
    private(set) var levels: [StepUpLevel] = []
    func record(_ reason: String, level: StepUpLevel) { reasons.append(reason); levels.append(level) }
}

struct RecordingStepUp: StepUpAuthenticating {
    let log: StepUpLog
    var cancels = false
    /// Face ID indisponible, verrouillé… : l'erreur que rend l'appareil.
    var failure: StepUpError? = nil

    var currentLevel: StepUpLevel { get async { .none } }
    func elevate(to level: StepUpLevel) async throws -> Bool { !cancels }
    func satisfyStepUp(level: StepUpLevel, reason: String, correlationID: CorrelationId,
                       deviceID: String) async throws -> StepUpAttestation {
        await log.record(reason, level: level)
        if cancels { throw StepUpError.userCancelled }
        if let failure { throw failure }
        return StepUpAttestation(level: level, correlationID: correlationID, deviceID: deviceID)
    }
}

enum CopilotTestSurface {

    /// La surface sur `services`, avec `catalog` à la place du catalogue live
    /// quand un test scripte les outils ou le brouillon.
    static func make(services: FinanceCoreLiveServices,
                     catalog: (any ChatFinanceCatalogProviding)? = nil,
                     contacts: [UserContactProps] = [],
                     stepUp: any StepUpAuthenticating = MockStepUpAuthenticator(),
                     promptFilter: (any PromptInjectionFilterProtocol)? = nil,
                     pinVerifier: any StepUpPINVerifying = UnavailableStepUpPINVerifier(),
                     disputes: (any DisputeFiling)? = nil,
                     objectReader: (any FinancialObjectUseCasesProtocol)? = nil,
                     reversals: (any OperationReversing)? = nil) -> ChatFinanceSurface {
        let registry = MockIdempotencyPreserver()
        return ChatFinanceSurface(
            catalog: catalog ?? services.catalog,
            recipientResolver: services.recipientResolver,
            moneyRequests: services.moneyRequests,
            transferQuoting: services.transferQuoting,
            qrResolver: services.qrResolver,
            qrPresenter: ClosedQRPresenter(),
            merchantProfiles: ClosedMerchantProfileProvider(),
            commerce: ClosedCommerceOrdering(),
            remoteForms: ClosedRemoteFormProvider(),
            support: ClosedSupportCaseOpener(),
            merchantInvoices: services.merchantInvoices,
            paymentLinks: ClosedPaymentLinkResolver(),
            cards: ClosedCardManager(),
            cardTransactions: ClosedCardTransactionProvider(),
            splitBills: services.splitBills,
            proximityPayments: ClosedProximityPaymentSessioning(),
            campaigns: ClosedCampaignManager(),
            nativeApps: ClosedNativeAppObjectProvider(),
            reconciliation: ClosedReconciliationProvider(),
            currentUserID: "usr_me",
            cashIn: services.cashIn,
            cashOut: services.cashOut,
            bills: services.bills,
            topUp: services.topUp,
            disputes: disputes ?? services.disputes,
            receipts: services.receipts,
            transactionHistory: ClosedTransactionHistory(),
            balance: UnavailableBalance(),
            fundingSources: ClosedFundingSources(),
            operationKeys: FinanceOperationKeys(preserver: registry),
            objectReader: objectReader,
            mandates: ClosedMandateManaging(),
            killSwitch: services.killSwitch,
            stepUp: stepUp,
            capabilityGates: services.capabilityGates,
            financeSession: services.session,
            remittance: ClosedRemittance(),
            fx: ClosedFX(),
            credit: ClosedCredit(),
            savings: ClosedSavings(),
            investment: ClosedInvestment(),
            pfm: ClosedPFM(),
            promptFilter: promptFilter,
            sendMoney: SendMoneyUseCase(quoting: services.transferQuoting, permits: services.executionPermits,
                                        client: services.apiClient, preserver: registry, logger: SilentLogger()),
            splitSharing: FakeContactsSharing(contacts: contacts),
            deviceID: "dev_1",
            requestResponder: services.moneyRequestResponder,
            pinVerifier: pinVerifier,
            reversals: reversals ?? services.reversals)
    }

    static func contact(_ name: String, phone: String, userID: String = "usr_x") -> UserContactProps {
        UserContactProps(idContact: "c_" + userID, userId: userID, name: name, avatar: nil, phone: phone,
                         description: "", isBlocked: false)
    }
}
