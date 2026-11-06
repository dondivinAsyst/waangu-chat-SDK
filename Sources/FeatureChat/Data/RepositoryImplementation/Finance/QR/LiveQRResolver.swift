//
//  LiveQRResolver.swift
//  FeatureChat
//
//  Phase 5.2 — lire un QR (INTEGRATION_CHAT_FINANCE.md §5.2).
//

import Foundation
import WaanguCoreKit

/// `POST /qr/parse` : **lecture seule**. Le QR ne paie rien — il désigne un
/// point d'acceptation, que le payeur confirme ensuite par devis et execute.
///
/// La forme de la réponse n'est pas publiée par le contrat : elle est appelée
/// pour de vrai et journalisée en DEBUG (`[FinanceQR]`), comme le catalogue
/// facturier l'a été, puis cartographiée une fois lue. D'ici là l'écran dit
/// « indisponible » — jamais un QR interprété par l'app, ce que le contrat
/// interdit (« la charge brute, **jamais interprétée** »).
struct LiveQRResolver: QRResolving {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    /// Prepare des opérations quotées — le même que facture et recharge.
    var quoting: LiveQuotedOperations? = nil
    var deviceID: @Sendable () -> String = { "" }

    var providesQuotes: Bool { quoting != nil }

    /// `POST /qr/prepare` — la charge du code, telle quelle. Rien n'est débité :
    /// le devis se confirme, puis part sur `/qr/execute`.
    func quotePayment(payload: String, conversationID: String?,
                      idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        guard let quoting else { return .failure(.capabilityUnavailable) }
        var body: [String: Any] = ["payload": payload, "deviceId": deviceID()]
        if let conversationID, !conversationID.isEmpty { body["conversationId"] = conversationID }
        return await quoting.prepare(.qr, body: body, idempotency: idempotency)
    }

    func resolve(payload: String, nonce: String) async -> Result<ResolvedQR, FinanceError> {
        switch await FinanceCoreError.capture({
            try await dataSource.parseQR(ParseQRRequest(payload: payload, nonce: nonce))
        }) {
        case .failure(let error):
            // `CF_042` QR invalide, `CF_043` nonce rejoué.
            #if DEBUG
            print("[FinanceQR] parse failed: \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let raw):
            #if DEBUG
            print("[FinanceQR] parse raw data: \(LiveBillPaying.describe(raw))")
            #endif
            return .failure(.providerUnavailable)
        }
    }
}
