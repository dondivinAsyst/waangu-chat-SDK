//
//  StepUpAuthenticating.swift
//  CoreKit
//
//  Preuve de satisfaction d'une politique d'authentification renforcée.
//
//  Le protocole `StepUpAuthenticating` lui-même **préexiste** au Bloc 1 et vit
//  dans `Protocols/SecurityKit/DeviceTrust/DeviceTrust.swift` ; ce fichier ne
//  déclare que ce qui lui manquait — l'attestation et ses erreurs — et le
//  protocole est étendu sur place. Déclarer un second contrat de step-up aurait
//  reproduit exactement le défaut relevé au §3.1 de la spec : plusieurs types
//  pour une seule notion.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §12 du prompt d'origine.

import Foundation

// MARK: - StepUpAttestation

/// Preuve qu'un niveau de step-up a été satisfait sur cet appareil.
///
/// Existe parce que `elevate(to:) -> Bool` ne suffit pas à une opération
/// financière. Un booléen produit localement dit « l'appareil est content » ;
/// sur un appareil compromis, il dit toujours oui. L'attestation, elle, se
/// présente au backend, qui reste seul juge.
///
/// Ne porte aucune donnée biométrique : celles-ci ne quittent jamais l'enclave
/// sécurisée et n'ont aucune raison de traverser une frontière de module.
public struct StepUpAttestation: Codable, Sendable, Hashable {

    /// Niveau effectivement atteint.
    ///
    /// Peut être **inférieur** à celui demandé si le système a proposé un repli.
    /// Le backend doit donc le revérifier plutôt que supposer qu'il correspond à
    /// sa demande — c'est le point où un client complaisant mentirait.
    public let level: StepUpLevel

    /// Corrèle l'attestation à l'opération qu'elle couvre.
    ///
    /// Sans elle, une attestation obtenue pour un geste anodin pourrait être
    /// représentée pour en couvrir un autre.
    public let correlationID: CorrelationId

    /// Lie l'attestation à l'appareil.
    public let deviceID: String

    /// Lie l'attestation à la session.
    ///
    /// Ajouté au Bloc 8 (§19) : une preuve biométrique doit être *device-bound,
    /// session-bound, time-bound et purpose-bound*. `deviceID` et
    /// `correlationID` couvraient déjà l'appareil et l'objet ; la session
    /// manquait, de sorte qu'une attestation survivait à une reconnexion sous
    /// une autre session sur le même appareil.
    ///
    /// `nil` signifie **non liée à une session**, et non « liée à toutes » :
    /// ``StepUpBindingRequirement`` la refuse sur un chemin mutant.
    public let sessionID: String?

    /// Instant de satisfaction.
    ///
    /// Le backend décide de sa péremption ; le client ne se prononce pas sur la
    /// durée de validité d'une preuve qu'il ne contrôle pas.
    public let satisfiedAt: Date

    /// Jeton opaque produit par le fournisseur (challenge signé, App Attest…).
    ///
    /// `nil` lorsque le mécanisme local n'en produit pas — `LocalAuthentication`
    /// est dans ce cas. L'attestation vaut alors déclaration, et le backend doit
    /// la pondérer en conséquence : pour un montant élevé, exiger App Attest.
    public let evidenceToken: String?

    public init(
        level: StepUpLevel,
        correlationID: CorrelationId,
        deviceID: String,
        sessionID: String? = nil,
        satisfiedAt: Date = Date(),
        evidenceToken: String? = nil
    ) {
        self.level = level
        self.correlationID = correlationID
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.satisfiedAt = satisfiedAt
        self.evidenceToken = evidenceToken
    }
}

// MARK: - StepUpError

public enum StepUpError: Error, Sendable, Equatable {

    /// L'utilisateur a refusé ou annulé. Ce n'est pas un incident.
    case userCancelled

    /// Le niveau n'est pas atteignable localement — biométrie non enrôlée, ou
    /// niveau qui exige une vérification hors bande que seul le backend peut
    /// conduire. Le backend doit alors proposer un autre chemin.
    case levelUnavailable(StepUpLevel)

    /// Trop d'échecs : l'appareil a verrouillé le mécanisme.
    case lockedOut

    /// Échec système sans signification métier.
    case failed(String)
}

// MARK: - Satisfaction par attestation

public extension StepUpAuthenticating {

    /// Repli pour les conformeurs antérieurs au Bloc 1.
    ///
    /// Traduit l'ancien `elevate(to:) -> Bool` en attestation. Le jeton est `nil`
    /// et le niveau est celui demandé — c'est précisément la faiblesse de
    /// l'ancien contrat : il ne permet pas de savoir ce qui a réellement été
    /// satisfait. Un conformeur destiné à couvrir une opération financière doit
    /// implémenter `satisfyStepUp` lui-même.
    func satisfyStepUp(
        level: StepUpLevel,
        reason: String,
        correlationID: CorrelationId,
        deviceID: String
    ) async throws -> StepUpAttestation {
        guard try await elevate(to: level) else {
            throw StepUpError.userCancelled
        }
        return StepUpAttestation(
            level: level,
            correlationID: correlationID,
            deviceID: deviceID
        )
    }
}

// MARK: - Défaut fermé

/// N'élève aucun niveau d'authentification.
///
/// Remplace le `nil` qui servait de valeur par défaut. La différence n'est pas
/// cosmétique : une dépendance **optionnelle** laisse chaque site d'appel
/// décider quoi faire de son absence, et il suffit d'un site qui interprète
/// `nil` comme « pas de step-up requis » pour ouvrir un chemin non authentifié.
///
/// Ici, l'authentificateur existe toujours et **refuse toujours** tant que
/// personne n'en injecte un vrai. Le refus est un comportement, pas un trou.
public struct ClosedStepUpAuthenticator: StepUpAuthenticating {

    public init() {}

    /// Aucune authentification n'a jamais eu lieu.
    public var currentLevel: StepUpLevel { get async { .none } }

    /// Échoue en nommant la cause : le niveau est indisponible, ce qui n'est
    /// **pas** une annulation par l'utilisateur. L'interface distingue les deux,
    /// et confondre « le mécanisme manque » avec « l'utilisateur a renoncé »
    /// enverrait chercher un geste que personne ne peut faire.
    public func elevate(to level: StepUpLevel) async throws -> Bool {
        throw StepUpError.levelUnavailable(level)
    }
}
