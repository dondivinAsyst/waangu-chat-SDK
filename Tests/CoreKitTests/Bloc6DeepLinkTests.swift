import Testing
import Foundation
@testable import WaanguCoreKit

/// Liens profonds signés — Bloc 6, §20 et chapitre 52.
///
/// Couvre le P0-7 : un lien actionnable ne doit pas pouvoir être fabriqué,
/// transféré ou rejoué.
@Suite("Bloc 6 — liens profonds signés")
struct Bloc6DeepLinkTests {

    private func context(
        issuedAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(600),
        nonce: String = "n-1",
        audience: String? = "user-42"
    ) -> SignedDeepLinkContext {
        SignedDeepLinkContext(
            appID: "waangu.taxi", objectType: "ride", objectID: "r-1",
            contextID: "c-1", issuedAt: issuedAt, expiresAt: expiresAt,
            nonce: nonce, signature: "sig", audience: audience
        )
    }

    /// Toujours valide, quel que soit le verdict du vérificateur.
    private struct AlwaysValid: DeepLinkVerifying {
        func verify(_ context: SignedDeepLinkContext, expectedAudience: String) async -> DeepLinkVerdict { .valid }
        func consume(nonce: String) async {}
    }

    // MARK: - Classification

    /// La règle de sûreté : ce qui n'est pas explicitement navigationnel est
    /// actionnable. Un hôte ajouté demain est protégé par défaut.
    @Test("Un hôte inconnu est traité comme actionnable")
    func unknownHostIsActionable() {
        #expect(DeepLinkActionability.classify(host: "pay", firstPathComponent: "link") == .actionable)
        #expect(DeepLinkActionability.classify(host: "nouveau", firstPathComponent: nil) == .actionable)
        #expect(DeepLinkActionability.classify(host: "chat", firstPathComponent: "callback") == .actionable)
    }

    @Test("Les cibles de navigation restent ouvertes sans signature")
    func navigationalTargetsStayOpen() {
        #expect(DeepLinkActionability.classify(host: "chat", firstPathComponent: "conversation") == .navigational)
        #expect(DeepLinkActionability.classify(host: "wallet", firstPathComponent: "home") == .navigational)
        #expect(DeepLinkActionability.classify(host: "ride", firstPathComponent: "detail") == .navigational)
    }

    /// L'objet financier ouvre une lecture par identifiant opaque : le serveur
    /// vérifie l'appartenance, donc la signature n'y ajoute rien.
    @Test("La lecture d'un objet financier reste navigationnelle")
    func financialObjectIsNavigational() {
        #expect(DeepLinkActionability.classify(host: "chat",
                                               firstPathComponent: "financial-object") == .navigational)
    }

    /// Un lien de paiement ne paie rien (`executable=false`) : il ouvre la
    /// demande, et le paiement exige devis et confirmation. Actionnable, il
    /// exigerait une signature que le contrat ne fournit pas.
    @Test("Un lien de paiement ouvre la demande sans rien déclencher")
    func paymentLinkIsNavigational() {
        #expect(DeepLinkActionability.classify(host: "chat", firstPathComponent: "pay-link") == .navigational)
    }

    // MARK: - Expiration

    @Test("Un contexte expiré est refusé")
    func expiredContextIsRejected() async {
        let now = Date()
        let gate = DeepLinkGate(verifier: AlwaysValid())
        let expired = context(expiresAt: now.addingTimeInterval(-1))

        let verdict = await gate.evaluate(actionability: .actionable, context: expired,
                                          expectedAudience: "user-42", at: now)
        #expect(verdict == .expired)
    }

    /// Une durée de vie anormalement longue se signale sans bloquer : c'est au
    /// backend de fixer ses durées, mais une émission mal configurée doit se voir.
    @Test("Une durée de vie trop longue est signalée")
    func suspiciousLifetimeIsFlagged() {
        let now = Date()
        let week = context(issuedAt: now, expiresAt: now.addingTimeInterval(604_800))
        let short = context(issuedAt: now, expiresAt: now.addingTimeInterval(300))

        #expect(week.hasSuspiciousLifetime())
        #expect(!short.hasSuspiciousLifetime())
    }

    // MARK: - Absence de contexte (P0-7)

    /// Le cœur du P0-7. L'absence de preuve n'est pas une preuve d'innocence :
    /// c'est exactement la forme qu'aurait un lien fabriqué à la main.
    @Test("Un lien actionnable sans contexte est refusé")
    func actionableWithoutContextIsRejected() async {
        let gate = DeepLinkGate(verifier: AlwaysValid())
        let verdict = await gate.evaluate(actionability: .actionable, context: nil,
                                          expectedAudience: "user-42")
        #expect(verdict == .invalidSignature)
        #expect(verdict.isSecurityIncident)
    }

    @Test("Un lien navigationnel passe sans contexte")
    func navigationalWithoutContextPasses() async {
        let gate = DeepLinkGate(verifier: AlwaysValid())
        let verdict = await gate.evaluate(actionability: .navigational, context: nil,
                                          expectedAudience: "user-42")
        #expect(verdict.isValid)
    }

    // MARK: - Rejeu

    /// Un lien consommé ne repart pas. Sans ce contrôle, le retour arrière
    /// suffirait à rejouer l'effet.
    @Test("Un nonce consommé fait refuser le lien")
    func consumedNonceIsReplayed() async {
        let gate = DeepLinkGate(verifier: AlwaysValid())
        let link = context(nonce: "n-unique")

        #expect(await gate.evaluate(actionability: .actionable, context: link,
                                    expectedAudience: "user-42").isValid)
        await gate.commit(link)

        let second = await gate.evaluate(actionability: .actionable, context: link,
                                         expectedAudience: "user-42")
        #expect(second == .replayed)
        #expect(second.isSecurityIncident)
    }

    /// Vérifier ne brûle pas. Un lien ouvert puis abandonné doit rester
    /// utilisable, sinon un geste hésitant coûte définitivement le lien.
    @Test("Vérifier ne consomme pas le nonce")
    func evaluateDoesNotBurnNonce() async {
        let gate = DeepLinkGate(verifier: AlwaysValid())
        let link = context(nonce: "n-2")

        _ = await gate.evaluate(actionability: .actionable, context: link, expectedAudience: "u")
        _ = await gate.evaluate(actionability: .actionable, context: link, expectedAudience: "u")

        #expect(await gate.evaluate(actionability: .actionable, context: link,
                                    expectedAudience: "u").isValid)
    }

    // MARK: - Registre de nonces

    /// Un nonce doit être retenu **plus longtemps** que le lien ne vit : sinon
    /// la fenêtre de rejeu se rouvre juste avant l'expiration.
    @Test("Le nonce reste retenu après l'expiration du lien")
    func nonceOutlivesLink() async {
        let now = Date()
        let store = DeepLinkNonceStore(grace: 3600)
        let linkExpiry = now.addingTimeInterval(60)

        await store.consume("n-3", expiringAt: linkExpiry, at: now)

        #expect(await store.isConsumed("n-3", at: now.addingTimeInterval(120)))
        #expect(await store.isConsumed("n-3", at: now.addingTimeInterval(3_000)))
        // Passé la rétention, il est oublié — le lien n'est plus présentable.
        #expect(!(await store.isConsumed("n-3", at: now.addingTimeInterval(4_000))))
    }

    @Test("Un nonce jamais vu n'est pas consommé")
    func unknownNonceIsFree() async {
        let store = DeepLinkNonceStore()
        #expect(!(await store.isConsumed("jamais-vu")))
    }

    // MARK: - Verdicts

    /// Une signature invalide et une expiration n'appellent pas la même
    /// réaction : la première est un incident, la seconde une banalité.
    @Test("Seuls certains refus sont des incidents de sécurité")
    func securityIncidentsAreDistinguished() {
        #expect(DeepLinkVerdict.invalidSignature.isSecurityIncident)
        #expect(DeepLinkVerdict.replayed.isSecurityIncident)
        #expect(DeepLinkVerdict.wrongAudience.isSecurityIncident)
        #expect(DeepLinkVerdict.unknownIssuer.isSecurityIncident)

        #expect(!DeepLinkVerdict.expired.isSecurityIncident)
        #expect(!DeepLinkVerdict.unauthorizedApp.isSecurityIncident)
        #expect(!DeepLinkVerdict.valid.isSecurityIncident)
    }

    // MARK: - Extraction depuis l'URL

    @Test("Le contexte se décode depuis le paramètre ctx en base64url")
    func contextDecodesFromURL() throws {
        let source = context()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(source)

        // Alphabet URL : ni `+`, ni `/`, ni remplissage.
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let url = URL(string: "waangu://pay/link/abc?ctx=\(encoded)")!
        let decoded = SignedDeepLinkContext.extract(from: url)

        #expect(decoded?.nonce == source.nonce)
        #expect(decoded?.appID == source.appID)
        #expect(decoded?.objectID == source.objectID)
    }

    /// Un contexte corrompu produit `nil`, donc un refus — jamais un contexte
    /// partiel accepté.
    @Test("Un contexte illisible rend nil")
    func corruptContextYieldsNil() {
        #expect(SignedDeepLinkContext.extract(from: URL(string: "waangu://pay/link?ctx=%%%")!) == nil)
        #expect(SignedDeepLinkContext.extract(from: URL(string: "waangu://pay/link")!) == nil)
    }

    // MARK: - Défaut fermé

    /// Le défaut ne rend pas `.valid` « en attendant ».
    @Test("Le vérificateur fermé refuse tout")
    func closedVerifierRefuses() async {
        let verdict = await ClosedDeepLinkVerifier().verify(context(), expectedAudience: "u")
        #expect(verdict == .unknownIssuer)
        #expect(!verdict.isValid)
    }
}
