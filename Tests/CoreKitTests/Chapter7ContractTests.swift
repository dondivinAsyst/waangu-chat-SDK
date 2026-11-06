import Testing
import Foundation
@testable import WaanguCoreKit

/// Les garde-fous du chapitre 7 — QR présenté, marchand, commerce, formulaires.
///
/// Chaque test couvre une décision qui, prise de travers, coûte de l'argent ou
/// de la confiance : un QR rejouable, un marchand révoqué payé quand même, une
/// commande annulable après coup, un champ inconnu rendu en saisie libre.
@Suite("Chapitre 7 — contrats")
struct Chapter7ContractTests {

    // MARK: - QR présenté

    private func qr(
        issuedAt: Date, expiresAt: Date, rotateAfter: TimeInterval?
    ) -> PresentableQR {
        PresentableQR(
            id: "qr-1", payload: "signed-payload", kind: .user,
            issuedAt: issuedAt, expiresAt: expiresAt, rotateAfter: rotateAfter
        )
    }

    @Test("Un QR expiré n'est plus valide")
    func expiredQRIsInvalid() {
        let now = Date()
        let code = qr(issuedAt: now.addingTimeInterval(-120),
                      expiresAt: now.addingTimeInterval(-1), rotateAfter: nil)

        #expect(!code.isValid(at: now))
        #expect(code.isValid(at: now.addingTimeInterval(-30)))
    }

    @Test("La rotation se déclenche à l'échéance fixée par le backend")
    func rotationFiresAtBackendDeadline() {
        let now = Date()
        let code = qr(issuedAt: now.addingTimeInterval(-60),
                      expiresAt: now.addingTimeInterval(300), rotateAfter: 45)

        #expect(code.needsRotation(at: now))
        #expect(!code.needsRotation(at: now.addingTimeInterval(-30)))
    }

    /// Sans consigne de rotation, l'écran n'en invente pas une : redemander une
    /// charge utile que le backend ne fait pas tourner produirait un appel par
    /// seconde pour rien.
    @Test("Sans rotateAfter, aucune rotation n'est inventée")
    func noRotationWithoutInstruction() {
        let now = Date()
        let code = qr(issuedAt: now.addingTimeInterval(-3600),
                      expiresAt: now.addingTimeInterval(3600), rotateAfter: nil)

        #expect(!code.needsRotation(at: now))
    }

    // MARK: - Marchand

    private func merchant(
        verification: VerificationStatus,
        permissions: Set<FinancialPermission>,
        accepts: Bool
    ) -> MerchantProfile {
        MerchantProfile(
            actor: FinancialActor(
                actorID: "m-1", type: .merchant, displayName: "Boutique",
                verification: verification, permissions: permissions
            ),
            acceptsPayments: accepts,
            identityVersion: "id-v1", policyVersion: "pol-v1"
        )
    }

    @Test("Un marchand vérifié, ouvert et autorisé est payable")
    func payableMerchant() {
        #expect(merchant(verification: .verified, permissions: [.execute], accepts: true).isPayable)
    }

    /// Les trois conditions sont distinctes. Un marchand révoqué reste
    /// consultable — payer un compte que l'opérateur a désavoué, non.
    @Test("Vérification retirée, droit manquant ou boutique fermée : non payable")
    func unpayableMerchants() {
        #expect(!merchant(verification: .revoked, permissions: [.execute], accepts: true).isPayable)
        #expect(!merchant(verification: .verified, permissions: [.read], accepts: true).isPayable)
        #expect(!merchant(verification: .verified, permissions: [.execute], accepts: false).isPayable)
    }

    // MARK: - Commerce

    private func order(
        state: CommerceOrderState,
        cancellableUntil: Date? = nil,
        returnableUntil: Date? = nil
    ) -> CommerceOrder {
        CommerceOrder(
            id: "o-1", merchantID: "m-1", merchantNameKey: "Boutique", state: state,
            lines: [], total: Money(minorUnits: 1000, currency: CurrencyCode(code: "BIF", exponent: 0)),
            placedAt: Date(), updatedAt: Date(),
            cancellableUntil: cancellableUntil, returnableUntil: returnableUntil
        )
    }

    /// La fenêtre **et** l'état doivent l'autoriser. Une commande expédiée ne
    /// s'annule pas, même dans les délais : le colis est parti.
    @Test("L'annulation demande la fenêtre et un état qui l'autorise")
    func cancellationNeedsBoth() {
        let now = Date()
        let open = now.addingTimeInterval(600)
        let past = now.addingTimeInterval(-600)

        #expect(order(state: .paid, cancellableUntil: open).isCancellable(at: now))
        #expect(!order(state: .paid, cancellableUntil: past).isCancellable(at: now))
        #expect(!order(state: .shipped, cancellableUntil: open).isCancellable(at: now))
        #expect(!order(state: .paid).isCancellable(at: now))
    }

    @Test("Le retour n'existe qu'après livraison, et dans sa fenêtre")
    func returnNeedsDelivery() {
        let now = Date()
        let open = now.addingTimeInterval(86_400)

        #expect(order(state: .delivered, returnableUntil: open).isReturnable(at: now))
        #expect(!order(state: .shipped, returnableUntil: open).isReturnable(at: now))
        #expect(!order(state: .delivered).isReturnable(at: now))
    }

    /// Un état inconnu dégrade **une ligne**, il n'efface pas l'historique :
    /// faire échouer le décodage viderait toute la liste des commandes.
    @Test("Un état de commande inconnu devient .unknown, pas une erreur")
    func unknownOrderStateDegrades() throws {
        let decoded = try JSONDecoder().decode(
            CommerceOrderState.self, from: Data(#""SOMETHING_NEW""#.utf8)
        )
        #expect(decoded == .unknown)
        // Et surtout pas un état qui laisserait croire à une livraison.
        #expect(decoded != .delivered)
    }

    @Test("Un panier vide ou bloqué ne se commande pas")
    func cartOrderability() {
        let zero = Money(minorUnits: 0, currency: CurrencyCode(code: "BIF", exponent: 0))
        let line = CommerceCartLine(
            itemID: "i-1", nameKey: "Article", quantity: 1,
            unitPrice: zero, lineTotal: zero
        )

        #expect(CommerceCart(id: "c", merchantID: "m", lines: [line],
                             subtotal: zero, total: zero).isOrderable)
        #expect(!CommerceCart(id: "c", merchantID: "m", lines: [],
                              subtotal: zero, total: zero).isOrderable)
        #expect(!CommerceCart(id: "c", merchantID: "m", lines: [line],
                              subtotal: zero, total: zero,
                              blockingReasonKeys: ["OUT_OF_STOCK"]).isOrderable)
    }

    @Test("Un retour sans ligne ou sans motif n'est pas soumettable")
    func returnRequestValidation() {
        #expect(CommerceReturnRequest(orderID: "o", lines: ["i": 1],
                                      kind: .refund, reasonKey: "DAMAGED").isSubmittable)
        #expect(!CommerceReturnRequest(orderID: "o", lines: [:],
                                       kind: .refund, reasonKey: "DAMAGED").isSubmittable)
        #expect(!CommerceReturnRequest(orderID: "o", lines: ["i": 0],
                                       kind: .refund, reasonKey: "DAMAGED").isSubmittable)
        #expect(!CommerceReturnRequest(orderID: "o", lines: ["i": 1],
                                       kind: .refund, reasonKey: "").isSubmittable)
    }

    // MARK: - Formulaires distants

    /// Le point entier du type `.unsupported`. Retomber sur `.text` ferait
    /// taper du texte libre là où le partenaire attend une valeur de liste.
    @Test("Un type de champ inconnu devient .unsupported, jamais .text")
    func unknownFieldKindIsUnsupported() throws {
        let decoded = try JSONDecoder().decode(
            RemoteFormFieldKind.self, from: Data(#""account_picker""#.utf8)
        )
        #expect(decoded == .unsupported)
        #expect(decoded != .text)
    }

    @Test("Les types connus se décodent sans tenir compte de la casse")
    func knownFieldKindsDecode() throws {
        let decoded = try JSONDecoder().decode(
            RemoteFormFieldKind.self, from: Data(#""SELECT""#.utf8)
        )
        #expect(decoded == .select)
    }

    /// Un champ requis invisible serait envoyé vide : le formulaire doit se
    /// bloquer plutôt que d'échouer côté serveur sans explication.
    @Test("Un champ requis non rendable bloque le formulaire")
    func unrenderableRequiredFieldBlocks() {
        let form = RemoteForm(
            id: "f-1", version: "v3", titleKey: "Titre",
            fields: [
                RemoteFormField(name: "a", labelKey: "A", kind: .text, isRequired: true),
                RemoteFormField(name: "b", labelKey: "B", kind: .unsupported, isRequired: true)
            ]
        )
        #expect(form.unrenderableRequiredFields().map(\.name) == ["b"])
    }

    /// Un champ **facultatif** d'un type inconnu ne bloque rien : on ne peut
    /// pas le saisir, mais personne ne l'attend.
    @Test("Un champ facultatif non rendable ne bloque pas")
    func unrenderableOptionalFieldDoesNotBlock() {
        let form = RemoteForm(
            id: "f-1", version: "v3", titleKey: "Titre",
            fields: [RemoteFormField(name: "b", labelKey: "B", kind: .unsupported, isRequired: false)]
        )
        #expect(form.unrenderableRequiredFields().isEmpty)
    }

    // MARK: - Défauts fermés

    /// Aucun défaut ne fabrique de données. Un catalogue factice fait commander
    /// des articles qui n'existent pas, et l'erreur n'apparaît qu'après paiement.
    @Test("Les défauts du chapitre 7 refusent tout")
    func closedDefaultsRefuse() async {
        let reference = FinancialReference(
            type: .payment, id: "p-1", version: 1, correlationID: CorrelationId()
        )
        let idempotency = IdempotencyContext.new(deviceID: "device")

        #expect(await ClosedQRPresenter().issue(.init(kind: .user)).isFailure)
        #expect(await ClosedMerchantProfileProvider().profile(merchantID: "m").isFailure)
        #expect(await ClosedCommerceOrdering().catalog(merchantID: "m", cursor: nil).isFailure)
        #expect(await ClosedCommerceOrdering().orders(cursor: nil).isFailure)
        #expect(await ClosedRemoteFormProvider().form(id: "f", context: [:]).isFailure)
        #expect(await ClosedSupportCaseOpener().context(for: reference).isFailure)
        #expect(await ClosedSupportCaseOpener()
            .open(contextID: "c", messageText: "x", idempotency: idempotency).isFailure)
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

/// Les portes du §16 et la saisie de bénéficiaire — Bloc 5, ch. 35 et §16.
@Suite("Portes de capacité et bénéficiaires")
struct CapabilityAndRecipientTests {

    private func capability(
        licensed: Bool = true, compliance: Bool = true,
        partner: Bool = true, enabled: Bool = true,
        from: Date = .distantPast, until: Date? = nil
    ) -> FinancialCapability {
        FinancialCapability(
            capabilityID: "REMITTANCE", country: "BI", enabled: enabled,
            licensed: licensed, complianceApproved: compliance,
            partnerApproved: partner, effectiveFrom: from,
            effectiveUntil: until, configVersion: "v1"
        )
    }

    @Test("Les quatre portes ouvertes rendent la capacité disponible")
    func allOpen() {
        #expect(capability().isAvailable())
        #expect(capability().closure() == nil)
    }

    /// L'ordre du contrôle est délibéré : on rapporte la cause la plus
    /// structurelle, celle qui ne se lèvera pas d'elle-même. Une licence
    /// manquante n'a pas la même réponse qu'une revue de conformité en cours.
    @Test("La cause la plus structurelle l'emporte")
    func mostStructuralClosureWins() {
        #expect(capability(licensed: false, compliance: false, partner: false,
                           enabled: false).closure() == .notLicensed)
        #expect(capability(compliance: false, partner: false,
                           enabled: false).closure() == .complianceWithheld)
        #expect(capability(partner: false, enabled: false).closure() == .partnerWithheld)
        #expect(capability(enabled: false).closure() == .notEnabled)
    }

    /// La fenêtre d'effet prime sur tout le reste : une capacité pas encore
    /// ouverte n'est pas « non licenciée », et le dire orienterait mal le
    /// support.
    @Test("La fenêtre d'effet est contrôlée en premier")
    func effectiveWindowFirst() {
        let now = Date()
        #expect(capability(licensed: false,
                           from: now.addingTimeInterval(3600)).closure(asOf: now) == .notYetEffective)
        #expect(capability(licensed: false,
                           until: now.addingTimeInterval(-1)).closure(asOf: now) == .expired)
    }

    /// Le silence du backend n'est pas une autorisation.
    @Test("Une capacité absente du catalogue est fermée")
    func absentCapabilityIsClosed() async {
        struct EmptyGates: FinancialCapabilityGateProviding {
            func capabilities() async -> [FinancialCapability] { [] }
            func invalidate() async {}
        }
        #expect(await EmptyGates().closure(for: "REMITTANCE") == .notEnabled)
        #expect(await EmptyGates().isAvailable("REMITTANCE") == false)
    }

    /// L'opérateur Mobile Money est **fourni**, jamais déduit du préfixe : la
    /// portabilité rend toute déduction fausse tôt ou tard.
    @Test("Le bénéficiaire Mobile Money porte son opérateur")
    func mobileMoneyCarriesOperator() {
        let input = RecipientInput.mobileMoney(operatorID: "ECOCASH", msisdn: "25761234567")
        guard case .mobileMoney(let operatorID, let msisdn) = input else {
            Issue.record("mauvaise variante")
            return
        }
        #expect(operatorID == "ECOCASH")
        #expect(msisdn == "25761234567")
    }

    /// Le code institution et l'agence ne s'appliquent pas partout : les rendre
    /// obligatoires bloquerait les corridors qui n'en ont pas.
    @Test("Un compte bancaire se compose sans code institution ni agence")
    func bankAccountWithoutOptionalFields() {
        let account = BankAccountInput(
            countryCode: "CA", accountNumber: "1234567",
            accountHolderName: "A. Ndikumana"
        )
        #expect(account.institutionCode == nil)
        #expect(account.branchCode == nil)
        #expect(account.accountHolderName == "A. Ndikumana")
    }
}
