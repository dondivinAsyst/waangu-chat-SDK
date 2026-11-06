//
//  PaymentConfirmationGuard.swift
//  SecurityKit
//
//  RULE: Le mobile ne peut confirmer aucun paiement
//  All payment confirmations MUST come from backend with rail proof
//

import Foundation
import WaanguCoreKit

/// Vérifie qu'une confirmation présentée comme venant du backend l'est vraiment.
///
/// Le garde ne confirme rien : il refuse d'afficher comme confirmé ce qu'il ne
/// peut pas établir. Quatre contrôles, dans cet ordre :
///
/// 1. **fraîcheur** — une révision antérieure ou égale ne remplace pas l'état courant ;
/// 2. **cohérence** — montant positif, statut réellement final ;
/// 3. **authenticité** — HMAC-SHA256 sur le contenu canonique ;
/// 4. **preuve de rail** — un rail externe a bien confirmé.
///
/// La version précédente de ce fichier se contentait de `signature.count >= 64`
/// et de `amount > 0`, ce qu'une chaîne de 64 caractères arbitraires franchit.
public struct PaymentConfirmationGuard: PaymentConfirmationGuardProtocol {

    private let logger: AppLogger
    private let verifier: any FinancialSignatureVerifying

    /// Exige une preuve de rail pour accepter une confirmation.
    ///
    /// Configurable parce que tous les rails n'en produisent pas encore au même
    /// stade ; par défaut exigée, car c'est la règle
    /// « `pendingExternal → confirmed` requiert une `RailProof` ».
    private let requiresRailProof: Bool

    public init(
        logger: AppLogger,
        verifier: any FinancialSignatureVerifying,
        requiresRailProof: Bool = true
    ) {
        self.logger = logger
        self.verifier = verifier
        self.requiresRailProof = requiresRailProof
    }

    // MARK: - Décision

    public func decide(on confirmation: PaymentConfirmation) async -> PaymentConfirmationDecision {

        // 1. Fraîcheur — avant tout le reste.
        //
        // Une confirmation authentiquement signée mais périmée reste irrecevable :
        // l'appliquer ferait régresser l'affichage. Placé en premier parce qu'une
        // signature valide sur un contenu ancien est exactement ce qu'un rejeu
        // présente.
        if let current = confirmation.currentKnownVersion,
           confirmation.reference.version <= current {
            let rejection = PaymentConfirmationRejection.staleVersion(
                incoming: confirmation.reference.version,
                current: current
            )
            await log("Confirmation périmée rejetée", confirmation, rejection, level: .warning)
            await audit(confirmation, verdict: "rejected", detail: rejection)
            return .rejected(rejection)
        }

        // 2. Cohérence.
        guard confirmation.amount > 0 else {
            await log("Montant invalide", confirmation, .nonPositiveAmount, level: .warning)
            await audit(confirmation, verdict: "rejected", detail: .nonPositiveAmount)
            return .rejected(.nonPositiveAmount)
        }

        guard confirmation.status == .confirmed || confirmation.status == .completed else {
            let rejection = PaymentConfirmationRejection.statusNotFinal(confirmation.status)
            await log("Statut non final", confirmation, rejection, level: .info)
            await audit(confirmation, verdict: "rejected", detail: rejection)
            return .rejected(rejection)
        }

        guard !confirmation.backendSignature.isEmpty else {
            await log("Signature absente", confirmation, .missingSignature, level: .warning)
            await audit(confirmation, verdict: "rejected", detail: .missingSignature)
            return .rejected(.missingSignature)
        }

        // 3. Authenticité.
        let payload = FinancialSignaturePayload(
            confirmation: confirmation,
            idempotencyKey: confirmation.idempotencyKey
        )

        switch await verifier.verify(signature: confirmation.backendSignature, over: payload) {

        case .forged:
            // Signature vérifiable et fausse. Événement de sécurité, pas incident
            // de fonctionnement : quelqu'un a présenté un contenu forgé.
            await log("Signature invalide", confirmation, .unverifiedSignature, level: .critical)
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: [
                    "violation": "forged_payment_signature",
                    "fin_type": confirmation.reference.type.rawValue,
                    "fin_version": String(confirmation.reference.version)
                ]
            )
            await audit(confirmation, verdict: "rejected", detail: .unverifiedSignature)
            return .rejected(.unverifiedSignature)

        case .unverifiable(let reason):
            // Ce client ne peut pas se prononcer — clé absente, contrat backend
            // non livré. Ni acceptation ni accusation : l'objet part en
            // réconciliation et s'affiche en `unknown`.
            await log("Signature non vérifiable (\(reason))", confirmation,
                      .backendContractPending, level: .warning)
            await audit(confirmation, verdict: "undetermined", detail: .backendContractPending)
            return .undetermined(.backendContractPending)

        case .authentic:
            break
        }

        // 4. Preuve de rail.
        if requiresRailProof {
            guard let proof = confirmation.railProof, Self.isUsable(proof) else {
                await log("Preuve de rail absente ou incomplète", confirmation,
                          .missingRailProof, level: .warning)
                // Indéterminé et non rejeté : le backend a bien signé, le rail
                // n'a simplement pas encore rendu sa preuve. Le paiement est
                // peut-être en cours de règlement.
                await audit(confirmation, verdict: "undetermined", detail: .missingRailProof)
                return .undetermined(.missingRailProof)
            }
        }

        await log("Confirmation vérifiée", confirmation, nil, level: .info)
        await audit(confirmation, verdict: "accepted", detail: nil)
        return .accepted
    }

    // MARK: - Interne

    /// Une preuve de rail exploitable identifie un fournisseur et une transaction.
    ///
    /// La signature du rail n'est pas vérifiée ici : elle relève du rail lui-même
    /// et de `RailProofValidator`. Ce garde s'assure seulement qu'elle existe et
    /// qu'elle n'est pas un remplissage vide.
    private static func isUsable(_ proof: RailProof) -> Bool {
        !proof.railProvider.isEmpty
            && !proof.railTransactionId.isEmpty
            && !proof.railSignature.isEmpty
    }

    /// Consigne le verdict dans la piste d'audit.
    ///
    /// **Chaque** décision y passe, pas seulement les refus. Un audit qui ne
    /// contient que les rejets ne permet pas de répondre à la question qui se pose
    /// vraiment après un incident : « qu'est-ce que ce client a accepté, et sur
    /// quelle base ? »
    ///
    /// Ne consigne ni identifiant brut, ni montant, ni contrepartie — seulement
    /// le type, la révision et le motif.
    private func audit(
        _ confirmation: PaymentConfirmation,
        verdict: String,
        detail: PaymentConfirmationRejection?
    ) async {
        var metadata: [String: String] = [
            "guard": "payment_confirmation",
            "verdict": verdict,
            "fin_type": confirmation.reference.type.rawValue,
            "fin_version": String(confirmation.reference.version)
        ]
        if let detail { metadata["reason"] = detail.technicalDetail }

        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: metadata,
            severity: verdict == "accepted" ? .info : .warning
        )
    }

    /// Journalise sans exposer l'identifiant d'objet financier ni le montant.
    private func log(
        _ message: String,
        _ confirmation: PaymentConfirmation,
        _ rejection: PaymentConfirmationRejection?,
        level: LogLevel
    ) async {
        let context = FinanceLogContext(
            reference: confirmation.reference,
            operation: "payment_confirmation_guard"
        )
        let reason = rejection.map { " reason=\($0.technicalDetail)" } ?? ""
        await logger.log("\(message) — \(context)\(reason)", level: level)
    }
}
