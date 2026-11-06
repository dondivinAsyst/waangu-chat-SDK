//
//  FinancialObjectUseCases.swift
//  FeatureChat
//
//  Lecture, rafraîchissement et réconciliation des objets financiers —
//  tâches 5.2, 5.3, 5.4.

import Foundation
import WaanguCoreKit

// MARK: - Contrats

public protocol FinancialObjectUseCasesProtocol: Sendable {

    /// État courant connu, sans appel réseau.
    func current(for reference: FinancialReference) async -> FinancialCardPayload?

    /// Force une lecture serveur et applique le résultat sous garde de version.
    @discardableResult
    func refresh(_ reference: FinancialReference) async -> Result<FinancialCardPayload, FinanceError>

    /// Applique une révision reçue d'ailleurs (MQTT, sync, push).
    @discardableResult
    func apply(_ payload: FinancialCardPayload) async -> Bool

    /// Inscrit, **avant** son exécution, une opération qui peut déplacer de
    /// l'argent.
    ///
    /// L'inscription est persistée et marquée ambiguë : si l'application est
    /// tuée pendant l'appel, le lancement suivant la relit et la requête, au
    /// lieu de laisser l'utilisateur refaire l'opération sans savoir que la
    /// première est peut-être passée. La première vérité backend la remplace
    /// sans condition de révision.
    func recordSubmission(_ payload: FinancialCardPayload) async

    /// Oublie une inscription avant soumission que le serveur a refusée.
    ///
    /// Le refus prouve que l'opération n'a pas eu lieu : la laisser inscrite
    /// afficherait une carte incertaine et la ferait relire à chaque passe de
    /// réconciliation.
    func discardSubmission(_ reference: FinancialReference) async

    /// Reprend tous les objets dont l'issue est ambiguë.
    func reconcilePending() async

    /// Requête les objets restaurés du disque au démarrage — lot 2.2.
    func restoreHydrated() async

    /// Objets dont l'issue est ambiguë, sans les reprendre.
    ///
    /// Existe pour que le planificateur puisse appliquer son délai de grâce :
    /// sans cette lecture, il ne peut que tout reprendre ou ne rien reprendre,
    /// et le délai n'a aucun effet observable.
    func pendingReconciliation() async -> [FinancialCardPayload]

    /// Oublie tout état financier.
    ///
    /// Déconnexion et changement de compte. Conserver les objets du compte
    /// précédent afficherait les paiements de quelqu'un d'autre dans les
    /// conversations du suivant.
    func purge() async

    /// Demande l'annulation d'un objet, puis le relit : la carte dit ensuite ce
    /// que le serveur en a fait.
    func cancel(_ reference: FinancialReference,
                conversationID: String?) async -> Result<MoneyRequestCancelOutcome, FinanceError>
}

public extension FinancialObjectUseCasesProtocol {
    func cancel(_ reference: FinancialReference,
                conversationID: String?) async -> Result<MoneyRequestCancelOutcome, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

// MARK: - Objet inconnu du serveur

extension FinanceError {
    /// `CF_011` — « Financial intent not found ». Une validation, mais
    /// reconnaissable : c'est la seule qui dit que l'objet n'existe pas.
    static let financialObjectNotFound = FinanceError.validation(field: "financialIntentRef")
}

// MARK: - Implémentation

public struct FinancialObjectUseCases: FinancialObjectUseCasesProtocol {

    private let store: FinancialObjectStore
    private let client: (any FinanceAPIClientProtocol)?
    private let guardian: (any PaymentConfirmationGuardProtocol)?
    private let capabilities: any FinanceCapabilityProviding
    private let logger: any AppLoggerProtocol

    public init(
        store: FinancialObjectStore,
        client: (any FinanceAPIClientProtocol)?,
        guardian: (any PaymentConfirmationGuardProtocol)?,
        capabilities: any FinanceCapabilityProviding,
        logger: any AppLoggerProtocol
    ) {
        self.store = store
        self.client = client
        self.guardian = guardian
        self.capabilities = capabilities
        self.logger = logger
    }

    // MARK: Lecture

    public func current(for reference: FinancialReference) async -> FinancialCardPayload? {
        await store.current(for: reference)
    }

    public func refresh(
        _ reference: FinancialReference
    ) async -> Result<FinancialCardPayload, FinanceError> {

        guard await capabilities.canRenderFinancialCards() else {
            return .failure(.capabilityUnavailable)
        }

        guard let client else {
            // Graphe construit sans finance : ce n'est pas une erreur réseau,
            // et surtout pas un échec de paiement.
            return .failure(.capabilityUnavailable)
        }

        // 2.5 — Jeton relevé **avant** la requête. Une connexion survenue
        // pendant l'appel le rendra différent, et la réponse sera refusée.
        let session = await store.currentSessionToken

        do {
            let envelope = try await client.refresh(reference)

            // 1.1 — La réponse doit porter l'objet demandé.
            //
            // Sans ce contrôle, une réponse mal corrélée — cache serveur,
            // requête croisée, proxy — s'appliquerait sous l'identité demandée
            // et afficherait le paiement de quelqu'un d'autre dans cette bulle.
            guard envelope.id == reference.id else {
                await logFailure(reference, "refresh", .validation(field: "id"))
                return .failure(.validation(field: "id"))
            }

            // 1.1 — La révision vient du backend, jamais de la requête.
            //
            // `objectRevision` rend `nil` quand le backend n'a pas fourni de
            // révision exploitable ; on n'en invente alors aucune. Conserver
            // celle de la requête laisse le magasin refuser par égalité, ce que
            // le retour ci-dessous rapporte honnêtement — au lieu de fabriquer
            // une version qui ferait rejeter la correction backend suivante.
            let serverReference = FinancialReference(
                type: reference.type,
                id: envelope.id,
                version: envelope.objectRevision ?? reference.version,
                correlationID: reference.correlationID
            )

            let payload = await makePayload(envelope: envelope, reference: serverReference)

            // 1.2 — L'état affichable est celui que le magasin a retenu.
            //
            // Rendre `payload` sans regarder ce verdict était le défaut : une
            // réponse v9 arrivée après une v10 était refusée par le magasin et
            // rendue quand même à l'appelant, qui affichait la plus ancienne.
            if await store.apply(payload, session: session) {
                return .success(payload)
            }

            // 1.3 — Même révision, verdict de vérification différent.
            //
            // Une clé installée entre-temps lève l'incertitude sans que le
            // backend ait produit de nouvelle révision.
            if await store.revalidate(payload) {
                return .success(payload)
            }

            // Refusée : on rend ce qui fait foi localement, pas la réponse.
            // Une révision identique compte quand même comme une lecture.
            await store.markChecked(serverReference)
            if let retained = await store.current(for: serverReference) {
                return .success(retained)
            }

            // Refusée sans état retenu : rien d'affichable ne peut être promis.
            await logFailure(reference, "refresh", .conflict)
            return .failure(.conflict)

        } catch let error as FinanceError {
            await logFailure(reference, "refresh", error)
            if error == .financialObjectNotFound {
                // Le serveur ne connaît pas cet objet (`CF_011`) : une inscription
                // restée là — prepare abandonné, compte de test purgé — serait
                // relue à chaque réconciliation, sans fin. On l'oublie ; la bulle
                // garde ce qu'elle affichait.
                await store.discard(reference)
            }
            return .failure(error)
        } catch {
            // Une erreur inattendue en lecture n'est pas une ambiguïté financière :
            // aucune écriture n'a eu lieu.
            await logFailure(reference, "refresh", .server(statusCode: nil))
            return .failure(.server(statusCode: nil))
        }
    }

    // MARK: Application

    @discardableResult
    public func apply(_ payload: FinancialCardPayload) async -> Bool {
        await store.apply(payload)
    }

    public func discardSubmission(_ reference: FinancialReference) async {
        await store.discard(reference)
    }

    public func recordSubmission(_ payload: FinancialCardPayload) async {
        await store.applyLocalEcho(payload, persisting: true)
    }

    // MARK: Réconciliation

    /// Reprend chaque objet ambigu — `unknown`, ou vérifié sans succès.
    ///
    /// Séquentiel et non concurrent : les objets à réconcilier sont peu nombreux,
    /// et un burst de requêtes au retour du réseau est exactement ce qu'un backend
    /// en difficulté n'a pas besoin de recevoir.
    public func pendingReconciliation() async -> [FinancialCardPayload] {
        await store.needingReconciliation
    }

    public func purge() async {
        await store.clear()
    }

    /// Transforme les objets restaurés du disque en lectures serveur — lot 2.2.
    ///
    /// À appeler au démarrage, **après** `hydrate()`. Sans cette étape, la
    /// restauration produit une liste que personne ne lit : les opérations en
    /// attente d'un lancement précédent restent invisibles jusqu'à ce que
    /// l'utilisateur rouvre par hasard la bonne conversation.
    ///
    /// Séquentiel comme la réconciliation, et pour la même raison : un burst de
    /// requêtes au lancement est ce dont un backend en difficulté n'a pas besoin.
    public func restoreHydrated() async {
        let references = await store.hydratedReferences
        guard !references.isEmpty else { return }

        await logger.log(
            "Restauration de \(references.count) objet(s) financier(s)",
            level: .info
        )

        for reference in references {
            _ = await refresh(reference)
        }
    }

    public func reconcilePending() async {
        let pending = await store.needingReconciliation
        guard !pending.isEmpty else { return }

        await logger.log(
            "Réconciliation de \(pending.count) objet(s) financier(s)",
            level: .info
        )

        for payload in pending {
            _ = await refresh(payload.reference)
        }
    }

    // MARK: Annulation

    public func cancel(_ reference: FinancialReference,
                       conversationID: String?) async -> Result<MoneyRequestCancelOutcome, FinanceError> {
        guard let client else { return .failure(.capabilityUnavailable) }
        let outcome: Result<MoneyRequestCancelOutcome, FinanceError>
        do {
            outcome = .success(try await client.cancelIntent(reference, conversationID: conversationID))
        } catch let error as FinanceError {
            outcome = .failure(error)
        } catch {
            outcome = .failure(.server(statusCode: nil))
        }
        _ = await refresh(reference)
        return outcome
    }

    // MARK: Interne

    /// Construit la carte, en y attachant le verdict du garde.
    ///
    /// Le statut et la vérification sont portés séparément : un objet peut être
    /// `confirmed` côté backend sans que ce client ait pu l'établir. Fusionner les
    /// deux forcerait à choisir entre afficher une confirmation non vérifiée et
    /// masquer une confirmation réelle.
    private func makePayload(
        envelope: PaymentEnvelope,
        reference: FinancialReference
    ) async -> FinancialCardPayload {

        let verification = await verify(envelope: envelope, reference: reference)

        return FinancialCardPayload(
            reference: reference,
            status: envelope.status,
            amount: envelope.amount,
            currency: envelope.currency,
            feeAmount: envelope.feeAmount,
            feeCurrency: envelope.feeCurrency,
            counterpartyName: nil,
            note: envelope.description,
            lastRefreshedAt: Date(),
            verification: verification,
            allowedActions: envelope.metadata["allowedActions"].map {
                $0.split(separator: ",").map(String.init)
            }
        )
    }

    private func verify(
        envelope: PaymentEnvelope,
        reference: FinancialReference
    ) async -> FinancialCardVerification {

        guard let guardian else { return .unverified }

        // Seuls les statuts finaux de succès passent par le garde : il n'a rien à
        // dire d'un objet encore en cours, et lui demander produirait un
        // `statusNotFinal` interprété à tort comme un rejet de signature.
        guard envelope.status == .confirmed || envelope.status == .completed else {
            return .unverified
        }

        let confirmation = PaymentConfirmation(
            reference: reference,
            amount: envelope.amount,
            currency: envelope.currency,
            status: envelope.status,
            backendSignature: envelope.backendSignature,
            idempotencyKey: envelope.idempotencyKey,
            railProof: envelope.railProof,
            currentKnownVersion: await store.currentVersion(for: reference)
        )

        switch await guardian.decide(on: confirmation) {
        case .accepted:      return .verified
        case .rejected:      return .rejected
        case .undetermined:  return .unverified
        }
    }

    private func logFailure(
        _ reference: FinancialReference,
        _ operation: String,
        _ error: FinanceError
    ) async {
        let context = FinanceLogContext(reference: reference, operation: operation)
        await logger.log("Finance — \(context) error=\(error.technicalDetail)", level: .warning)
    }
}
