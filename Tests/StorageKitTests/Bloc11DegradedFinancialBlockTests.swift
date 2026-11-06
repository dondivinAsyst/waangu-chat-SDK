import Testing
import Foundation
@testable import WaanguStorageKit

/// Aucune action financière en mode dégradé ou lecture seule — Waangu 360 §7.
///
/// `DegradedModeGuard.shared` est un singleton : la suite est sérialisée et
/// remet le mode à `normal` après chaque cas, pour ne pas fuir vers d'autres tests.
@Suite("Bloc 11 — blocage financier hors ligne / dégradé", .serialized)
struct Bloc11DegradedFinancialBlockTests {

    private let blockedModes: [DegradedModeGuard.SystemMode] = [.degraded, .readOnly]

    private func throwsBlocked(_ body: () async throws -> Void) async -> Bool {
        do { try await body(); return false } catch { return true }
    }

    @Test("Paiement, carte, NFC, QR et écriture fintech sont refusés hors mode normal")
    func financialActionsBlockedWhenNotNormal() async {
        let guardian = DegradedModeGuard.shared
        for mode in blockedModes {
            await guardian.setMode(mode)
            #expect(await throwsBlocked { try await guardian.validatePaymentOperation() }, "payment \(mode)")
            #expect(await throwsBlocked { try await guardian.validateCardOperation() }, "card \(mode)")
            #expect(await throwsBlocked { try await guardian.validateNFCOperation() }, "nfc \(mode)")
            #expect(await throwsBlocked { try await guardian.validateQROperation() }, "qr \(mode)")
            #expect(await throwsBlocked { try await guardian.validateFintechWrite() }, "fintech \(mode)")
        }
        await guardian.setMode(.normal)
    }

    @Test("Les mêmes actions passent en mode normal")
    func financialActionsAllowedWhenNormal() async throws {
        let guardian = DegradedModeGuard.shared
        await guardian.setMode(.normal)
        try await guardian.validatePaymentOperation()
        try await guardian.validateCardOperation()
        try await guardian.validateNFCOperation()
        try await guardian.validateQROperation()
        try await guardian.validateFintechWrite()
    }

    @Test("Le refus de paiement porte l'erreur dédiée, pas une erreur générique")
    func paymentRefusalIsSpecific() async {
        let guardian = DegradedModeGuard.shared
        await guardian.setMode(.degraded)
        do {
            try await guardian.validatePaymentOperation()
            Issue.record("le paiement aurait dû être refusé")
        } catch let error as DegradedModeGuard.DegradedError {
            if case .paymentBlockedInDegradedMode = error {} else {
                Issue.record("erreur inattendue : \(error)")
            }
        } catch {
            Issue.record("erreur de mauvais type : \(error)")
        }
        await guardian.setMode(.normal)
    }

    @Test("L'initiation de paiement est une opération critique")
    func paymentInitiationIsCritical() async {
        #expect(await DegradedModeGuard.shared.isCriticalOperation("payment_initiation"))
    }
}
