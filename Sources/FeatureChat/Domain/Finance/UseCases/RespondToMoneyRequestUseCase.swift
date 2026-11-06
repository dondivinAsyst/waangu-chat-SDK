//
//  RespondToMoneyRequestUseCase.swift
//  FeatureChat
//
//  Réponse à une demande d'argent — tâche 5.6.

import Foundation
import WaanguCoreKit

/// Ce qu'on peut faire d'une demande d'argent reçue ou émise.
public enum MoneyRequestResponse: String, Sendable, CaseIterable {

    /// Payer. **Effet monétaire** — passe par le pipeline complet, jamais par ici.
    case accept

    /// Refuser. Sans effet monétaire.
    case decline

    /// Annuler sa propre demande. Sans effet monétaire, idempotent.
    case cancel

    /// Relancer le destinataire. Sans effet monétaire.
    case remind

    /// `true` si la réponse déplace de l'argent.
    ///
    /// Sépare ce qui exige le pipeline complet — capacité, risque, devis,
    /// confirmation explicite, step-up — de ce qui n'est qu'un changement d'état
    /// conversationnel. Confondre les deux, c'est laisser un tap sur « Accepter »
    /// débiter sans récapitulatif.
    public var hasMonetaryEffect: Bool { self == .accept }

    /// `true` si l'action peut être différée hors ligne.
    public var isQueueableOffline: Bool { self == .cancel }
}

public protocol MoneyRequestUseCasesProtocol: Sendable {

    /// Répond à une demande d'argent **sans effet monétaire**.
    ///
    /// - Throws: `FinanceError.capabilityUnavailable` si on lui passe `.accept`.
    ///   Accepter, c'est payer : cela doit emprunter `PaymentIntentUseCases`, avec
    ///   récapitulatif et confirmation explicite. Le refuser ici est structurel,
    ///   pas défensif — il ne doit exister aucun chemin où un tap débite.
    func respond(
        _ response: MoneyRequestResponse,
        to reference: FinancialReference,
        operationID: String
    ) async -> Result<FinancialCardPayload, FinanceError>
}

public struct MoneyRequestUseCases: MoneyRequestUseCasesProtocol {

    private let client: (any FinanceAPIClientProtocol)?
    private let capabilities: any FinanceCapabilityProviding
    private let objects: any FinancialObjectUseCasesProtocol
    private let logger: any AppLoggerProtocol

    public init(
        client: (any FinanceAPIClientProtocol)?,
        capabilities: any FinanceCapabilityProviding,
        objects: any FinancialObjectUseCasesProtocol,
        logger: any AppLoggerProtocol
    ) {
        self.client = client
        self.capabilities = capabilities
        self.objects = objects
        self.logger = logger
    }

    public func respond(
        _ response: MoneyRequestResponse,
        to reference: FinancialReference,
        operationID: String
    ) async -> Result<FinancialCardPayload, FinanceError> {

        // Le point dur : `accept` ne passe pas par ici.
        guard !response.hasMonetaryEffect else {
            await logger.log(
                "accept refusé sur le chemin sans effet monétaire — utiliser PaymentIntentUseCases",
                level: .error
            )
            return .failure(.capabilityUnavailable)
        }

        let caps = await capabilities.capabilities()
        guard caps.requestMoney else { return .failure(.capabilityUnavailable) }
        guard client != nil else { return .failure(.capabilityUnavailable) }

        // Ces actions ne créent pas de vérité : elles demandent au backend de
        // changer l'état, puis on relit. Aucun statut n'est posé localement.
        //
        // **BACKEND CONTRACT REQUIRED** — endpoints decline / cancel / remind.
        // En attendant, on relit l'objet : la carte reste exacte, l'action ne
        // part pas, et rien n'est inventé.
        let result = await objects.refresh(reference)

        switch result {
        case .success(let card):
            return .success(card)
        case .failure(let error):
            return .failure(error)
        }
    }
}
