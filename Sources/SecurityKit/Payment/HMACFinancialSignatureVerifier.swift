//
//  HMACFinancialSignatureVerifier.swift
//  SecurityKit
//
//  Vérification HMAC-SHA256 des objets financiers.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.5 — remplace le contrôle de longueur
//  de chaîne qui tenait lieu de vérification.

import Foundation
import CryptoKit
import WaanguCoreKit

/// Vérifie la signature backend d'un objet financier.
///
/// La clé de vérification n'est **jamais** embarquée dans le binaire : elle est
/// installée à l'exécution depuis l'IdentityGateway et conservée au trousseau.
/// Un secret compilé dans l'application est un secret public — n'importe qui peut
/// l'extraire d'un `.ipa` et forger des confirmations.
///
/// Sans clé installée, le vérificateur répond `.unverifiable` et **jamais**
/// `.authentic`. C'est le comportement voulu tant que le contrat backend #1 n'est
/// pas livré : rien ne s'affiche comme confirmé, plutôt que tout.
public actor HMACFinancialSignatureVerifier: FinancialSignatureVerifying {

    private let keychain: any KeychainStoreProtocol
    private let logger: AppLogger

    /// Clé de vérification en mémoire, une fois chargée depuis le trousseau.
    private var cachedKey: SymmetricKey?

    /// `true` une fois la tentative de chargement effectuée, pour ne pas
    /// interroger le trousseau à chaque vérification lorsqu'aucune clé n'existe.
    private var didAttemptLoad = false

    private static let keychainKey = "com.waangu.finance.signature.verification-key"

    public init(keychain: any KeychainStoreProtocol, logger: AppLogger) {
        self.keychain = keychain
        self.logger = logger
    }

    // MARK: - Installation de la clé

    /// Installe la clé de vérification fournie par l'IdentityGateway.
    ///
    /// À rappeler à chaque rotation. L'ancienne clé est écrasée : conserver un
    /// trousseau de clés acceptées élargirait la fenêtre d'une clé compromise.
    ///
    /// **BACKEND CONTRACT REQUIRED** — contrat #1 : endpoint de distribution,
    /// cadence de rotation, encodage de la clé.
    public func installVerificationKey(base64: String) async throws {
        guard let data = Data(base64Encoded: base64), data.count >= 32 else {
            throw SignatureVerifierError.invalidKeyMaterial
        }
        try await keychain.saveData(data, forKey: Self.keychainKey)
        cachedKey = SymmetricKey(data: data)
        didAttemptLoad = true
        await logger.log("Clé de vérification financière installée", level: .info)
    }

    /// Retire la clé — déconnexion, révocation d'appareil.
    public func removeVerificationKey() async {
        try? await keychain.remove(forKey: Self.keychainKey)
        cachedKey = nil
        didAttemptLoad = true
    }

    // MARK: - FinancialSignatureVerifying

    public func isOperational() async -> Bool {
        await loadedKey() != nil
    }

    public func verify(
        signature: String,
        over payload: FinancialSignaturePayload
    ) async -> FinancialSignatureVerdict {

        guard !signature.isEmpty else {
            return .forged
        }

        guard let key = await loadedKey() else {
            // Pas de clé : ce client ne peut pas se prononcer. Surtout pas
            // `.authentic`, et pas `.forged` non plus — le backend n'a rien fait
            // de mal, c'est le client qui n'est pas configuré.
            return .unverifiable(reason: "no_verification_key")
        }

        guard let provided = Self.decodeSignature(signature) else {
            // Une signature illisible est un contenu qui ne correspond pas au
            // contrat : c'est un rejet, pas une indétermination.
            return .forged
        }

        // Comparaison à temps constant — `isValidAuthenticationCode` compare sans
        // court-circuit. Un `==` sur des `Data` s'arrête au premier octet
        // divergent et laisse mesurer la position de l'erreur.
        let valid = HMAC<SHA256>.isValidAuthenticationCode(
            provided,
            authenticating: payload.canonicalData,
            using: key
        )
        return valid ? .authentic : .forged
    }

    // MARK: - Interne

    private func loadedKey() async -> SymmetricKey? {
        if let cachedKey { return cachedKey }
        guard !didAttemptLoad else { return nil }
        didAttemptLoad = true

        let stored: Data?
        do {
            stored = try await keychain.getData(forKey: Self.keychainKey)
        } catch {
            await logger.log("Lecture de la clé de vérification impossible", level: .error)
            return nil
        }
        guard let material = stored, material.count >= 32 else { return nil }

        let key = SymmetricKey(data: material)
        cachedKey = key
        return key
    }

    /// Accepte base64 et hexadécimal.
    ///
    /// **BACKEND CONTRACT REQUIRED** — contrat #1 : l'encodage doit être fixé.
    /// Accepter les deux est une tolérance d'intégration, pas une position tenable :
    /// dès que l'encodage est arrêté, retirer l'autre branche.
    private static func decodeSignature(_ signature: String) -> Data? {
        if let data = Data(base64Encoded: signature), data.count == SHA256.byteCount {
            return data
        }
        return hexDecode(signature)
    }

    private static func hexDecode(_ string: String) -> Data? {
        let chars = Array(string)
        guard chars.count == SHA256.byteCount * 2 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(SHA256.byteCount)
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(chars[index...index + 1]), radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index += 2
        }
        return Data(bytes)
    }
}

// MARK: - Vérificateur indisponible

/// Vérificateur qui ne peut rien vérifier, et le dit.
///
/// À injecter tant que le contrat backend #1 n'est pas livré. Existe pour que le
/// graphe de dépendances soit complet et testable sans qu'un `nil` optionnel se
/// propage jusqu'aux sites d'appel — un `verifier?` invite au `?? true`.
public struct UnavailableFinancialSignatureVerifier: FinancialSignatureVerifying {

    private let reason: String

    public init(reason: String = "backend_contract_pending") {
        self.reason = reason
    }

    public func isOperational() async -> Bool { false }

    public func verify(
        signature: String,
        over payload: FinancialSignaturePayload
    ) async -> FinancialSignatureVerdict {
        .unverifiable(reason: reason)
    }
}

// MARK: - Erreurs

public enum SignatureVerifierError: Error, Sendable, Equatable {
    /// Clé absente, mal encodée, ou trop courte pour HMAC-SHA256.
    case invalidKeyMaterial
}
