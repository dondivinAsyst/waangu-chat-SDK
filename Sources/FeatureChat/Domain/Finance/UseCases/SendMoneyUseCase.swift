//
//  SendMoneyUseCase.swift
//  FeatureChat
//
//  La séquence de confirmation du chapitre 18.4 — Bloc 3.
//

import Foundation
import CryptoKit
import WaanguCoreKit

/// Orchestre l'envoi d'argent, de l'accord de l'utilisateur à l'exécution.
///
/// **La valeur de ce type est l'ordre des étapes, pas leur contenu.** Le Bloc 1
/// avait la clé d'idempotence, le Bloc 2 le snapshot et le permis ; ce qui
/// manquait était le rafraîchissement entre l'aperçu et l'exécution. Sans lui,
/// les scénarios 13 à 16 — bénéficiaire, frais, FX et conformité modifiés entre
/// les deux — étaient indétectables.
public struct SendMoneyUseCase: Sendable {

    private let quoting: any TransferQuoting
    private let permits: any ExecutionPermitIssuing
    private let client: (any FinanceAPIClientProtocol)?
    private let preserver: (any IdempotencyKeyPreserving)?
    private let logger: any AppLoggerProtocol

    /// Bloc 9, §25 — audit-first. Nommé `auditEmitter` et non `audit` : `audit`
    /// entre en collision avec une fonction C du système, et le compilateur
    /// résout alors vers elle avec un message peu parlant.
    private let auditEmitter: any FinancialAuditEmitting

    public init(
        quoting: any TransferQuoting,
        permits: any ExecutionPermitIssuing,
        client: (any FinanceAPIClientProtocol)?,
        preserver: (any IdempotencyKeyPreserving)?,
        logger: any AppLoggerProtocol,
        audit: any FinancialAuditEmitting = UnavailableAuditEmitter()
    ) {
        self.quoting = quoting
        self.permits = permits
        self.client = client
        self.preserver = preserver
        self.logger = logger
        self.auditEmitter = audit
    }

    // MARK: - Résultat

    public enum Outcome: Sendable, Equatable {
        case executed(FinancialReference)
        /// Les conditions ont bougé. Porte les champs concernés pour que
        /// l'interface dise *quoi* a changé, et non « veuillez réessayer ».
        case needsNewAgreement(fields: [DecisionField], fresh: TransferQuote)
        case failed(FinanceError)
        /// Le serveur a refusé, et l'a dit : **rien n'a été exécuté**. Distinct
        /// de `failed`, dont certaines causes laissent l'issue inconnue.
        case refused(FinanceError)
    }

    // MARK: - Confirmation

    /// Exécute l'ordre après avoir vérifié que rien n'a bougé.
    ///
    /// - Parameter agreed: l'aperçu que l'utilisateur a réellement accepté.
    /// - Parameter attestation: la preuve de step-up, si le backend l'exigeait.
    public func confirm(
        agreed: TransferQuote,
        recipientID: String,
        operationID: String,
        idempotency: IdempotencyContext,
        attestation: StepUpAttestation?,
        beforeExecution: (@Sendable (_ executing: TransferQuote) async -> Void)? = nil
    ) async -> Outcome {

        // 1. Péremption. Contrôle qui peut enfin se déclencher — `expiresAt`
        //    est obligatoire sur `TransferQuote`.
        guard !agreed.isExpired() else {
            return .failed(.expired)
        }

        // 2-4. Rafraîchissement : devis, frais, taux, bénéficiaire, conformité.
        //      Un seul appel les rapporte tous, parce qu'ils forment un état
        //      cohérent : les lire séparément laisserait combiner des valeurs
        //      qui n'ont jamais coexisté côté serveur.
        let refreshed: TransferQuote
        switch await quoting.refreshQuote(agreed) {
        case .success(let fresh): refreshed = fresh
        case .failure(let error): return .failed(error)
        }

        // Le devis rafraîchi peut lui-même être déjà périmé si le backend en a
        // raccourci la validité.
        guard !refreshed.isExpired() else { return .failed(.expired) }

        // 5. Divergence. Aucun champ décisionnel n'a le droit d'avoir bougé :
        //    l'utilisateur n'a pas consenti à « environ ce montant ».
        let before = agreed.snapshot(recipientID: recipientID)
        let after = refreshed.snapshot(recipientID: recipientID)
        let divergences = before.divergences(from: after)
        guard divergences.isEmpty else {
            await log("send_money", "conditions_changed(\(divergences.map(\.rawValue).joined(separator: ",")))")
            return .needsNewAgreement(fields: divergences, fresh: refreshed)
        }

        // 6. La conformité doit autoriser l'exécution — vérifiée sur l'état
        //    **rafraîchi**, pas sur celui de l'aperçu.
        guard refreshed.complianceState.allowsExecution else {
            return .failed(.complianceBlocked(displayReason: nil))
        }

        // 7. Permis d'exécution, lié à l'empreinte de ce qui a été accepté.
        let permit: ExecutionPermit
        switch await permits.issue(for: after, idempotency: idempotency, stepUp: attestation) {
        case .success(let issued): permit = issued
        case .failure(let error):  return .failed(error)
        }

        guard permit.authorizes(after) else {
            // Un permis qui n'autorise pas l'aperçu qu'il vient d'être demandé
            // pour est une incohérence backend, pas une condition d'exécution.
            return .failed(.executionPermitExpired)
        }

        // 8. Exécution, sous la clé d'origine. La clé n'est jamais neuve ici :
        //    l'intention n'a pas changé, seule sa tentative.
        guard let client else { return .failed(.capabilityUnavailable) }

        do {
            try await preserver?.assertSameKey(
                operationID: operationID,
                providedKey: idempotency.key
            )
        } catch {
            return .failed(.duplicate)
        }

        // Inscription avant soumission : dernier instant où l'argent n'a
        // certainement pas bougé. Plus tôt, un devis périmé ou refusé laisserait
        // une trace d'opération jamais tentée ; plus tard, un kill pendant
        // l'appel ne laisserait rien à reprendre.
        await beforeExecution?(refreshed)

        do {
            let envelope = try await client.confirmPaymentIntent(
                reference: refreshed.reference,
                idempotency: idempotency.nextAttempt(),
                stepUp: attestation
            )

            // 9. Consommer le permis **après** l'exécution : le consommer avant
            //    perdrait la trace si l'exécution échouait, et le rejeu
            //    deviendrait indétectable.
            _ = await permits.consume(permit)

            // Bloc 9, §25 — le fait est consigné **après** l'exécution, et son
            // échec ne remonte pas. Un audit injoignable est un incident
            // d'observabilité ; le transformer en échec dirait à l'utilisateur
            // que son virement a raté alors qu'il est parti.
            await emitAudit(reference: refreshed.reference, snapshot: after)

            if envelope.status.isTerminal {
                await preserver?.release(operationID: operationID)
            }

            return .executed(refreshed.reference)

        } catch let refusal as FinanceServerRefusal {
            await log("send_money refused", refusal.error.technicalDetail)
            return .refused(refusal.error)
        } catch let error as FinanceError {
            await log("send_money", error.technicalDetail)
            return .failed(error)
        } catch {
            // Tout échec non typé après soumission est ambigu : ni échec, ni
            // succès. La réconciliation tranchera.
            return .failed(.timeoutUnknown)
        }
    }

    /// Consigne un virement exécuté.
    ///
    /// Aucun montant, aucun bénéficiaire : l'identifiant d'objet est **haché**,
    /// comme le veut le §5. Un journal d'audit qui fuit aggrave l'incident qu'il
    /// documente.
    private func emitAudit(reference: FinancialReference, snapshot: ConfirmationSnapshot) async {
        let event = FinancialAuditEvent(
            action: .created,
            category: .payment,
            actorID: "self",
            actorType: "user",
            resourceIDHash: Self.hashed(reference.id),
            correlationID: reference.correlationID,
            metadata: ["decision_hash": snapshot.decisionHash]
        )

        if case .failure(let error) = await auditEmitter.emit(event) {
            await log("audit", "emit_failed(\(error))")
        }
    }

    /// SHA-256 hexadécimal, en minuscules.
    private static func hashed(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func log(_ operation: String, _ detail: String) async {
        await logger.log("Finance — \(operation) \(detail)", level: .warning)
    }
}
