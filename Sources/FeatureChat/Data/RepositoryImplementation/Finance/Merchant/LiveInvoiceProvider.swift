//
//  LiveInvoiceProvider.swift
//  FeatureChat
//
//  §5.2 — facture marchande sur Chat Core : inquire → prepare → execute.
//

import Foundation
import WaanguCoreKit

/// `InvoiceProviding` sur Chat Core.
///
/// Le serveur ne rend que **le reste dû et le déjà payé** (`InvoiceOutstanding`) :
/// ni lignes, ni sous-total, ni total. Ce qu'il ne rend pas reste vide — rien
/// n'est recomposé ici. Le paiement suit le contrat §5 : `/invoice/prepare`
/// rend un devis sur le montant **du serveur**, l'execute suit après
/// confirmation, par le chemin de Send Money.
struct LiveInvoiceProvider: InvoiceProviding {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let quoting: LiveQuotedOperations
    let deviceID: @Sendable () -> String

    func invoice(id: String) async -> Result<Invoice, FinanceError> {
        switch await inquire(id) {
        case .success(let outstanding): return .success(Self.invoice(from: outstanding))
        case .failure(let error):       return .failure(error)
        }
    }

    /// Aucune liste au contrat : une facture s'ouvre par sa référence.
    func invoices(cursor: String?) async -> Result<[Invoice], FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// Relue juste avant de payer. Le reste dû est la seule chose qui puisse
    /// bouger sous les yeux de l'utilisateur : s'il a changé, il relit.
    func revalidate(_ snapshot: InvoiceSnapshot) async -> Result<InvoiceVerdict, FinanceError> {
        switch await inquire(snapshot.invoiceID) {
        case .failure(let error):
            return .failure(error)
        case .success(let outstanding):
            let fresh = Self.invoice(from: outstanding)
            if !fresh.state.acceptsPayment {
                return .success(.cancelled(reasonKey: FinanceStrings.invoiceNotPayable))
            }
            if let expiresAt = fresh.expiresAt, Date() >= expiresAt { return .success(.expired) }
            if fresh.amountDue != snapshot.amountDue { return .success(.mutated(.amountChanged, fresh: fresh)) }
            return .success(.unchanged)
        }
    }

    /// **Jamais un débit direct** : le contrat prépare, fait confirmer, puis
    /// exécute (§5, `providesQuotes`).
    func pay(invoiceID: String, snapshot: InvoiceSnapshot, allocation: PaymentAllocation,
             idempotency: IdempotencyContext, stepUp: StepUpAttestation?) async -> Result<Invoice, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    var providesQuotes: Bool { true }

    /// `POST /invoice/prepare`. Pas de montant dans le corps : le serveur prend
    /// le reste dû du Merchant Backend.
    func quote(_ invoice: Invoice, conversationID: String?,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        var body: [String: Any] = ["invoiceRef": invoice.id, "deviceId": deviceID()]
        if !invoice.merchantID.isEmpty { body["merchantId"] = invoice.merchantID }
        if let conversationID, !conversationID.isEmpty { body["conversationId"] = conversationID }
        return await quoting.prepare(.invoice, body: body, idempotency: idempotency)
    }

    // MARK: - Lecture

    private func inquire(_ invoiceRef: String) async -> Result<InvoiceOutstandingDTO, FinanceError> {
        let request = InvoiceInquireRequest(invoiceRef: invoiceRef, merchantId: nil)
        switch await FinanceCoreError.capture({ try await dataSource.inquireInvoice(request) }) {
        case .success(let outstanding): return .success(outstanding)
        case .failure(let error):       return .failure(error.financeError)
        }
    }

    /// La facture telle que le Merchant Backend la décrit — sans ce qu'il ne dit pas.
    static func invoice(from dto: InvoiceOutstandingDTO, now: Date = Date()) -> Invoice {
        let currency = CurrencyCode(code: dto.currency ?? "", exponent: exponent(of: dto.currency ?? ""))
        let merchant = dto.merchantId ?? ""
        return Invoice(
            id: dto.invoiceRef, merchantID: merchant, merchantNameKey: merchant,
            number: dto.invoiceRef, state: state(dto.status), lines: [],
            subtotal: nil, total: nil,
            paidAmount: Money(minorUnits: dto.paidMinor ?? 0, currency: currency),
            amountDue: Money(minorUnits: dto.outstandingMinor ?? 0, currency: currency),
            // Le prepare ne prend pas de montant : tout ou rien.
            allowsPartialPayment: false,
            // Pas de date d'émission au contrat : celle de la lecture.
            issuedAt: now, expiresAt: FinanceCoreDates.parse(dto.expiresAt),
            version: 1,
            // Empreinte des seuls faits rendus — la revalidation compare le reste dû.
            contentHash: [dto.invoiceRef, dto.merchantId ?? "", dto.currency ?? "",
                          String(dto.outstandingMinor ?? 0), String(dto.paidMinor ?? 0),
                          dto.status ?? ""].joined(separator: "|"))
    }

    /// `OPEN` · `PARTIAL` · `PAID` · `VOID`. Un mot inconnu n'est pas payable.
    static func state(_ raw: String?) -> InvoiceState {
        switch raw?.uppercased() {
        case "OPEN":    return .issued
        case "PARTIAL": return .partiallyPaid
        case "PAID":    return .paid
        case "VOID":    return .cancelled
        default:        return .unknown
        }
    }

    /// Exposant ISO 4217 — le même que `FcoCardMapper.amount`.
    static func exponent(of currency: String) -> Int {
        guard !currency.isEmpty else { return 0 }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.maximumFractionDigits
    }
}
