//
//  LiveReceiptAccess.swift
//  FeatureChat
//
//  Phase 10 — reçus servis par Chat Core, signés par Finance.
//

import Foundation
import WaanguCoreKit

/// `ReceiptAccessProviding` sur Chat Core : `POST /receipts/share` rend l'URL
/// signée par Finance ; un reçu pas encore émis l'est d'abord
/// (`POST /receipts/issue`).
///
/// **Un reçu provisoire n'est pas demandé.** Le serveur n'émet de reçu qu'après
/// `COMPLETED` (§10) : en demander un avant, c'est obtenir un document qui dit
/// « payé » trop tôt. L'écran l'annonce comme indisponible.
struct LiveReceiptAccess: ReceiptAccessProviding {

    let dataSource: any RemoteChatFinanceDataSourceProtocol

    func receipt(for reference: FinancialReference,
                 variant: ReceiptVariant) async -> Result<SignedReceipt, FinanceError> {
        guard variant != .provisional else { return .failure(.capabilityUnavailable) }

        let ref = TopUpRefRequest(financialIntentRef: reference.id, conversationId: nil)
        switch await FinanceCoreError.capture({ try await dataSource.shareReceipt(ref) }) {
        case .success(let record):
            return Self.signed(record, variant: variant)
        // Finance absent, réseau coupé : émettre n'y changerait rien.
        case .failure(.transport(let error)):
            return .failure(error)
        case .failure(.business(let code, _)) where code.rawValue == "CF_051":
            return .failure(code.financeError)
        case .failure:
            // Pas encore émis : on l'émet, puis on redemande l'URL.
            let issue = IssueReceiptRequest(financialIntentRef: reference.id,
                                            conversationId: nil, documentBody: nil)
            if case .failure(let error) = await FinanceCoreError.capture({ try await dataSource.issueReceipt(issue) }) {
                return .failure(error.financeError)
            }
            switch await FinanceCoreError.capture({ try await dataSource.shareReceipt(ref) }) {
            case .success(let record): return Self.signed(record, variant: variant)
            case .failure(let error):  return .failure(error.financeError)
            }
        }
    }

    /// `POST /receipt/share` — la carte du reçu dans la conversation. Le reçu est
    /// émis d'abord s'il ne l'est pas ; `receiptRef` vient toujours du serveur.
    func postInConversation(_ reference: FinancialReference,
                            conversationID: String) async -> Result<Void, FinanceError> {
        let ref = TopUpRefRequest(financialIntentRef: reference.id, conversationId: conversationID)
        var receiptRef: String?
        if case .success(let record) = await FinanceCoreError.capture({ try await dataSource.shareReceipt(ref) }) {
            receiptRef = record.receiptRef
        } else {
            let issue = IssueReceiptRequest(financialIntentRef: reference.id,
                                            conversationId: conversationID, documentBody: nil)
            switch await FinanceCoreError.capture({ try await dataSource.issueReceipt(issue) }) {
            case .success(let record): receiptRef = record.receiptRef
            case .failure(let error):  return .failure(error.financeError)
            }
        }
        guard let receiptRef else { return .failure(.providerUnavailable) }
        let card = ReceiptCardShareRequest(financialIntentRef: reference.id, conversationId: conversationID,
                                           receiptRef: receiptRef)
        if case .failure(let error) = await FinanceCoreError.capture({ try await dataSource.postReceiptCard(card) }) {
            return .failure(error.financeError)
        }
        return .success(())
    }

    /// `POST /receipts/verify` — rend le même `ReceiptRecord` ; `CF_045` si le hash diffère.
    func verify(receiptID: String, documentBody: String) async -> Result<Void, FinanceError> {
        let request = VerifyReceiptRequest(receiptRef: receiptID, documentBody: documentBody)
        switch await FinanceCoreError.capture({ try await dataSource.verifyReceipt(request) }) {
        case .success:             return .success(())
        case .failure(let error):  return .failure(error.financeError)
        }
    }

    /// Le reçu tel que Finance l'a signé. Sans URL ni échéance, rien n'est
    /// ouvrable : jamais d'URL reconstruite depuis `storageKey`.
    static func signed(_ record: ReceiptRecordDTO,
                       variant: ReceiptVariant) -> Result<SignedReceipt, FinanceError> {
        guard let text = record.signedUrl, let url = URL(string: text),
              let expiresAt = FinanceCoreDates.parse(record.signedUrlExpiresAt)
        else { return .failure(.providerUnavailable) }
        return .success(SignedReceipt(
            receiptID: record.receiptRef, variant: variant, url: url, expiresAt: expiresAt,
            documentHash: record.sha256 ?? "", version: record.version ?? 1,
            // `/receipts/share` existe pour partager : l'URL rendue l'est.
            isShareable: true))
    }
}
