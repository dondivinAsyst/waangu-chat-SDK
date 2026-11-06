//
//  AppAttestation.swift
//  CoreKit
//
//  Bloc 9, §13 (ch. 73) — App Attest et verdict de confiance.
//

import Foundation

/// Décision de confiance **rendue par le backend de sécurité**.
///
/// À ne pas confondre avec ``DeviceTrustVerdict`` (`DeviceTrust.swift`), qui
/// agrège les signaux calculés *localement* — jailbreak, menaces runtime,
/// liaison Secure Enclave. Les deux coexistent volontairement, et la
/// distinction est le §13 lui-même : les signaux locaux sont une **entrée**,
/// jamais l'autorité. Un verdict calculé sur l'appareil est une valeur que
/// l'attaquant B contrôle, sur un appareil qu'il contrôle.
///
/// Le mobile produit une attestation ; le serveur décide et rend ceci.
public enum DeviceTrustDecision: String, Codable, Sendable, Equatable {

    /// Toutes les capacités financières autorisées par la politique.
    case trusted = "TRUSTED"

    /// Lecture seule, ou plafonds réduits. La décision appartient au moteur Risk.
    case limited = "LIMITED"

    /// Authentification renforcée exigée avant toute action financière.
    case stepUp = "STEP_UP"

    /// Aucune action financière.
    case blocked = "BLOCKED"
}

/// Attestation produite par l'appareil, à faire vérifier par le serveur.
public struct DeviceAttestation: Sendable, Equatable {

    /// Identifiant de la clé App Attest, généré et conservé par l'appareil.
    public let keyID: String

    /// Objet d'attestation (première inscription) ou assertion (usages suivants).
    public let payload: Data

    /// Défi **fourni par le serveur**.
    ///
    /// Le serveur émet le défi, jamais le client : un défi choisi localement
    /// rendrait l'attestation rejouable, ce qui annule exactement ce qu'elle
    /// prouve.
    public let challenge: String

    /// `true` pour une première inscription, `false` pour une assertion.
    public let isEnrollment: Bool

    public init(keyID: String, payload: Data, challenge: String, isEnrollment: Bool) {
        self.keyID = keyID
        self.payload = payload
        self.challenge = challenge
        self.isEnrollment = isEnrollment
    }
}

/// Produit des attestations d'intégrité de l'application.
public protocol AppAttesting: Sendable {

    /// `false` sur simulateur et sur les appareils non éligibles.
    ///
    /// L'indisponibilité n'est pas un échec de sécurité : c'est une entrée de
    /// plus pour le moteur Risk, qui décide quoi en faire. La traiter comme une
    /// compromission bloquerait tout le développement sur simulateur.
    var isSupported: Bool { get }

    /// Inscrit cet appareil — une seule fois par installation.
    func enroll(challenge: String) async throws -> DeviceAttestation

    /// Signe une requête avec la clé inscrite.
    ///
    /// - Parameter clientDataHash: empreinte des données à lier à l'assertion.
    ///   C'est ce qui rattache l'attestation à **cette** requête ; sans elle,
    ///   une assertion valide autorise n'importe quel appel.
    func assert(challenge: String, clientDataHash: Data) async throws -> DeviceAttestation
}

/// Erreurs d'attestation.
public enum AppAttestationError: Error, Sendable, Equatable {

    /// Matériel ou OS non éligible, ou simulateur.
    case unsupported

    /// Aucune clé inscrite — il faut appeler `enroll` d'abord.
    case notEnrolled

    /// Le service Apple a refusé ou n'a pas répondu.
    case attestationFailed(reason: String)
}
