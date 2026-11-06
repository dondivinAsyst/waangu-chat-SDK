import Testing
import Foundation
@testable import WaanguCoreKit

/// Collectes et mini-apps — Bloc 6, chapitres 51 et 52.
@Suite("Bloc 6 — collectes et mini-apps")
struct Bloc6CampaignNativeTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)
    private func money(_ v: Int64) -> Money { Money(minorUnits: v, currency: bif) }

    private func policy(
        fixed: Int64? = nil, minimum: Int64? = nil, maximum: Int64? = nil,
        anonymity: Bool = true
    ) -> CollectionPolicy {
        CollectionPolicy(
            fixedContribution: fixed.map(money),
            minimumContribution: minimum.map(money),
            maximumContribution: maximum.map(money),
            allowsPublicAnonymity: anonymity,
            requiresVoteForDisbursement: false,
            allowsRefund: true,
            visibility: .contributorsOnly
        )
    }

    private func campaign(
        state: CampaignState = .open,
        verification: BeneficiaryVerification = .verified,
        target: Int64? = 100_000,
        collected: Int64 = 40_000,
        deadline: Date? = nil,
        identityVersion: String = "id-1"
    ) -> Campaign {
        Campaign(
            id: "c-1", kind: .fundraising, titleKey: "Collecte",
            organizer: CampaignOrganizer(
                actor: FinancialActor(actorID: "o-1", type: .user, displayName: "Organisateur",
                                      verification: .verified, permissions: [.read]),
                trustLevel: .established
            ),
            beneficiary: CampaignBeneficiary(
                actor: FinancialActor(actorID: "b-1", type: .user, displayName: "Bénéficiaire",
                                      verification: .verified, permissions: [.read]),
                verification: verification, identityVersion: identityVersion
            ),
            target: target.map(money), collected: money(collected), disbursed: money(0),
            state: state, policy: policy(), createdAt: Date(), deadline: deadline
        )
    }

    // MARK: - Collecte : bénéficiaire

    /// Le §51 exige la vérification du bénéficiaire. Collecter d'abord pour
    /// vérifier ensuite est le schéma exact de la collecte frauduleuse.
    @Test("Un bénéficiaire non vérifié bloque les contributions")
    func unverifiedBeneficiaryBlocksContributions() {
        #expect(campaign(verification: .verified).acceptsContributions())
        #expect(!campaign(verification: .unverified).acceptsContributions())
        #expect(!campaign(verification: .pending).acceptsContributions())
        #expect(!campaign(verification: .rejected).acceptsContributions())
    }

    @Test("Une vérification inconnue vaut non vérifiée")
    func unknownVerificationIsUnverified() throws {
        let decoded = try JSONDecoder().decode(BeneficiaryVerification.self,
                                               from: Data(#""NEW""#.utf8))
        #expect(decoded == .unverified)
        #expect(!decoded.permitsCollection)
    }

    /// Marqué P0 par le §30 : une collecte ne peut pas changer de bénéficiaire
    /// sans revalidation. Sans version d'identité, le changement est invisible.
    @Test("Un changement de bénéficiaire est détecté au décaissement")
    func beneficiaryChangeIsDetected() {
        let source = campaign(identityVersion: "id-1")
        let unchanged = DisbursementWorkflow(
            id: "d-1", campaignID: "c-1", amount: money(10_000), state: .requested,
            beneficiaryVerification: .verified, beneficiaryIdentityVersion: "id-1",
            requestedAt: Date()
        )
        let changed = DisbursementWorkflow(
            id: "d-2", campaignID: "c-1", amount: money(10_000), state: .requested,
            beneficiaryVerification: .verified, beneficiaryIdentityVersion: "id-9",
            requestedAt: Date()
        )
        #expect(!unchanged.beneficiaryChanged(since: source))
        #expect(changed.beneficiaryChanged(since: source))
    }

    // MARK: - Collecte : état et échéance

    /// Dépasser un objectif n'est pas une erreur : la collecte continue.
    @Test("Une collecte à l'objectif atteint accepte encore")
    func targetMetStillAccepts() {
        #expect(campaign(state: .targetMet).acceptsContributions())
        #expect(campaign(state: .open).acceptsContributions())
        #expect(!campaign(state: .suspended).acceptsContributions())
        #expect(!campaign(state: .closed).acceptsContributions())
        #expect(!campaign(state: .unknown).acceptsContributions())
    }

    @Test("Une collecte échue n'accepte plus rien")
    func expiredCampaignStopsAccepting() {
        let now = Date()
        #expect(!campaign(deadline: now.addingTimeInterval(-1)).acceptsContributions(at: now))
        #expect(campaign(deadline: now.addingTimeInterval(3600)).acceptsContributions(at: now))
    }

    @Test("La progression est bornée à 100 %")
    func progressIsCapped() {
        #expect(campaign(target: 100_000, collected: 40_000).progressPercent == 40)
        #expect(campaign(target: 100_000, collected: 250_000).progressPercent == 100)
        // Sans objectif, pas de progression — et surtout pas zéro.
        #expect(campaign(target: nil).progressPercent == nil)
    }

    // MARK: - Politique de contribution

    @Test("Un montant imposé n'accepte que lui")
    func fixedContributionAcceptsOnlyItself() {
        let fixed = policy(fixed: 5_000)
        #expect(fixed.accepts(money(5_000)))
        #expect(!fixed.accepts(money(4_000)))
        #expect(!fixed.accepts(money(6_000)))
    }

    @Test("Les bornes minimum et maximum sont respectées")
    func boundsAreEnforced() {
        let bounded = policy(minimum: 1_000, maximum: 50_000)
        #expect(bounded.accepts(money(1_000)))
        #expect(bounded.accepts(money(50_000)))
        #expect(!bounded.accepts(money(999)))
        #expect(!bounded.accepts(money(50_001)))
        #expect(!bounded.accepts(money(0)))
    }

    /// Demander l'anonymat là où la collecte ne l'autorise pas produirait une
    /// contribution nominative alors que le contributeur croyait le contraire.
    /// Pire que le refus.
    @Test("L'anonymat non autorisé rend l'intention mal formée")
    func anonymityRequiresPermission() {
        let anonymous = ContributionIntent(campaignID: "c-1", amount: money(2_000),
                                           isPubliclyAnonymous: true)
        #expect(anonymous.isWellFormed(under: policy(anonymity: true)))
        #expect(!anonymous.isWellFormed(under: policy(anonymity: false)))

        let named = ContributionIntent(campaignID: "c-1", amount: money(2_000))
        #expect(named.isWellFormed(under: policy(anonymity: false)))
    }

    /// Une tontine engage un tour de cotisations. L'interface doit le dire
    /// avant l'adhésion, pas au premier appel de fonds.
    @Test("Seule la tontine crée une obligation récurrente")
    func onlyTontineCreatesObligation() {
        #expect(CampaignKind.tontine.createsRecurringObligation)
        #expect(!CampaignKind.fundraising.createsRecurringObligation)
        #expect(!CampaignKind.eventPot.createsRecurringObligation)
    }

    /// Un niveau de confiance inconnu retombe sur `newOrganizer`, pas
    /// `trusted` : le sens de la dégradation protège le contributeur.
    @Test("Un niveau de confiance inconnu vaut nouvel organisateur")
    func unknownTrustDegradesSafely() throws {
        let decoded = try JSONDecoder().decode(OrganizerTrustLevel.self,
                                               from: Data(#""SUPER""#.utf8))
        #expect(decoded == .newOrganizer)
        #expect(decoded.warrantsWarning)
    }

    @Test("Une visibilité inconnue retombe sur la plus restrictive")
    func unknownVisibilityDegradesSafely() throws {
        let decoded = try JSONDecoder().decode(CampaignVisibility.self,
                                               from: Data(#""EVERYONE""#.utf8))
        #expect(decoded == .contributorsOnly)
    }

    @Test("Un brouillon de nature inconnue ne se soumet pas")
    func unknownKindDraftIsRejected() {
        let draft = CampaignDraft(kind: .unknown, titleKey: "Collecte",
                                  beneficiaryID: "b-1", policy: policy())
        #expect(!draft.isSubmittable)

        let valid = CampaignDraft(kind: .fundraising, titleKey: "Collecte",
                                  beneficiaryID: "b-1", policy: policy())
        #expect(valid.isSubmittable)
    }

    // MARK: - Mini-apps

    private func descriptor(
        types: [String] = ["ride"],
        capabilities: Set<NativeAppCapability> = [.renderCard, .deepLink],
        available: Bool = true
    ) -> NativeAppDescriptor {
        NativeAppDescriptor(
            appID: "waangu.ride", owner: "Ride", displayNameKey: "Course",
            objectTypes: types, capabilities: capabilities,
            contractVersion: "1.0", isAvailable: available, fallback: .web
        )
    }

    /// Router un objet de pharmacie vers l'application de course produit un
    /// écran vide et un ticket de support.
    @Test("Une application ne traite que ses types d'objets")
    func appHandlesOnlyItsTypes() {
        #expect(descriptor(types: ["ride", "booking"]).handles(objectType: "ride"))
        #expect(!descriptor(types: ["ride"]).handles(objectType: "prescription"))
    }

    /// Sans repli, un objet référencé dans une conversation devient un
    /// cul-de-sac le jour où l'application est retirée du marché.
    @Test("Un repli inconnu retombe sur la carte seule")
    func unknownFallbackDegradesToCardOnly() throws {
        let decoded = try JSONDecoder().decode(NativeAppFallback.self,
                                               from: Data(#""TELEPORT""#.utf8))
        #expect(decoded == .cardOnly)
    }

    /// Une action inconnue de ce client ne s'exécute pas, quoi qu'en dise
    /// l'application qui l'a déclarée.
    @Test("Une action de carte inconnue n'est pas exécutable")
    func unknownCardActionIsNotExecutable() throws {
        let decoded = try JSONDecoder().decode(UniversalCardActionKind.self,
                                               from: Data(#""LAUNCH_ROCKET""#.utf8))
        #expect(decoded == .unknown)
        #expect(!decoded.isExecutable)
        #expect(UniversalCardActionKind.pay.isExecutable)
    }

    /// Une ordonnance relève de `sensitive` : se tromper dans ce sens masque
    /// trop, se tromper dans l'autre expose.
    @Test("Une classe de confidentialité inconnue est traitée comme sensible")
    func unknownPrivacyClassIsSensitive() throws {
        let decoded = try JSONDecoder().decode(NativeObjectPrivacyClass.self,
                                               from: Data(#""WHATEVER""#.utf8))
        #expect(decoded == .sensitive)
        #expect(!decoded.canRenderInline)
        #expect(NativeObjectPrivacyClass.conversational.canRenderInline)
    }

    @Test("Un cycle de vie inconnu exige une requête, jamais une conclusion")
    func unknownLifecycleRequiresRequery() throws {
        let decoded = try JSONDecoder().decode(NativeObjectLifecycle.self,
                                               from: Data(#""LEVITATING""#.utf8))
        #expect(decoded == .unknown)
        #expect(decoded.requiresRequery)
        #expect(!decoded.isTerminal)
    }

    // MARK: - Défauts fermés

    @Test("Les défauts fermés des chapitres 51 et 52 refusent tout")
    func closedDefaultsRefuse() async {
        let idempotency = IdempotencyContext.new(deviceID: "device")

        #expect(await ClosedCampaignManager().campaigns(cursor: nil).isFailureResult)
        #expect(await ClosedCampaignManager()
            .contribute(ContributionIntent(campaignID: "c-1", amount: money(1_000)),
                        idempotency: idempotency, stepUp: nil).isFailureResult)
        #expect(await ClosedNativeAppObjectProvider().registry().isFailureResult)
        #expect(await ClosedNativeAppObjectProvider()
            .resolve(appID: "a", objectType: "o", objectID: "1").isFailureResult)
    }
}

private extension Result {
    var isFailureResult: Bool {
        if case .failure = self { return true }
        return false
    }
}
