//
//  AppAttestService.swift
//  SecurityKit
//
//  Bloc 9, G9-03 — l'application ne produisait aucune attestation matérielle.
//

import Foundation
import WaanguCoreKit
import DeviceCheck
import CryptoKit
import OSLog

/// Implémente App Attest.
///
/// Avant ce service, l'intégrité reposait entièrement sur des heuristiques —
/// `DeviceIntegritySignals`, `Raspmonitor` — qui détectent un jailbreak
/// ordinaire et rien d'autre. Une application repackagée ou instrumentée par
/// Frida émet exactement les mêmes requêtes qu'une application authentique, et
/// le backend n'avait aucun moyen de faire la différence.
///
/// App Attest apporte ce que l'heuristique ne peut pas : une clé matérielle,
/// gardée par la Secure Enclave, qu'Apple atteste comme appartenant à une
/// installation authentique de **ce** bundle. Elle ne se falsifie pas depuis
/// l'espace utilisateur, contrairement à tout contrôle local.
///
/// Ce que ce service ne fait pas, délibérément : décider. Il produit une
/// attestation ; le verdict appartient au backend, conformément au §13.
public actor AppAttestService: AppAttesting {

    private let service = DCAppAttestService.shared
    private let keyStorage: any SecureKeyIDStoring

    /// Autorité qui juge l'attestation.
    ///
    /// Le §13 sépare produire et juger : ce service produisait sans que rien ne
    /// vérifie, ce qui revenait à ne rien produire du tout.
    private let verifier: any DeviceAttestationVerifying

    private static let log = Logger(subsystem: "com.waangu.security", category: "attest")

    public init(
        keyStorage: any SecureKeyIDStoring,
        verifier: any DeviceAttestationVerifying = UnavailableAttestationVerifier()
    ) {
        self.keyStorage = keyStorage
        self.verifier = verifier
    }

    public nonisolated var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    // MARK: - Inscription

    public func enroll(challenge: String) async throws -> DeviceAttestation {
        guard service.isSupported else { throw AppAttestationError.unsupported }

        let keyID = try await generateKey()

        // Le défi vient du serveur : c'est lui qui garantit la fraîcheur. Le
        // hacher ici plutôt que l'envoyer brut suit ce qu'attend `attestKey`.
        let hash = Data(SHA256.hash(data: Data(challenge.utf8)))

        let attestation: Data
        do {
            attestation = try await service.attestKey(keyID, clientDataHash: hash)
        } catch {
            // La clé générée mais non attestée est inutilisable : la retirer
            // évite qu'un `assert` ultérieur échoue sans explication.
            try? await keyStorage.clearKeyID()
            Self.log.error("Attestation refusée")
            throw AppAttestationError.attestationFailed(reason: String(describing: error))
        }

        let produced = DeviceAttestation(
            keyID: keyID,
            payload: attestation,
            challenge: challenge,
            isEnrollment: true
        )

        // Faire **juger** l'attestation avant de retenir la clé. Conserver une
        // clé que l'autorité refuse laisserait le service produire indéfiniment
        // des assertions issues d'une inscription invalide.
        switch await verifier.verify(produced, expectedChallenge: challenge) {
        case .success(let decision):
            try await keyStorage.saveKeyID(keyID)
            Self.log.info("Inscription acceptée, verdict \(decision.rawValue, privacy: .public)")
            return produced

        case .failure(let error):
            try? await keyStorage.clearKeyID()
            Self.log.error("Inscription refusée par l'autorité")
            throw AppAttestationError.attestationFailed(reason: String(describing: error))
        }
    }

    // MARK: - Assertion

    public func assert(challenge: String, clientDataHash: Data) async throws -> DeviceAttestation {
        guard service.isSupported else { throw AppAttestationError.unsupported }

        guard let keyID = try await keyStorage.loadKeyID() else {
            throw AppAttestationError.notEnrolled
        }

        // Le défi **et** les données de la requête entrent dans l'empreinte.
        // Lier les deux est ce qui empêche de rejouer une assertion valide sur
        // une autre requête — un virement vers un autre bénéficiaire, par
        // exemple. Une assertion qui ne porte que le défi autorise n'importe
        // quel appel dans sa fenêtre de fraîcheur.
        var combined = Data(challenge.utf8)
        combined.append(clientDataHash)
        let hash = Data(SHA256.hash(data: combined))

        do {
            let assertion = try await service.generateAssertion(keyID, clientDataHash: hash)
            let produced = DeviceAttestation(
                keyID: keyID,
                payload: assertion,
                challenge: challenge,
                isEnrollment: false
            )

            // Même règle qu'à l'inscription : une assertion que personne ne juge
            // n'apporte rien. Le verdict n'est pas rendu à l'appelant — le §13
            // veut qu'il alimente le moteur Risk, pas qu'il autorise ici.
            switch await verifier.verify(produced, expectedChallenge: challenge) {
            case .success:
                return produced
            case .failure(let error):
                throw AppAttestationError.attestationFailed(reason: String(describing: error))
            }
        } catch {
            Self.log.error("Assertion refusée")
            throw AppAttestationError.attestationFailed(reason: String(describing: error))
        }
    }

    // MARK: -

    private func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyID, error in
                if let keyID {
                    continuation.resume(returning: keyID)
                } else {
                    continuation.resume(
                        throwing: AppAttestationError.attestationFailed(
                            reason: error.map { String(describing: $0) } ?? "clé absente"
                        )
                    )
                }
            }
        }
    }
}

/// Conserve l'identifiant de clé App Attest.
///
/// Séparé du service pour que le stockage reste testable et remplaçable :
/// l'identifiant n'est pas un secret, mais le perdre force une réinscription,
/// que le backend doit alors distinguer d'une tentative d'inscription multiple.
public protocol SecureKeyIDStoring: Sendable {
    func saveKeyID(_ keyID: String) async throws
    func loadKeyID() async throws -> String?
    func clearKeyID() async throws
}
