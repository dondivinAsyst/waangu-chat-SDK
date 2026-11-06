//
//  ChatDependencyOverrides.swift
//  WaanguChatSDK
//
//  Values a host supplies in place of the ones the facade builds (SDK plan, step 1.9, parity).
//

import Foundation
import WaanguCoreKit
import WaanguFeatureChat

/// Replaces, one by one, what `WaanguChat` would otherwise use for finance and security.
///
/// Every field is optional and `nil` means "use the facade's choice": the live Chat Core service
/// when payments are enabled and one exists, otherwise the closed one. A host that does not need
/// this passes nothing. The Waangu app uses it to plug in its simulated finance backend in debug
/// builds and its security stand-ins.
///
/// A value given here always wins over the live service.
public struct ChatDependencyOverrides {

    /// The host's wallet use cases. Chat reads the balance from them. Without them the balance
    /// reads as unavailable.
    public var sharedFeatureUsecases: (any SharedFeatureUsecasesProtocol)?

    // Security
    public var auditEmitter: (any FinancialAuditEmitting)?
    public var tokenRotation: (any RefreshTokenRotating)?
    public var attestationVerifier: (any DeviceAttestationVerifying)?

    // Finance, services that also have a live version
    public var paymentConfirmationGuard: (any PaymentConfirmationGuardProtocol)?
    public var financeAPIClient: (any FinanceAPIClientProtocol)?
    public var financeCapabilities: (any FinanceCapabilityProviding)?
    public var idempotencyPreserver: (any IdempotencyKeyPreserving)?
    public var recipientResolver: (any RecipientResolving)?
    public var executionPermits: (any ExecutionPermitIssuing)?
    public var financeCatalog: (any ChatFinanceCatalogProviding)?
    public var moneyRequests: (any MoneyRequestCreating)?
    public var transferQuoting: (any TransferQuoting)?
    public var qrResolver: (any QRResolving)?
    public var merchantInvoices: (any InvoiceProviding)?
    public var splitBills: (any SplitBillManaging)?
    public var disputes: (any DisputeFiling)?
    public var cashIn: (any CashInInitiating)?
    public var cashOut: (any CashOutIssuing)?
    public var bills: (any BillPaying)?
    public var billFieldValidator: BillFieldValidating?
    public var topUp: (any TopUpOrdering)?
    public var receipts: (any ReceiptAccessProviding)?
    public var killSwitch: (any OperationalKillSwitchProviding)?
    public var financialObjectPersistence: (any FinancialObjectPersisting)?
    public var capabilityGates: (any FinancialCapabilityGateProviding)?
    public var financeSession: (any FinanceSessionProviding)?
    public var stepUpAuthenticator: (any StepUpAuthenticating)?
    public var moneyRequestResponder: (any MoneyRequestResponding)?
    public var reversals: (any OperationReversing)?
    public var financialTranslator: (any FinancialTranslating)?

    // Finance, services with no live version
    public var qrPresenter: (any QRPresenting)?
    public var merchantProfiles: (any MerchantProfileProviding)?
    public var commerce: (any CommerceOrdering)?
    public var remoteForms: (any RemoteFormProviding)?
    public var support: (any SupportCaseOpening)?
    public var paymentLinks: (any PaymentLinkResolving)?
    public var cards: (any CardManaging)?
    public var cardTransactions: (any CardTransactionProviding)?
    public var proximityPayments: (any ProximityPaymentSessioning)?
    public var campaigns: (any CampaignManaging)?
    public var nativeApps: (any NativeAppObjectProviding)?
    public var reconciliation: (any ReconciliationProviding)?
    public var transactionHistory: (any TransactionHistoryProviding)?
    public var fundingSources: (any FundingSourceProviding)?
    public var financeBalanceOverride: (any GetBalanceUseCaseProtocol)?
    public var mandates: (any MandateManaging)?
    public var remittance: (any RemittanceSending)?
    public var fx: (any FXConverting)?
    public var credit: (any CreditLending)?
    public var savings: (any SavingsManaging)?
    public var investment: (any InvestmentTrading)?
    public var pfm: (any PersonalFinanceProviding)?

    public init() {}
}
