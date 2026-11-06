//
//  FinanceAPIClientProtocol.swift
//  CoreKit
//
//  Accès gouverné aux objets financiers.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §5.3 et §6.

import Foundation

/// Le seul chemin par lequel une feature atteint la vérité financière.
///
/// Aucune implémentation ici : CoreKit ne porte que des contrats. L'implémentation
/// s'adosse au pipeline existant `TransactionStep` (`check → request → confirm →
/// verify`) — il n'existe pas de second pipeline de paiement dans ce dépôt.
///
/// Ce que ce contrat **ne propose pas**, délibérément :
/// - aucune méthode d'écriture d'un statut : le client ne fait pas avancer un objet ;
/// - aucune méthode de suppression : la trace financière est réglementaire ;
/// - aucune lecture par montant, contrepartie ou conversation : la lecture se fait
///   par référence, ce qui empêche d'énumérer les objets d'autrui.
public protocol FinanceAPIClientProtocol: Sendable {

    /// Catalogue des capacités autorisées pour la session courante.
    /// Toute erreur doit être traitée comme `.none` par l'appelant, jamais ignorée.
    func capabilities() async throws -> FinanceCapabilities

    /// Lit l'objet désigné par la référence.
    ///
    /// La `version` portée par la référence sert d'indication, pas de filtre : le
    /// backend répond avec la version courante, qui peut être plus récente.
    func financialObject(for reference: FinancialReference) async throws -> PaymentEnvelope

    /// Force une relecture, en contournant tout cache.
    ///
    /// Distinct de `financialObject` à dessein : c'est l'appel de la réconciliation
    /// et du geste « actualiser », les deux situations où un cache est exactement
    /// ce qu'il ne faut pas lire.
    func refresh(_ reference: FinancialReference) async throws -> PaymentEnvelope

    /// Crée une intention de paiement.
    ///
    /// L'`IdempotencyContext` est **fourni par l'appelant**, jamais fabriqué ici :
    /// un client qui génère la clé au moment de l'appel en génère une nouvelle à
    /// chaque retry, ce qui est exactement le défaut que la clé doit empêcher.
    func createPaymentIntent(
        _ request: CreatePaymentIntentRequest,
        idempotency: IdempotencyContext
    ) async throws -> PaymentEnvelope

    /// Confirme une intention déjà créée, après confirmation explicite de
    /// l'utilisateur et satisfaction éventuelle d'une politique de step-up.
    ///
    /// - Throws: `FinanceError.timeoutUnknown` si la requête est partie sans
    ///   réponse exploitable. L'appelant ne doit alors ni conclure à un échec,
    ///   ni relancer : il réconcilie.
    func confirmPaymentIntent(
        reference: FinancialReference,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async throws -> PaymentEnvelope

    /// Demande l'annulation d'un objet que le serveur déclare annulable.
    ///
    /// `.cancelled` : annulé avant soumission. `.requested` : déjà soumis, la
    /// finalité de l'annulation appartient à Finance (`CF_046`) — l'écran ne
    /// dit pas « annulé ».
    func cancelIntent(_ reference: FinancialReference,
                      conversationID: String?) async throws -> MoneyRequestCancelOutcome
}

public extension FinanceAPIClientProtocol {
    /// Par défaut : pas d'annulation. Seul un client branché sur
    /// `/intent/cancel-request` sait en demander une.
    func cancelIntent(_ reference: FinancialReference,
                      conversationID: String?) async throws -> MoneyRequestCancelOutcome {
        throw FinanceError.capabilityUnavailable
    }
}

// MARK: - CreatePaymentIntentRequest

/// Ce que le client demande. Ce n'est pas ce qu'il obtient : montants, frais et
/// taux définitifs sont ceux que le backend renvoie dans l'enveloppe.
public struct CreatePaymentIntentRequest: Codable, Sendable, Hashable {

    public let type: FinancialObjectType

    /// Montant souhaité, en unité majeure. `Decimal` et non `Double` : un binaire
    /// flottant ne représente pas exactement une somme d'argent.
    public let amount: Decimal

    public let currency: String

    /// Identifiant backend du bénéficiaire. Jamais un numéro de téléphone brut :
    /// la résolution contrepartie → identifiant appartient au backend, qui seul
    /// peut vérifier que le bénéficiaire est toujours éligible.
    public let recipientID: String

    /// Conversation d'origine, pour que le backend rattache l'objet au fil.
    /// Ne confère aucun droit : l'autorisation ne dépend pas de la conversation.
    public let conversationID: String?

    /// Note libre de l'utilisateur. Le backend en reste l'arbitre (longueur, filtrage).
    public let note: String?

    public init(
        type: FinancialObjectType,
        amount: Decimal,
        currency: String,
        recipientID: String,
        conversationID: String? = nil,
        note: String? = nil
    ) {
        self.type = type
        self.amount = amount
        self.currency = currency
        self.recipientID = recipientID
        self.conversationID = conversationID
        self.note = note
    }
}
