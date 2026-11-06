import Testing
import Foundation
@testable import WaanguCoreKit

/// Identité marchande épinglée — Bloc 6, chapitre 44.
///
/// Couvre les deux P0 fermés en premier : l'exposant de devise composé côté
/// client, et l'absence de revalidation avant paiement.
@Suite("Bloc 6 — identité marchande")
struct Bloc6MerchantIdentityTests {

    private func snapshot(
        capturedAt: Date = Date(),
        capabilityExpiresAt: Date? = nil,
        verification: VerificationStatus = .verified
    ) -> MerchantIdentitySnapshot {
        MerchantIdentitySnapshot(
            merchantID: "m-1", identityVersion: "id-3", policyVersion: "pol-2",
            verification: verification, capturedAt: capturedAt,
            capabilityExpiresAt: capabilityExpiresAt
        )
    }

    // MARK: - Exposant de devise (P0-1)

    /// Le bug corrigé : l'exposant était codé à zéro dans l'écran marchand.
    /// Sur une devise à deux décimales, 12,50 partait pour 12 unités mineures.
    @Test("L'exposant de la devise décide du montant en unités mineures")
    func currencyExponentDrivesMinorUnits() {
        let cad = Money(minorUnits: 1250, currency: CurrencyCode(code: "CAD", exponent: 2))
        let bif = Money(minorUnits: 1250, currency: CurrencyCode(code: "BIF", exponent: 0))

        #expect(cad.majorUnitsForDisplay == Decimal(string: "12.50"))
        #expect(bif.majorUnitsForDisplay == 1250)
        // Deux devises différentes ne se comparent pas.
        #expect(!cad.isComparable(to: bif))
    }

    /// Le profil porte désormais des devises avec exposant, pas des codes nus :
    /// c'est ce qui rend l'erreur impossible à réintroduire depuis l'écran.
    @Test("Le profil marchand porte l'exposant de chaque devise acceptée")
    func merchantCarriesCurrencyExponent() {
        let profile = MerchantProfile(
            actor: FinancialActor(actorID: "m-1", type: .merchant, displayName: "Boutique",
                                  verification: .verified, permissions: [.execute]),
            acceptsPayments: true,
            acceptedCurrencies: [CurrencyCode(code: "CAD", exponent: 2)],
            identityVersion: "id-3", policyVersion: "pol-2"
        )
        #expect(profile.acceptedCurrencies.first?.exponent == 2)
    }

    // MARK: - Revalidation (P0-2)

    /// Une capacité expirée ferme le paiement, quoi qu'affiche le profil.
    @Test("Une capacité expirée rend l'instantané inutilisable")
    func expiredCapabilityBlocks() {
        let now = Date()
        let expired = snapshot(capabilityExpiresAt: now.addingTimeInterval(-1))
        let live = snapshot(capabilityExpiresAt: now.addingTimeInterval(3600))

        #expect(expired.hasExpiredCapability(at: now))
        #expect(expired.isStale(at: now))
        #expect(!live.hasExpiredCapability(at: now))
    }

    /// Un écran resté ouvert vieillit. La borne locale ne remplace pas le
    /// verdict serveur : elle force la revalidation.
    @Test("Un instantané trop vieux est périmé")
    func staleAfterMaxAge() {
        let now = Date()
        #expect(snapshot(capturedAt: now.addingTimeInterval(-300)).isStale(at: now))
        #expect(!snapshot(capturedAt: now.addingTimeInterval(-10)).isStale(at: now))
    }

    /// `nil` n'est pas « illimité » : c'est l'absence de borne côté backend.
    /// L'écran ne doit pas la transformer en expiration.
    @Test("Sans échéance, la capacité n'expire pas d'elle-même")
    func noExpiryMeansNoExpiry() {
        #expect(!snapshot(capabilityExpiresAt: nil).hasExpiredCapability())
    }

    /// Le cœur du P0-2 : seul `unchanged` laisse enchaîner sans geste. Traiter
    /// `changed` comme un feu vert ferait payer une identité jamais vue.
    @Test("Seul .unchanged autorise le paiement immédiat")
    func onlyUnchangedPermitsPayment() {
        let profile = MerchantProfile(
            actor: FinancialActor(actorID: "m-1", type: .merchant, displayName: "Boutique",
                                  verification: .verified, permissions: [.execute]),
            acceptsPayments: true, identityVersion: "id-4", policyVersion: "pol-2"
        )

        #expect(MerchantIdentityVerdict.unchanged.permitsImmediatePayment)
        #expect(!MerchantIdentityVerdict.changed(profile).permitsImmediatePayment)
        #expect(!MerchantIdentityVerdict.suspended(reasonKey: "k").permitsImmediatePayment)
        #expect(!MerchantIdentityVerdict.revoked(reasonKey: "k").permitsImmediatePayment)
    }

    /// L'instantané naît du profil, avec ses trois versions. Le fabriquer à
    /// partir du seul identifiant lui ferait perdre toute valeur de preuve.
    @Test("L'instantané reprend les versions du profil affiché")
    func snapshotCarriesProfileVersions() {
        let profile = MerchantProfile(
            actor: FinancialActor(actorID: "m-9", type: .merchant, displayName: "Pharmacie",
                                  verification: .verified, permissions: [.execute]),
            acceptsPayments: true, identityVersion: "id-7", policyVersion: "pol-5"
        )
        let pinned = profile.snapshot()

        #expect(pinned.merchantID == "m-9")
        #expect(pinned.identityVersion == "id-7")
        #expect(pinned.policyVersion == "pol-5")
        #expect(pinned.verification == .verified)
    }

    /// Le défaut fermé refuse aussi la revalidation : sans implémentation, on
    /// ne laisse pas passer un paiement en prétendant que rien n'a changé.
    @Test("Le défaut fermé refuse la revalidation")
    func closedDefaultRefusesRevalidation() async {
        let result = await ClosedMerchantProfileProvider().revalidate(snapshot())
        if case .failure(let error) = result {
            #expect(error == .capabilityUnavailable)
        } else {
            Issue.record("le défaut fermé a laissé passer une revalidation")
        }
    }
}
