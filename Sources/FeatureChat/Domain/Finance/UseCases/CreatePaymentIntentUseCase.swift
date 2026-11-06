//
//  CreatePaymentIntentUseCase.swift
//  FeatureChat
//
//  Émission d'un paiement depuis une conversation — tâche 5.5.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §6.

import Foundation
import WaanguCoreKit

/// Le pipeline complet, de l'intention au suivi.
///
/// Chaque étape est obligatoire et ordonnée. L'ordre n'est pas décoratif :
/// vérifier la capacité après avoir créé l'intention exposerait une opération que
/// l'utilisateur n'aurait pas dû pouvoir déclencher ; demander le step-up avant
/// la confirmation explicite ferait de la biométrie le consentement, alors
/// qu'elle ne fait que le prouver.
public protocol PaymentIntentUseCasesProtocol: Sendable {

    /// Prépare une intention : capacité → risque → devis → objet financier.
    ///
    /// Ne débite rien. L'objet rendu est un devis à présenter à l'utilisateur.
    func prepare(
        _ request: CreatePaymentIntentRequest,
        operationID: String
    ) async -> Result<PreparedPaymentIntent, FinanceError>

    /// Confirme une intention préparée, après consentement explicite.
    ///
    /// - Parameter attestation: preuve de step-up, si `PreparedPaymentIntent`
    ///   en exigeait une. Passer `nil` alors qu'un niveau était requis fait
    ///   échouer l'appel côté client, avant le réseau.
    func confirm(
        _ prepared: PreparedPaymentIntent,
        attestation: StepUpAttestation?
    ) async -> Result<FinancialCardPayload, FinanceError>
}

// MARK: - Intention préparée

/// Devis prêt à être confirmé.
///
/// Porte son `IdempotencyContext` : c'est ce qui garantit que la confirmation,
/// ses retries et une éventuelle reprise après kill d'application parlent tous de
/// la même opération. Le contexte est créé **ici**, une fois, et jamais ailleurs.
public struct PreparedPaymentIntent: Sendable, Equatable {

    /// Identifiant local de l'opération, clé de la préservation d'idempotence.
    public let operationID: String

    /// Objet financier créé par le backend, à sa révision initiale.
    public let reference: FinancialReference

    /// Ce qui sera affiché dans le récapitulatif. Vient du backend, jamais calculé.
    public let card: FinancialCardPayload

    /// Contexte d'idempotence, immuable.
    public let idempotency: IdempotencyContext

    /// Niveau d'authentification exigé, plancher backend élevé par le risque local.
    public let requiredStepUp: StepUpLevel

    /// Fin de validité du devis. Au-delà, il faut recommencer — pas prolonger.
    public let expiresAt: Date?

    public init(
        operationID: String,
        reference: FinancialReference,
        card: FinancialCardPayload,
        idempotency: IdempotencyContext,
        requiredStepUp: StepUpLevel,
        expiresAt: Date?
    ) {
        self.operationID = operationID
        self.reference = reference
        self.card = card
        self.idempotency = idempotency
        self.requiredStepUp = requiredStepUp
        self.expiresAt = expiresAt
    }

    public func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

// MARK: - Implémentation

public struct PaymentIntentUseCases: PaymentIntentUseCasesProtocol {

    private let client: (any FinanceAPIClientProtocol)?
    private let capabilities: any FinanceCapabilityProviding
    private let preserver: any IdempotencyKeyPreserving
    private let riskEvaluator: (any SessionRiskEvaluating)?
    private let store: FinancialObjectStore
    private let deviceID: String
    private let logger: any AppLoggerProtocol

    public init(
        client: (any FinanceAPIClientProtocol)?,
        capabilities: any FinanceCapabilityProviding,
        preserver: any IdempotencyKeyPreserving,
        riskEvaluator: (any SessionRiskEvaluating)?,
        store: FinancialObjectStore,
        deviceID: String,
        logger: any AppLoggerProtocol
    ) {
        self.client = client
        self.capabilities = capabilities
        self.preserver = preserver
        self.riskEvaluator = riskEvaluator
        self.store = store
        self.deviceID = deviceID
        self.logger = logger
    }

    // MARK: Préparation

    public func prepare(
        _ request: CreatePaymentIntentRequest,
        operationID: String
    ) async -> Result<PreparedPaymentIntent, FinanceError> {

        // 1. Capacité. Une capacité fermée n'atteint jamais le réseau.
        let caps = await capabilities.capabilities()
        guard caps.allowsAnyOutgoingOperation else {
            return .failure(.capabilityUnavailable)
        }
        guard let client else { return .failure(.capabilityUnavailable) }

        // 2. Idempotence — créée **avant** le réseau.
        //
        // Si l'application meurt entre l'enregistrement et la réponse, la clé
        // survit et la reprise retrouve l'opération au lieu d'en créer une
        // seconde. La créer après l'appel laisserait cette fenêtre ouverte.
        let context: IdempotencyContext
        if let existing = await preserver.context(for: operationID) {
            context = existing
        } else {
            context = IdempotencyContext.new(deviceID: deviceID)
            do {
                try await preserver.register(operationID: operationID, context: context)
            } catch {
                return .failure(.duplicate)
            }
        }

        // 3. Risque local — ne peut qu'élever l'exigence backend.
        let assessment = await riskEvaluator?.evaluate(
            for: "payment_intent",
            amount: request.amount
        )

        // 4. Devis.
        do {
            let envelope = try await client.createPaymentIntent(request, idempotency: context)

            // La révision appartient au backend. Tant que le contrat #2 ne la
            // rend pas, le devis est affiché comme écho local : il occupe la
            // place de l'objet sans prétendre en connaître la révision, et la
            // première réponse authentique le remplace sans condition.
            let backendRevision = envelope.objectRevision
            let reference = FinancialReference(
                type: request.type,
                id: envelope.id,
                version: backendRevision ?? 0,
                correlationID: context.correlationID
            )

            let card = FinancialCardPayload(
                reference: reference,
                status: envelope.status,
                amount: envelope.amount,
                currency: envelope.currency,
                feeAmount: envelope.feeAmount,
                feeCurrency: envelope.feeCurrency,
                counterpartyName: nil,
                note: envelope.description,
                lastRefreshedAt: Date(),
                // Un devis n'est pas confirmé : rien à vérifier encore.
                verification: .unverified
            )
            if backendRevision != nil {
                await store.apply(card)
            } else {
                await store.applyLocalEcho(card)
            }

            return .success(PreparedPaymentIntent(
                operationID: operationID,
                reference: reference,
                card: card,
                idempotency: context,
                requiredStepUp: StepUpRequirement.effectiveLevel(
                    // Le plancher vient de l'enveloppe backend — GAP-10.
                    //
                    // À défaut, `.biometric` et non `.pin` : sans instruction,
                    // la valeur sûre est la plus exigeante atteignable
                    // localement. Un plancher trop bas laisse passer ; un
                    // plancher trop haut ne coûte qu'un geste.
                    backendRequired: envelope.requiredStepUpLevel ?? .biometric,
                    localAssessment: assessment
                ),
                expiresAt: nil
            ))

        } catch let error as FinanceError {
            await log(reference: nil, "prepare", error)
            return .failure(error)
        } catch {
            return .failure(.timeoutUnknown)
        }
    }

    // MARK: Confirmation

    public func confirm(
        _ prepared: PreparedPaymentIntent,
        attestation: StepUpAttestation?
    ) async -> Result<FinancialCardPayload, FinanceError> {

        guard let client else { return .failure(.capabilityUnavailable) }

        // Devis périmé : parcours complet, jamais de reprise silencieuse. Le
        // montant, le taux et les frais ont pu changer depuis.
        guard !prepared.isExpired() else {
            return .failure(.expired)
        }

        // Le step-up exigé doit être satisfait. Un `nil` ici est une faute du
        // site d'appel, pas une condition d'exécution — on refuse avant le réseau.
        if prepared.requiredStepUp != .none {
            guard let attestation, attestation.level >= prepared.requiredStepUp else {
                return .failure(.forbidden)
            }
        }

        // La clé de la préparation est réutilisée telle quelle.
        do {
            try await preserver.assertSameKey(
                operationID: prepared.operationID,
                providedKey: prepared.idempotency.key
            )
        } catch {
            return .failure(.duplicate)
        }

        do {
            let envelope = try await client.confirmPaymentIntent(
                reference: prepared.reference,
                idempotency: prepared.idempotency.nextAttempt(),
                stepUp: attestation
            )

            // Le backend fait autorité sur la révision — sans exception.
            //
            // Aucune arithmétique ici : avancer d'un cran ferait entrer une
            // révision inventée dans le garde de version, et la vraie révision
            // backend, qui repart de son propre compteur, serait ensuite rejetée
            // comme périmée. La carte resterait figée sur le statut optimiste,
            // y compris quand le backend corrige `processing` en `failed`.
            //
            // Sans révision exploitable, la charge est un écho local : même
            // référence, aucune autorité, remplacée sans condition par la
            // première réponse authentique.
            let backendRevision = envelope.objectRevision
            let reference: FinancialReference
            let isAuthoritative: Bool
            if let backendRevision, backendRevision > prepared.reference.version {
                reference = FinancialReference(
                    type: prepared.reference.type,
                    id: prepared.reference.id,
                    version: backendRevision,
                    correlationID: prepared.idempotency.correlationID
                )
                isAuthoritative = true
            } else {
                reference = prepared.reference
                isAuthoritative = false
            }

            let card = FinancialCardPayload(
                reference: reference,
                status: envelope.status,
                amount: envelope.amount,
                currency: envelope.currency,
                feeAmount: envelope.feeAmount,
                feeCurrency: envelope.feeCurrency,
                counterpartyName: prepared.card.counterpartyName,
                note: envelope.description,
                lastRefreshedAt: Date(),
                verification: .unverified
            )
            if isAuthoritative {
                await store.apply(card)
            } else {
                await store.applyLocalEcho(card)
            }

            // La clé n'est libérée que sur un état **réellement** final. Un objet
            // en `unknown` garde la sienne : la libérer autoriserait une nouvelle
            // tentative sous une clé neuve, donc un second débit.
            if envelope.status.isTerminal {
                await preserver.release(operationID: prepared.operationID)
            }

            return .success(card)

        } catch let refusal as FinanceServerRefusal {
            // Le serveur a répondu et refusé : rien n'a été exécuté. La carte
            // inscrite à la préparation ne correspond à aucune opération, et la
            // garder la ferait revenir à chaque passe de réconciliation. La clé
            // est libérée parce que le refus est établi — une nouvelle tentative
            // ne peut pas doubler un débit qui n'a pas eu lieu.
            await store.discard(prepared.reference)
            await preserver.release(operationID: prepared.operationID)
            await log(reference: prepared.reference, "confirm refused", refusal.error)
            return .failure(refusal.error)
        } catch let error as FinanceError {
            await log(reference: prepared.reference, "confirm", error)
            return .failure(error)
        } catch {
            // Tout échec non typé après soumission est ambigu.
            return .failure(.timeoutUnknown)
        }
    }

    private func log(reference: FinancialReference?, _ op: String, _ error: FinanceError) async {
        let context = reference.map { FinanceLogContext(reference: $0, operation: op) }
            ?? FinanceLogContext(correlationID: CorrelationId(), financialObjectID: nil, operation: op)
        await logger.log("Finance — \(context) error=\(error.technicalDetail)", level: .warning)
    }
}
