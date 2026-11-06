import Testing
import Foundation
@testable import WaanguCoreKit

/// Factures et liens de paiement — Bloc 6, chapitre 46.
///
/// Couvre P0-3 (détection de mutation de facture) et P0-4 (révocation et
/// rejeu des liens de paiement).
@Suite("Bloc 6 — factures et liens")
struct Bloc6InvoiceLinkTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)

    private func money(_ value: Int64) -> Money { Money(minorUnits: value, currency: bif) }

    private func invoice(
        state: InvoiceState = .issued,
        version: Int = 3,
        contentHash: String = "h-abc",
        amountDue: Int64 = 5_000,
        paid: Int64 = 0,
        allowsPartial: Bool = true,
        installments: [InvoiceInstallment] = [],
        expiresAt: Date? = nil
    ) -> Invoice {
        Invoice(
            id: "inv-1", merchantID: "m-1", merchantNameKey: "Boutique", number: "F-2026-001",
            state: state, lines: [], subtotal: money(5_000), total: money(5_000),
            paidAmount: money(paid), amountDue: money(amountDue),
            installments: installments, allowsPartialPayment: allowsPartial,
            issuedAt: Date(), expiresAt: expiresAt,
            version: version, contentHash: contentHash
        )
    }

    // MARK: - Détection de mutation (P0-3)

    /// Le cas grave du §46 : contenu modifié **à version constante**. Le
    /// compteur seul ne l'aurait pas vu.
    @Test("Un contenu modifié à version constante est une mutation silencieuse")
    func silentContentChangeIsDetected() {
        let pinned = invoice(version: 3, contentHash: "h-abc").snapshot()
        let tampered = invoice(version: 3, contentHash: "h-xyz")

        #expect(pinned.mutation(comparedTo: tampered) == .silentContentChange)
    }

    /// Une modification déclarée reste une modification : elle doit être relue,
    /// mais elle n'a pas la même gravité.
    @Test("Contenu et version modifiés ensemble : modification déclarée")
    func declaredContentChange() {
        let pinned = invoice(version: 3, contentHash: "h-abc").snapshot()
        let updated = invoice(version: 4, contentHash: "h-xyz")

        #expect(pinned.mutation(comparedTo: updated) == .contentChanged)
    }

    @Test("Une version seule qui change est signalée")
    func versionChangeDetected() {
        let pinned = invoice(version: 3, contentHash: "h-abc").snapshot()
        #expect(pinned.mutation(comparedTo: invoice(version: 4, contentHash: "h-abc")) == .versionChanged)
    }

    /// Un montant dû qui bouge à contenu et version constants — un acompte
    /// versé par un autre payeur, par exemple.
    @Test("Un montant dû modifié est signalé")
    func amountChangeDetected() {
        let pinned = invoice(amountDue: 5_000).snapshot()
        #expect(pinned.mutation(comparedTo: invoice(amountDue: 3_000)) == .amountChanged)
    }

    @Test("Une facture inchangée ne produit aucune mutation")
    func noMutationWhenIdentical() {
        let source = invoice()
        #expect(source.snapshot().mutation(comparedTo: source) == nil)
    }

    /// Seul `unchanged` laisse enchaîner. Traiter `mutated` comme un feu vert
    /// ferait payer un document que l'utilisateur n'a jamais lu.
    @Test("Seul .unchanged autorise le paiement immédiat")
    func onlyUnchangedPermitsPayment() {
        #expect(InvoiceVerdict.unchanged.permitsImmediatePayment)
        #expect(!InvoiceVerdict.mutated(.silentContentChange, fresh: invoice()).permitsImmediatePayment)
        #expect(!InvoiceVerdict.cancelled(reasonKey: "k").permitsImmediatePayment)
        #expect(!InvoiceVerdict.expired.permitsImmediatePayment)
    }

    // MARK: - États et payabilité

    /// Trois états seulement admettent un paiement. `unknown` n'en fait pas
    /// partie : envoyer de l'argent sur un état incompris est exclu.
    @Test("Seuls issued, viewed et partiallyPaid acceptent un paiement")
    func onlyThreeStatesAcceptPayment() {
        #expect(InvoiceState.issued.acceptsPayment)
        #expect(InvoiceState.viewed.acceptsPayment)
        #expect(InvoiceState.partiallyPaid.acceptsPayment)
        #expect(!InvoiceState.draft.acceptsPayment)
        #expect(!InvoiceState.cancelled.acceptsPayment)
        #expect(!InvoiceState.unknown.acceptsPayment)
    }

    @Test("Un état de facture inconnu devient .unknown, pas une erreur")
    func unknownInvoiceStateDegrades() throws {
        let decoded = try JSONDecoder().decode(InvoiceState.self, from: Data(#""SOMETHING""#.utf8))
        #expect(decoded == .unknown)
        #expect(!decoded.acceptsPayment)
    }

    /// Une facture expirée reste consultable — c'est une pièce comptable — mais
    /// elle ne se paie plus.
    @Test("Une facture expirée n'est plus payable")
    func expiredInvoiceIsNotPayable() {
        let now = Date()
        #expect(!invoice(expiresAt: now.addingTimeInterval(-1)).isPayable(at: now))
        #expect(invoice(expiresAt: now.addingTimeInterval(600)).isPayable(at: now))
    }

    @Test("Une facture entièrement réglée n'est plus payable")
    func settledInvoiceIsNotPayable() {
        #expect(!invoice(amountDue: 0).isPayable())
    }

    // MARK: - Affectation du paiement

    /// Un acompte sur une facture qui n'admet pas les paiements partiels est
    /// mal formé, quel que soit son montant.
    @Test("Un acompte exige que la facture l'autorise")
    func partialRequiresPermission() {
        #expect(PaymentAllocation.partial(money(2_000))
            .isWellFormed(on: invoice(allowsPartial: true)))
        #expect(!PaymentAllocation.partial(money(2_000))
            .isWellFormed(on: invoice(allowsPartial: false)))
    }

    /// Un versement supérieur au dû n'est pas un acompte : c'est une erreur.
    @Test("Un acompte supérieur au montant dû est mal formé")
    func partialCannotExceedAmountDue() {
        #expect(!PaymentAllocation.partial(money(9_000))
            .isWellFormed(on: invoice(amountDue: 5_000)))
        #expect(PaymentAllocation.partial(money(5_000))
            .isWellFormed(on: invoice(amountDue: 5_000)))
    }

    /// Deux devises différentes ne se règlent pas l'une par l'autre.
    @Test("Un acompte dans une autre devise est mal formé")
    func partialCurrencyMustMatch() {
        let cad = Money(minorUnits: 100, currency: CurrencyCode(code: "CAD", exponent: 2))
        #expect(!PaymentAllocation.partial(cad).isWellFormed(on: invoice()))
    }

    @Test("Une échéance déjà réglée ne se repaie pas")
    func settledInstallmentIsRejected() {
        let settled = InvoiceInstallment(id: "i-1", number: 1, amount: money(1_000),
                                         dueAt: Date(), isSettled: true)
        let open = InvoiceInstallment(id: "i-2", number: 2, amount: money(1_000),
                                      dueAt: Date(), isSettled: false)
        let target = invoice(installments: [settled, open])

        #expect(!PaymentAllocation.installment(id: "i-1").isWellFormed(on: target))
        #expect(PaymentAllocation.installment(id: "i-2").isWellFormed(on: target))
        // Une échéance qui n'existe pas non plus.
        #expect(!PaymentAllocation.installment(id: "i-9").isWellFormed(on: target))
    }

    // MARK: - Liens de paiement (P0-4)

    private func link(
        amount: PaymentLinkAmount = .fixed(Money(minorUnits: 1_000,
                                                 currency: CurrencyCode(code: "BIF", exponent: 0))),
        usage: PaymentLinkUsage = .singleUse,
        expiresAt: Date? = nil,
        isPayable: Bool = true,
        permissions: Set<FinancialPermission> = [.execute]
    ) -> ResolvedPaymentLink {
        ResolvedPaymentLink(
            id: "l-1", target: .invoice(id: "inv-1"),
            payee: FinancialActor(actorID: "m-1", type: .merchant, displayName: "Boutique",
                                  verification: .verified, permissions: permissions),
            amount: amount, usage: usage, expiresAt: expiresAt,
            isPayable: isPayable, isExternalOrigin: false
        )
    }

    /// Un lien expiré ne s'utilise plus, même si le serveur l'avait dit payable
    /// au moment de la résolution : l'écran a pu rester ouvert.
    @Test("Un lien expiré n'est plus utilisable")
    func expiredLinkIsUnusable() {
        let now = Date()
        #expect(!link(expiresAt: now.addingTimeInterval(-1)).isUsable(at: now))
        #expect(link(expiresAt: now.addingTimeInterval(600)).isUsable(at: now))
    }

    @Test("Un bénéficiaire sans droit d'exécution rend le lien inutilisable")
    func payeeWithoutExecuteIsUnusable() {
        #expect(!link(permissions: [.read]).isUsable())
    }

    /// L'interdiction centrale du §46 : un montant indicatif ne devient jamais
    /// ferme par le seul fait d'être affiché.
    @Test("Un montant indicatif n'est pas payable en l'état")
    func indicativeAmountIsNotPayable() {
        let amount = Money(minorUnits: 1_000, currency: bif)
        #expect(PaymentLinkAmount.fixed(amount).isPayableAsIs)
        #expect(PaymentLinkAmount.open(minimum: nil, maximum: nil).isPayableAsIs)
        #expect(!PaymentLinkAmount.indicative(amount).isPayableAsIs)
    }

    /// Un lien de nature inconnue est traité comme à usage unique. L'inverse
    /// le rendrait payable plusieurs fois.
    @Test("Un usage inconnu retombe sur le plus restrictif")
    func unknownUsageFallsBackToSingleUse() throws {
        let decoded = try JSONDecoder().decode(PaymentLinkUsage.self, from: Data(#""WHATEVER""#.utf8))
        #expect(decoded == .singleUse)
    }

    /// Révoquer un lien déjà consommé, révoqué ou expiré n'a pas d'objet.
    @Test("Seul un lien actif et non expiré est révocable")
    func onlyActiveLinksAreRevocable() {
        let now = Date()
        func issued(_ state: PaymentLinkState, expires: Date?) -> IssuedPaymentLink {
            IssuedPaymentLink(
                id: "l-1", url: URL(string: "https://example.test/l/1")!,
                usage: .singleUse,
                amount: .fixed(Money(minorUnits: 1_000, currency: bif)),
                issuedAt: now, expiresAt: expires, state: state
            )
        }

        #expect(issued(.active, expires: now.addingTimeInterval(600)).isRevocable(at: now))
        #expect(!issued(.active, expires: now.addingTimeInterval(-1)).isRevocable(at: now))
        #expect(!issued(.consumed, expires: nil).isRevocable(at: now))
        #expect(!issued(.revoked, expires: nil).isRevocable(at: now))
        #expect(!issued(.expired, expires: nil).isRevocable(at: now))
    }

    // MARK: - Défauts fermés

    @Test("Les défauts fermés du chapitre 46 refusent tout")
    func closedDefaultsRefuse() async {
        let idempotency = IdempotencyContext.new(deviceID: "device")

        #expect(await ClosedInvoiceProvider().invoice(id: "inv-1").isFailureResult)
        #expect(await ClosedInvoiceProvider().revalidate(invoice().snapshot()).isFailureResult)
        #expect(await ClosedPaymentLinkResolver().resolve(token: "t", nonce: "n").isFailureResult)
        #expect(await ClosedPaymentLinkResolver()
            .revoke(linkID: "l-1", idempotency: idempotency).isFailureResult)
    }
}

private extension Result {
    var isFailureResult: Bool {
        if case .failure = self { return true }
        return false
    }
}
