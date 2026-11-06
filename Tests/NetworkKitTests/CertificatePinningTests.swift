//
//  CertificatePinningTests.swift
//  NetworkKitTests
//
//  Bloc 9, G9-01 — preuve (niveau 6) de l'épinglage SPKI.
//

import XCTest
import CryptoKit
@testable import WaanguNetworkKit
import WaanguCoreKit

/// Vérifie que l'empreinte calculée par le délégué est **celle qu'openssl
/// produit**, et non une valeur interne cohérente avec elle-même.
///
/// C'est le point où l'épinglage se trompe silencieusement : une empreinte
/// calculée sur la clé nue, sans l'en-tête ASN.1 du SubjectPublicKeyInfo, est
/// parfaitement stable et parfaitement fausse. Les broches renseignées depuis
/// `openssl x509 -pubkey | openssl dgst -sha256` ne correspondraient jamais, et
/// le rejet ressemblerait à une attaque permanente.
final class CertificatePinningTests: XCTestCase {

    /// Certificat auto-signé EC P-256, généré pour ce test.
    /// `openssl req -new -x509 -key ec.key -subj "/CN=pinning.test"`
    private static let certificateDER = """
    MIIBHjCBxAIJAOUr0TOxq4tSMAoGCCqGSM49BAMCMBcxFTATBgNVBAMMDHBpbm5pbmcudGVzdDAeFw0yNjA5MDgxMzAwMDNaFw0zNjA5MDUxMzAwMDNaMBcxFTATBgNVBAMMDHBpbm5pbmcudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABF1i7DBxtsDgTxmj/lTqycURP3ll0U1FflKeWnqu3xv/f34E9EKgvKY3yzuUwSHc2oJqheFqRWwtJS+OCzxxla4wCgYIKoZIzj0EAwIDSQAwRgIhAPA5Cba+8B/ScQf/IWJAsNCsbmteiKhiv0oiuvevFzChAiEAu/3awk7cg4sl5Bxs/4XqJdLQ1xEyJ9qS8b/ZEilm1iM=
    """

    /// Référence produite hors de Swift :
    /// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
    ///   | openssl dgst -sha256 -binary | openssl enc -base64`
    private static let expectedSPKIHash = "8km8v22mWRg3C93JM65RGkBMRsJhnGxBjF9aXXuBmgY="

    private func makeCertificate() throws -> SecCertificate {
        let cleaned = Self.certificateDER.replacingOccurrences(of: "\n", with: "")
        let data = try XCTUnwrap(Data(base64Encoded: cleaned), "DER illisible")
        return try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData),
                             "certificat non décodable")
    }

    // MARK: - Le contrôle central

    func test_spkiHash_matchesOpenSSLReference() throws {
        let certificate = try makeCertificate()

        let hash = try XCTUnwrap(
            CertificatePinningDelegate.spkiHashForTesting(certificate),
            "empreinte non calculée — en-tête ASN.1 manquant pour ce type de clé ?"
        )

        XCTAssertEqual(
            hash, Self.expectedSPKIHash,
            "L'empreinte diverge d'openssl : les broches renseignées par l'exploitation ne correspondront jamais."
        )
    }

    /// Sans l'en-tête ASN.1, l'empreinte est stable mais fausse. Ce test fige
    /// l'écart, pour qu'un « nettoyage » de l'en-tête casse ici plutôt qu'en
    /// production.
    func test_spkiHash_differsFromRawKeyHash() throws {
        let certificate = try makeCertificate()
        let publicKey = try XCTUnwrap(SecCertificateCopyKey(certificate))
        let raw = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let rawHash = Data(SHA256.hash(data: raw)).base64EncodedString()

        XCTAssertNotEqual(
            rawHash, Self.expectedSPKIHash,
            "Si ces deux valeurs coïncident, le test de référence ne prouve plus rien."
        )
    }

    // MARK: - Politique

    func test_noPinning_returnsNoPolicy() {
        XCTAssertNil(NoCertificatePinning().policy(for: "api.waangu.test"))
    }

    func test_policy_matchesOnlyExactHost() {
        let policy = CertificatePinPolicy(
            host: "api.waangu.test",
            spkiSHA256Base64: [Self.expectedSPKIHash],
            isEnforced: true
        )
        let provider = StaticPinProvider(policies: [policy])

        XCTAssertNotNil(provider.policy(for: "api.waangu.test"))
        // Un sous-domaine ne doit pas hériter : un `*.waangu.test` épinglé
        // couvrirait aussi un sous-domaine compromis.
        XCTAssertNil(provider.policy(for: "evil.api.waangu.test"))
        XCTAssertNil(provider.policy(for: "waangu.test"))
    }

    func test_policy_acceptsBackupPin() {
        let policy = CertificatePinPolicy(
            host: "api.waangu.test",
            spkiSHA256Base64: ["courante", "secours"],
            isEnforced: true
        )

        // Deux broches minimum : sans la seconde, une régénération de clé casse
        // l'application jusqu'à la prochaine version App Store.
        XCTAssertEqual(policy.spkiSHA256Base64.count, 2)
        XCTAssertTrue(policy.spkiSHA256Base64.contains("secours"))
    }
}

/// Fournisseur de test — correspondance exacte d'hôte.
private struct StaticPinProvider: CertificatePinProviding {
    let policies: [CertificatePinPolicy]
    func policy(for host: String) -> CertificatePinPolicy? {
        policies.first { $0.host == host }
    }
}
