//
//  LiveOperationReversal.swift
//  FeatureChat
//
//  Remboursement et extourne servis par Chat Core — Phase 10.
//

import Foundation
import WaanguCoreKit

/// `POST /refund` rend un devis, confirmé ensuite par le chemin de Send Money ;
/// `POST /reversal/request` n'est qu'une demande — Finance exécute.
struct LiveOperationReversal: OperationReversing {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let quoting: LiveQuotedOperations
    let deviceID: @Sendable () -> String

    /// Corps `RefundBody` : `originalIntentRef`, `conversationId`, `amountMinor`,
    /// `deviceId` ; la clé d'idempotence s'y ajoute.
    func quoteRefund(of reference: FinancialReference, amount: Decimal, currency: String,
                     conversationID: String?,
                     idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        var body: [String: Any] = [
            "originalIntentRef": reference.id,
            "amountMinor": LiveSendMoney.minorUnits(amount, currency: currency),
            "deviceId": deviceID()
        ]
        if let conversationID, !conversationID.isEmpty { body["conversationId"] = conversationID }
        return await quoting.prepare(.refund, body: body, idempotency: idempotency)
    }

    func requestReversal(of reference: FinancialReference, conversationID: String?,
                         reason: String) async -> Result<ReversalRequested, FinanceError> {
        // Même porte que toute écriture : session, lecture seule, droits.
        if let refusal = await quoting.writeRefusal(for: .sendMoney) { return .failure(refusal) }
        let request = CancelIntentRequest(financialIntentRef: reference.id,
                                          conversationId: conversationID.flatMap { $0.isEmpty ? nil : $0 },
                                          reason: reason)
        switch await FinanceCoreError.capture({
            try await dataSource.requestReversal(request, correlationID: reference.correlationID)
        }) {
        case .failure(let error):
            return .failure(error.financeError)
        case .success(let dto):
            return .success(ReversalRequested(originalIntentRef: dto.originalIntentRef ?? reference.id,
                                              status: dto.status ?? "", message: dto.message))
        }
    }
}
