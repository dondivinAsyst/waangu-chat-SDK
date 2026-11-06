//
//  ExecutionPermitIssuing.swift
//  CoreKit
//
//  Permis d'exécution à usage unique — Bloc 2 §13.4.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /execution-permits`
//  et `POST /execution-permits/{id}/consume`.
//  Voir BLOC2-MODELE-CONVERSATIONNEL-FINANCIER.md §12.2.
//

import Foundation

/// Autorisation d'exécuter **une** opération, dans **ces** conditions.
///
/// Ce que la clé d'idempotence ne fait pas : elle empêche qu'un retry crée une
/// seconde opération, mais elle n'empêche pas d'exécuter une opération dont les
/// frais, le taux ou le bénéficiaire ont changé depuis l'accord de l'utilisateur.
/// Les deux mécanismes sont complémentaires, jamais interchangeables — les
/// confondre laisse passer les scénarios 13 à 16.
public struct ExecutionPermit: Codable, Sendable, Equatable {

    public let permitID: String

    /// Objet auquel ce permis se rapporte. Un permis n'est pas transférable.
    public let objectID: String

    /// Empreinte du `ConfirmationSnapshot` accepté.
    /// C'est ce qui lie l'exécution à ce que l'utilisateur a réellement vu.
    public let snapshotHash: String

    public let issuedAt: Date
    public let expiresAt: Date

    /// Toujours `true` dans le Bloc 2. Le champ existe pour que le contrat soit
    /// explicite, pas pour offrir un permis réutilisable.
    public let singleUse: Bool

    public init(
        permitID: String,
        objectID: String,
        snapshotHash: String,
        issuedAt: Date,
        expiresAt: Date,
        singleUse: Bool = true
    ) {
        self.permitID = permitID
        self.objectID = objectID
        self.snapshotHash = snapshotHash
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.singleUse = singleUse
    }
}

public extension ExecutionPermit {

    /// `true` si le permis est encore utilisable pour cet aperçu, à cet instant.
    ///
    /// Les trois conditions sont vérifiées ensemble à dessein : un permis valide
    /// pour un autre objet, ou pour d'autres conditions, n'est pas « à moitié
    /// bon ». Les séparer inviterait un site d'appel à n'en vérifier qu'une.
    func authorizes(_ snapshot: ConfirmationSnapshot, asOf now: Date = Date()) -> Bool {
        objectID == snapshot.reference.id
            && snapshotHash == snapshot.decisionHash
            && now < expiresAt
    }

    func isExpired(asOf now: Date = Date()) -> Bool { now >= expiresAt }
}

// MARK: - Contrat

/// Émet et consomme les permis d'exécution.
///
/// Deux appels distincts et non un seul : entre l'émission et la consommation,
/// le client peut mourir. Un permis émis mais jamais consommé expire de
/// lui-même ; un permis consommé ne peut plus l'être. Fusionner les deux ferait
/// perdre cette distinction et rendrait le rejeu indétectable.
public protocol ExecutionPermitIssuing: Sendable {

    /// Demande un permis pour l'aperçu accepté par l'utilisateur.
    ///
    /// - Parameter idempotency: la clé de l'intention, **pas une neuve**. Deux
    ///   demandes pour la même intention doivent rendre le même permis.
    func issue(
        for snapshot: ConfirmationSnapshot,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<ExecutionPermit, FinanceError>

    /// Consomme le permis. Un permis déjà consommé échoue — c'est le point.
    func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError>
}
