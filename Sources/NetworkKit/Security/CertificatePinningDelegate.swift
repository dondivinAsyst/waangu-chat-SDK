//
//  CertificatePinningDelegate.swift
//  NetworkKit
//
//  Bloc 9, G9-01 — l'application n'épinglait aucun certificat.
//

import Foundation
import WaanguCoreKit
import CryptoKit
import OSLog

/// Valide la chaîne TLS **et** vérifie qu'elle porte une clé publique épinglée.
///
/// Avant ce délégué, `AllowedHostsPolicy` filtrait les hôtes autorisés, ce qui
/// ne protège d'aucun interception : un proxy présentant un certificat valide
/// pour un hôte autorisé — CA d'entreprise, profil MDM, Burp — passait, et
/// pouvait réécrire montants, bénéficiaires et statuts financiers.
///
/// L'ordre des deux contrôles compte. La validation système d'abord, l'épinglage
/// ensuite : épingler sans valider accepterait un certificat auto-signé qui
/// porterait la bonne clé, et perdrait l'expiration et la révocation.
public final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    private let pins: any CertificatePinProviding
    private let onFailure: @Sendable (CertificatePinningFailure) -> Void

    private static let log = Logger(subsystem: "com.waangu.network", category: "pinning")

    /// - Parameter onFailure: appelé à chaque rejet, y compris en mode
    ///   observation. C'est le signal qui permet de mesurer avant de fermer.
    public init(
        pins: any CertificatePinProviding,
        onFailure: @escaping @Sendable (CertificatePinningFailure) -> Void = { _ in }
    ) {
        self.pins = pins
        self.onFailure = onFailure
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Hôte non épinglé : comportement système. Tous les hôtes ne sont pas
        // épinglés, et bloquer par défaut casserait les CDN et domaines tiers.
        guard let policy = pins.policy(for: host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 1. Validation système — expiration, révocation, chaîne d'autorité.
        guard Self.passesSystemValidation(trust) else {
            Self.log.error("Chaîne rejetée par le système pour \(host, privacy: .public)")
            onFailure(.systemTrustRejected(host: host))
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 2. Épinglage — une clé de la chaîne doit figurer dans la politique.
        //
        // Toute la chaîne est examinée, pas seulement la feuille : épingler une
        // clé intermédiaire est un choix d'exploitation légitime, qui survit au
        // renouvellement de la feuille.
        let presented = Self.spkiHashes(in: trust)
        let matched = !presented.isDisjoint(with: policy.spkiSHA256Base64)

        if matched {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        onFailure(.noPinMatched(host: host))

        guard policy.isEnforced else {
            // Mode observation : on laisse passer, mais l'échec est émis. Sans
            // cette trace, activer l'épinglage revient à couper les clients
            // sans savoir combien.
            Self.log.warning("Broche non trouvée pour \(host, privacy: .public) — observation, non bloquant")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        Self.log.error("Broche non trouvée pour \(host, privacy: .public) — connexion refusée")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Évaluation

    private static func passesSystemValidation(_ trust: SecTrust) -> Bool {
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }

    /// Empreintes SHA-256 des SPKI de toute la chaîne, en base64.
    private static func spkiHashes(in trust: SecTrust) -> Set<String> {
        let certificates: [SecCertificate]
        if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            certificates = chain
        } else {
            certificates = []
        }

        return Set(certificates.compactMap(spkiHash(of:)))
    }

    /// Point d'entrée de test.
    ///
    /// Exposé en `internal` plutôt que de rendre `spkiHash` public : l'empreinte
    /// SPKI est le seul endroit où l'épinglage peut se tromper en silence, et
    /// elle doit être comparable à la référence openssl depuis les tests.
    static func spkiHashForTesting(_ certificate: SecCertificate) -> String? {
        spkiHash(of: certificate)
    }

    private static func spkiHash(of certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let header = asn1Header(for: publicKey) else {
            return nil
        }

        // L'en-tête ASN.1 doit précéder la clé : l'empreinte SPKI porte sur la
        // structure SubjectPublicKeyInfo complète. Hacher la clé nue produit une
        // valeur qui ne correspond à aucun outil standard (`openssl … -pubkey |
        // openssl dgst -sha256`), et les broches deviennent invérifiables.
        return Data(SHA256.hash(data: header + data)).base64EncodedString()
    }

    /// En-tête ASN.1 du SubjectPublicKeyInfo, par type et taille de clé.
    private static func asn1Header(for key: SecKey) -> Data? {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let type = attributes[kSecAttrKeyType] as? String,
              let size = attributes[kSecAttrKeySizeInBits] as? Int else {
            return nil
        }

        switch (type, size) {
        case (String(kSecAttrKeyTypeRSA), 2048):
            return Data([
                0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48,
                0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01,
                0x0f, 0x00
            ])
        case (String(kSecAttrKeyTypeRSA), 4096):
            return Data([
                0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48,
                0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02,
                0x0f, 0x00
            ])
        case (String(kSecAttrKeyTypeECSECPrimeRandom), 256):
            return Data([
                0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d,
                0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01,
                0x07, 0x03, 0x42, 0x00
            ])
        case (String(kSecAttrKeyTypeECSECPrimeRandom), 384):
            return Data([
                0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d,
                0x02, 0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62,
                0x00
            ])
        default:
            // Type ou taille non couverts : rendre `nil` plutôt que deviner.
            // Une empreinte calculée sur un en-tête faux ne correspondrait à
            // aucune broche, et le rejet ressemblerait à une attaque.
            return nil
        }
    }
}
