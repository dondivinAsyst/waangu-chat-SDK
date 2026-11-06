//
//  ResilientFinanceAPIClient.swift
//  CoreKit
//
//  Résilience appliquée au chemin financier réel — §15, §17, §19.
//

import Foundation

/// Enveloppe un client financier avec les garde-fous du §15.
///
/// Un **décorateur**, pas une réécriture : les implémentations existantes ne
/// changent pas, et la résilience s'ajoute ou se retire d'une ligne. C'est aussi
/// ce qui rend les règles testables sans réseau — l'enveloppé est un protocole.
///
/// Trois asymétries portent tout le comportement, et aucune n'est arbitraire :
///
/// - **Les lectures réessaient, les écritures non.** Relire coûte une requête ;
///   réécrire coûte un second débit.
/// - **Le disjoncteur bloque les lectures, jamais une confirmation.** Refuser
///   localement de confirmer une intention déjà créée laisserait de l'argent
///   dans un état que personne ne vient clarifier.
/// - **Un timeout n'est pas un échec.** Il ouvre le disjoncteur et remonte
///   `timeoutUnknown`, que l'appelant réconcilie — il ne le rejoue pas.
public actor ResilientFinanceAPIClient: FinanceAPIClientProtocol {

    private let wrapped: any FinanceAPIClientProtocol
    private let breaker: ProviderCircuitBreaker
    private let idempotency: IdempotencyStore
    private let readPolicy: RetryPolicy

    /// Identifie le circuit. Un disjoncteur par fournisseur : une panne d'un
    /// prestataire ne doit pas couper les autres.
    private let circuitKey: ProviderCircuitKey

    public init(
        wrapping client: any FinanceAPIClientProtocol,
        breaker: ProviderCircuitBreaker = ProviderCircuitBreaker(),
        idempotency: IdempotencyStore = IdempotencyStore(),
        readPolicy: RetryPolicy = .read,
        circuitKey: ProviderCircuitKey
    ) {
        self.wrapped = client
        self.breaker = breaker
        self.idempotency = idempotency
        self.readPolicy = readPolicy
        self.circuitKey = circuitKey
    }

    // MARK: - Lectures

    public func capabilities() async throws -> FinanceCapabilities {
        try await read { try await self.wrapped.capabilities() }
    }

    public func financialObject(for reference: FinancialReference) async throws -> PaymentEnvelope {
        try await read { try await self.wrapped.financialObject(for: reference) }
    }

    /// Écriture : transmise telle quelle, jamais réessayée.
    public func cancelIntent(_ reference: FinancialReference,
                             conversationID: String?) async throws -> MoneyRequestCancelOutcome {
        try await wrapped.cancelIntent(reference, conversationID: conversationID)
    }

    public func refresh(_ reference: FinancialReference) async throws -> PaymentEnvelope {
        // `refresh` est l'appel de la réconciliation : il doit passer même
        // disjoncteur ouvert, sinon un incident se répare seulement une fois la
        // panne finie — c'est-à-dire trop tard pour l'utilisateur qui attend.
        try await attempt(honoringCircuit: false) { try await self.wrapped.refresh(reference) }
    }

    /// Lecture réessayée, sous disjoncteur.
    private func read<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        guard await breaker.allowsAttempt(for: circuitKey) else {
            throw FinanceError.capabilityUnavailable
        }

        var attemptIndex = 1
        while true {
            do {
                let value = try await operation()
                await breaker.recordSuccess(for: circuitKey)
                return value
            } catch {
                await breaker.recordFailure(for: circuitKey)

                // Un timeout sur une lecture reste réessayable : relire ne
                // déplace rien. C'est le seul endroit où cette indulgence est
                // sûre, et elle s'arrête aux lectures.
                guard let delay = readPolicy.nextDelay(afterAttempt: attemptIndex) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attemptIndex += 1
            }
        }
    }

    /// Une tentative, sans réessai.
    private func attempt<T: Sendable>(
        honoringCircuit: Bool,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        if honoringCircuit, await breaker.allowsAttempt(for: circuitKey) == false {
            throw FinanceError.capabilityUnavailable
        }
        do {
            let value = try await operation()
            await breaker.recordSuccess(for: circuitKey)
            return value
        } catch let refusal as FinanceServerRefusal {
            // Un refus métier est un aller-retour **réussi** : le serveur a
            // répondu, et il a dit non. Le compter comme une panne ouvrirait le
            // disjoncteur sur un backend en parfait état, et couperait les
            // lectures des autres utilisateurs de ce client.
            await breaker.recordSuccess(for: circuitKey)
            throw refusal
        } catch {
            await breaker.recordFailure(for: circuitKey)
            throw error
        }
    }

    // MARK: - Écritures

    /// Crée une intention, **une seule fois**.
    ///
    /// La clé fournie par l'appelant sert de garde : rejouée avec le même
    /// contenu, elle rend l'enveloppe mémorisée sans rappeler le backend ;
    /// rejouée avec un contenu différent, elle lève `requestConflict` plutôt
    /// que de créer une seconde intention sous la même clé.
    public func createPaymentIntent(
        _ request: CreatePaymentIntentRequest,
        idempotency context: IdempotencyContext
    ) async throws -> PaymentEnvelope {

        let hash = Self.hash(of: request)

        switch await idempotency.resolve(key: context.key, requestHash: hash) {
        case .success(let data):
            return try Self.decoder.decode(PaymentEnvelope.self, from: data)
        case .failure(let error):
            throw error
        case nil:
            break
        }

        let envelope = try await attempt(honoringCircuit: true) {
            try await self.wrapped.createPaymentIntent(request, idempotency: context)
        }

        if let data = try? Self.encoder.encode(envelope) {
            await idempotency.store(key: context.key, requestHash: hash,
                                    responseData: data, ttl: 900)
        }
        return envelope
    }

    /// Confirme une intention. **Jamais réessayé, jamais bloqué localement.**
    ///
    /// Le disjoncteur n'est pas honoré ici : refuser de confirmer parce qu'un
    /// circuit est ouvert laisserait une intention créée dans un état que rien
    /// ne vient résoudre. On tente, on enregistre l'issue, et un timeout
    /// remonte tel quel — l'appelant réconcilie.
    public func confirmPaymentIntent(
        reference: FinancialReference,
        idempotency context: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async throws -> PaymentEnvelope {

        let hash = Self.hash(of: reference)

        switch await idempotency.resolve(key: context.key, requestHash: hash) {
        case .success(let data):
            return try Self.decoder.decode(PaymentEnvelope.self, from: data)
        case .failure(let error):
            throw error
        case nil:
            break
        }

        let envelope = try await attempt(honoringCircuit: false) {
            try await self.wrapped.confirmPaymentIntent(
                reference: reference, idempotency: context, stepUp: stepUp
            )
        }

        if let data = try? Self.encoder.encode(envelope) {
            await idempotency.store(key: context.key, requestHash: hash,
                                    responseData: data, ttl: 900)
        }
        return envelope
    }

    // MARK: - Outillage

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Empreinte stable d'une requête.
    ///
    /// `Hasher` suffit : l'empreinte ne quitte jamais le processus et ne sert
    /// qu'à comparer deux requêtes sous une même clé. Une empreinte
    /// cryptographique coûterait sans rien apporter — ce n'est pas une preuve
    /// opposable, c'est un garde-fou local.
    private static func hash(of request: CreatePaymentIntentRequest) -> String {
        var hasher = Hasher()
        hasher.combine(request.type)
        hasher.combine(request.amount)
        hasher.combine(request.currency)
        hasher.combine(request.recipientID)
        hasher.combine(request.conversationID)
        hasher.combine(request.note)
        return String(hasher.finalize())
    }

    private static func hash(of reference: FinancialReference) -> String {
        var hasher = Hasher()
        hasher.combine(reference.id)
        hasher.combine(reference.version)
        return String(hasher.finalize())
    }
}
