//
//  FinanceTranslationKeys.swift
//  FeatureChat
//
//  Terminologie financière centralisée — Bloc 3 §27.
//

import Foundation
import WaanguCoreKit

/// Toutes les chaînes affichées par la surface financière, en un seul endroit.
///
/// **Le seul fichier du dossier `Presentation/Finance` autorisé à contenir un
/// littéral d'affichage.** C'est ce que `ci_forbid_hardcoded_strings.sh` vérifie :
/// une chaîne financière écrite dans une vue échappe à GEORGES, et se retrouve
/// en français dans une application anglophone.
///
/// Le français est ici la **valeur de repli**, pas la traduction : quand le
/// catalogue de traductions existera, `NSLocalizedString` la remplacera sans
/// toucher aux vues.
/// Clés du module `finance` de TranslationKit.
///
/// `FinanceStrings` (ci-dessous) résout par `NSLocalizedString`, que ce module
/// n'alimente d'aucun catalogue `.strings` : chacun de ses ~200 libellés rend
/// donc son repli français, dans les quatre langues. Le moteur du projet est
/// TranslationKit, et c'est par lui que passent les nouvelles clés.
///
/// La migration du reste de `FinanceStrings` est une tâche à part entière et
/// n'est pas faite ici.
public enum FinanceTranslationKeys {

    public static let MODULE = "finance"

    /// Clé d'un libellé d'entrée, dérivée de sa nature.
    ///
    /// Le catalogue backend transporte sa propre `titleKey` ; celle-ci sert de
    /// repli quand elle ne résout pas — la nature est un type fermé, donc
    /// toujours traduisible.
    public static func entryKey(for kind: FinanceEntryKind) -> String {
        "entry_" + kind.rawValue.lowercased()
    }

    public static let ENTRY_NOT_BUILT  = "entry_not_built"
    public static let ENTRY_UNAVAILABLE = "entry_unavailable"
}

public enum FinanceStrings {

    /// Résolution par TranslationKit, avec repli français.
    ///
    /// Passait par `NSLocalizedString`, que ce module n'alimente d'aucun
    /// catalogue : les deux cents libellés ci-dessous rendaient donc leur repli
    /// français dans les quatre langues.
    private static func t(_ key: String, _ fallback: String) -> String {
        FinanceLocalization.string(key, fallback: fallback)
    }

    // MARK: Hub

    public static var hubTitle: String { t("finance.hub.title", "Paiements") }
    public static var hubLoading: String { t("finance.hub.loading", "Chargement des services…") }
    public static var hubEmptyTitle: String {
        t("finance.hub.empty.title", "Aucun service de paiement disponible")
    }
    public static var hubEmptyDetail: String {
        t("finance.hub.empty.detail",
          "Les services proposés dépendent de votre pays et de votre profil.")
    }
    public static var hubUnavailableTitle: String {
        t("finance.hub.unavailable.title", "Services de paiement indisponibles")
    }
    public static var hubUnavailableDetail: String {
        t("finance.hub.unavailable.detail",
          "Cette fonctionnalité n'est pas activée sur cet appareil.")
    }
    public static var entryNotBuiltYet: String {
        t("finance.entry.not_built",
          "Ce service n'est pas encore disponible dans les conversations.")
    }
    public static var groupNotSupported: String {
        t("finance.entry.group_unsupported",
          "Les opérations de groupe ne sont pas encore disponibles.")
    }

    // MARK: Commun

    public static var cancel: String { t("finance.common.cancel", "Annuler") }
    public static var close: String { t("finance.common.close", "Fermer") }
    /// Ferme le clavier d'un champ multiligne, dont la touche Retour insère une ligne.
    public static var keyboardDone: String { t("finance.common.keyboard_done", "OK") }

    // MARK: Choix d'un contact

    public static var recipientPickTitle: String { t("finance.recipient.pick_title", "Choisir un bénéficiaire") }
    public static var recipientScanQR: String { t("finance.recipient.scan_qr", "Scanner un code") }
    public static var recipientNone: String { t("finance.recipient.none", "Aucun contact à afficher") }
    public static var recipientScanHint: String { t("finance.recipient.scan_hint", "Ou scannez le code de la personne") }
    public static var recipientBlocked: String { t("finance.recipient.blocked", "Ce bénéficiaire ne peut pas être payé.") }
    public static var recipientSearch: String { t("finance.recipient.search", "Rechercher un nom ou un numéro") }
    public static var recipientNoResults: String {
        t("finance.recipient.no_results", "Aucun contact ne correspond à votre recherche")
    }

    // MARK: - Marchand et commerce (ch. 7)

    public static var merchantTitle: String { t("finance.merchant.title", "Marchand") }
    public static var merchantLoading: String { t("finance.merchant.loading", "Chargement du marchand…") }
    public static var merchantVerified: String { t("finance.merchant.verified", "Marchand vérifié") }
    public static var merchantWarning: String {
        t("finance.merchant.warning", "Vérification retirée — prudence")
    }
    public static var merchantAbout: String { t("finance.merchant.about", "À propos") }
    public static var merchantPayTitle: String { t("finance.merchant.pay", "Payer ce marchand") }
    public static var merchantReference: String {
        t("finance.merchant.reference", "Référence (facultatif)")
    }
    public static var merchantNotPayable: String {
        t("finance.merchant.not_payable", "Ce marchand n'accepte pas de paiement pour le moment.")
    }
    public static var merchantRevalidating: String {
        t("finance.merchant.revalidating", "Vérification du marchand…")
    }
    public static var merchantIdentityChangedTitle: String {
        t("finance.merchant.identity_changed_title", "Le marchand a changé")
    }
    public static var merchantIdentityChangedDetail: String {
        t("finance.merchant.identity_changed_detail",
          "Les informations de ce marchand ont été modifiées depuis l'ouverture de cet écran. Relisez-les avant de payer.")
    }
    public static var merchantReviewProfile: String {
        t("finance.merchant.review_profile", "Revoir le marchand")
    }
    public static var merchantNotIdentified: String {
        t("finance.merchant.not_identified", "Ce marchand n'est pas identifié pour cette conversation.")
    }
    public static var merchantBrowseCatalog: String {
        t("finance.merchant.browse", "Voir le catalogue")
    }
    public static var merchantReturnPolicy: String {
        t("finance.merchant.return_policy", "Politique de retour")
    }
    public static var quoteNotExecutable: String {
        t("finance.quote.not_executable", "Ce devis ne peut pas être exécuté.")
    }

    public static var catalogTitle: String { t("finance.catalog.title", "Catalogue") }
    public static var catalogLoading: String { t("finance.catalog.loading", "Chargement du catalogue…") }
    public static var catalogEmpty: String {
        t("finance.catalog.empty", "Ce marchand ne publie aucun article.")
    }
    public static var catalogAdd: String { t("finance.catalog.add", "Ajouter au panier") }
    public static var catalogUnavailable: String { t("finance.catalog.unavailable", "Indisponible") }
    /// Format à un entier : le stock restant.
    public static var catalogLowStock: String { t("finance.catalog.low_stock", "Plus que %d en stock") }

    public static var cartTitle: String { t("finance.cart.title", "Panier") }
    public static var cartOpen: String { t("finance.cart.open", "Ouvrir le panier") }
    public static var cartLoading: String { t("finance.cart.loading", "Chargement du panier…") }
    public static var cartEmpty: String { t("finance.cart.empty", "Votre panier est vide.") }
    public static var cartQuantity: String { t("finance.cart.quantity", "Quantité") }
    public static var cartSubtotal: String { t("finance.cart.subtotal", "Sous-total") }
    public static var cartDelivery: String { t("finance.cart.delivery", "Livraison") }
    public static var cartDeliveryFee: String { t("finance.cart.delivery_fee", "Frais de livraison") }
    /// Format à un entier : le nombre de jours.
    public static var cartDeliveryDays: String { t("finance.cart.delivery_days", "Environ %d jours") }
    public static var cartTax: String { t("finance.cart.tax", "Taxes") }
    public static var cartPriceChanged: String {
        t("finance.cart.price_changed", "Le prix a changé depuis l'ajout")
    }
    public static var cartPlaceOrder: String { t("finance.cart.place_order", "Commander") }
    public static var cartPlaceOrderNote: String {
        t("finance.cart.place_order_note",
          "Commander ne débite rien. Le paiement se fait à l'étape suivante.")
    }
    public static var cartPlacing: String { t("finance.cart.placing", "Création de la commande…") }
    public static var cartPlacedTitle: String { t("finance.cart.placed_title", "Commande enregistrée") }
    /// Format à une chaîne : le total.
    public static var cartPlacedDetail: String {
        t("finance.cart.placed_detail", "Total à régler : %@")
    }

    public static var ordersTitle: String { t("finance.orders.title", "Mes commandes") }
    public static var ordersLoading: String { t("finance.orders.loading", "Chargement des commandes…") }
    public static var ordersEmpty: String { t("finance.orders.empty", "Aucune commande.") }
    public static var orderTitle: String { t("finance.order.title", "Commande") }
    public static var orderWorking: String { t("finance.order.working", "Traitement en cours…") }
    public static var orderItems: String { t("finance.order.items", "Articles") }
    public static var orderTracking: String { t("finance.order.tracking", "Suivi") }
    public static var orderPay: String { t("finance.order.pay", "Payer la commande") }
    public static var orderCancel: String { t("finance.order.cancel", "Annuler la commande") }
    public static var orderReturn: String { t("finance.order.return", "Ouvrir un retour") }

    public static var orderStateAwaitingPayment: String {
        t("finance.order.state.awaiting_payment", "En attente de paiement")
    }
    public static var orderStatePaid: String { t("finance.order.state.paid", "Payée") }
    public static var orderStateAccepted: String { t("finance.order.state.accepted", "Acceptée") }
    public static var orderStatePreparing: String { t("finance.order.state.preparing", "En préparation") }
    public static var orderStateShipped: String { t("finance.order.state.shipped", "Expédiée") }
    public static var orderStateDelivered: String { t("finance.order.state.delivered", "Livrée") }
    public static var orderStateCancelled: String { t("finance.order.state.cancelled", "Annulée") }
    public static var orderStateRefunded: String { t("finance.order.state.refunded", "Remboursée") }
    public static var orderStateReturnOpen: String { t("finance.order.state.return_open", "Retour en cours") }
    public static var orderStateUnknown: String {
        t("finance.order.state.unknown", "État non reconnu par cette version")
    }

    // MARK: - Saisie d'un bénéficiaire (ch. 35)

    // MARK: - Parcours
    //
    // Déclarés après coup : `FinanceNavigationScope`, `RequestMoneyView` et les
    // écrans d'espèces les référençaient sans qu'aucun n'ait été compilé.

    public static var flowSetAmount: String { t("finance.flow.set_amount", "Indiquer le montant") }

    public static var flowRequestSent: String { t("finance.flow.request_sent", "Demande envoyée") }

    public static var flowPayerChooses: String { t("finance.flow.payer_chooses", "Le payeur choisit le montant") }

    public static var flowCheckStatus: String { t("finance.flow.check_status", "Vérifier le statut") }

    public static var flowCashInReview: String { t("finance.flow.cash_in_review", "Vérifier le dépôt") }

    public static var flowCashOutReview: String { t("finance.flow.cash_out_review", "Vérifier le retrait") }

    /// Libellé du bouton retour d'un parcours financier.
    ///
    /// Référencé par `FinanceNavigationScope` sans avoir jamais été déclaré :
    /// le fichier est récent et n'avait pas encore été compilé.
    public static var flowBack: String { t("finance.flow.back", "Retour") }

    public static var recipientTitle: String { t("finance.recipient.title", "Bénéficiaire") }
    public static var recipientChoose: String {
        t("finance.recipient.choose", "Choisir un bénéficiaire")
    }
    public static var recipientChange: String { t("finance.recipient.change", "Changer") }
    public static var recipientFromQR: String { t("finance.recipient.from_qr", "Depuis un QR scanné") }
    public static var recipientMethod: String { t("finance.recipient.method", "Type de bénéficiaire") }
    public static var recipientPhone: String { t("finance.recipient.phone", "Numéro de téléphone") }
    public static var recipientHandle: String { t("finance.recipient.handle", "Identifiant Waangu") }
    public static var recipientMobileMoney: String { t("finance.recipient.mobile_money", "Mobile Money") }
    public static var recipientBankAccount: String { t("finance.recipient.bank", "Compte bancaire") }
    public static var recipientCashPickup: String { t("finance.recipient.cash_pickup", "Retrait en espèces") }
    public static var recipientOperator: String { t("finance.recipient.operator", "Opérateur") }
    public static var recipientOperatorNote: String {
        t("finance.recipient.operator_note",
          "Indiquez l'opérateur du bénéficiaire. Il n'est pas déduit du numéro : un numéro porté créditerait le mauvais compte.")
    }
    public static var recipientMsisdn: String { t("finance.recipient.msisdn", "Numéro Mobile Money") }
    public static var recipientHolder: String { t("finance.recipient.holder", "Nom du titulaire") }
    public static var recipientCountry: String { t("finance.recipient.country", "Pays du compte") }
    public static var recipientAccountNumber: String {
        t("finance.recipient.account_number", "IBAN ou numéro de compte")
    }
    public static var recipientOptionalFields: String {
        t("finance.recipient.optional_fields", "Selon le pays")
    }
    public static var recipientInstitution: String {
        t("finance.recipient.institution", "BIC / code établissement")
    }
    public static var recipientBranch: String { t("finance.recipient.branch", "Agence / transit") }
    public static var recipientAgentNetwork: String {
        t("finance.recipient.agent_network", "Réseau d'agents")
    }
    public static var recipientServerValidates: String {
        t("finance.recipient.server_validates",
          "Les coordonnées sont vérifiées par le partenaire avant tout envoi.")
    }

    // MARK: - Cartes et libellés d'écran

    /// Format à une chaîne : la date d'arrêté.
    public static var pfmAsOf: String { t("finance.pfm.as_of", "Arrêté au %@") }
    public static var pfmRevocable: String { t("finance.pfm.revocable", "Révocable") }

    public static var creditExpectedDocuments: String {
        t("finance.credit.expected_documents", "Documents attendus")
    }
    public static var creditOffer: String { t("finance.credit.offer", "Offre") }
    public static var creditOfferExpired: String { t("finance.credit.offer_expired", "Offre expirée") }
    public static var creditSchedule: String { t("finance.credit.schedule", "Échéancier") }
    public static var creditConditions: String { t("finance.credit.conditions", "Conditions") }
    public static var creditAcceptOffer: String { t("finance.credit.accept_offer", "Accepter l'offre") }
    public static var creditAcceptNote: String {
        t("finance.credit.accept_note",
          "Accepter engage un remboursement selon l'échéancier ci-dessus.")
    }
    public static var creditAmount: String { t("finance.credit.amount", "Montant") }

    public static var cardOpenToReply: String { t("finance.card.open_to_reply", "Ouvrir pour répondre") }
    public static var cardPartialRefund: String {
        t("finance.card.partial_refund", "Remboursement partiel")
    }
    public static var cardTrackInWallet: String {
        t("finance.card.track_in_wallet", "Suivi dans le portefeuille")
    }
    public static var cardViewSharesInWallet: String {
        t("finance.card.view_shares", "Voir les parts dans le portefeuille")
    }
    public static var cardQuoteExpired: String {
        t("finance.card.quote_expired", "Devis expiré — reprendre l'opération")
    }
    public static var cardUnauthenticated: String {
        t("finance.card.unauthenticated", "Contenu non authentifié")
    }
    /// Format à une chaîne : le montant des frais.
    public static var cardIncludingFee: String { t("finance.card.including_fee", "dont %@ de frais") }
    /// Titre d'une carte vue dans le fil : le sens compte plus que la nature.
    public static var cardMoneySent: String { t("finance.card.money_sent", "Argent envoyé") }
    public static var cardMoneyReceived: String { t("finance.card.money_received", "Argent reçu") }
    public static var cardTo: String { t("finance.card.to", "À") }
    // MARK: Demande d'argent — carte et réponse (§4)

    public static var requestCardReceivedTitle: String { t("finance.request.card.received_title", "Demande d'argent") }
    public static var requestCardSentTitle: String { t("finance.request.card.sent_title", "Demande envoyée") }
    public static var requestCardAmountAsked: String { t("finance.request.card.amount_asked", "Montant demandé") }
    public static var requestCardYouOwe: String { t("finance.request.card.you_owe", "À payer") }
    public static var requestCardAwaiting: String { t("finance.request.card.awaiting", "En attente de paiement") }
    public static var requestCardPaymentSent: String { t("finance.request.card.payment_sent", "Paiement envoyé") }
    public static var requestCardPaid: String { t("finance.request.card.paid", "Payé") }
    public static var requestCardDeclined: String { t("finance.request.card.declined", "Refusée") }
    public static var requestActionPay: String { t("finance.request.action.pay", "Payer") }
    public static var requestActionDecline: String { t("finance.request.action.decline", "Refuser") }
    public static var requestActionRemind: String { t("finance.request.action.remind", "Relancer") }
    public static var requestDeclineTitle: String { t("finance.request.decline.title", "Refuser la demande ?") }
    public static var requestDeclineDetail: String {
        t("finance.request.decline.detail", "Le demandeur verra que vous avez refusé. Rien n'est débité.")
    }
    public static var requestReminded: String { t("finance.request.reminded", "Relance envoyée.") }
    public static var failurePaymentTitle: String { t("finance.failure.payment_title", "Paiement non effectué") }
    public static var failureNothingCharged: String {
        t("finance.failure.nothing_charged", "Aucun montant n'a été débité.")
    }
    public static var failureRetry: String { t("finance.failure.retry", "Réessayer") }
    public static var requestActionCancel: String { t("finance.request.action.cancel", "Annuler la demande") }
    public static var billCategoryWater: String { t("finance.bill.category.water", "Eau") }
    public static var billCategoryPower: String { t("finance.bill.category.power", "Électricité") }
    public static var billCategoryMedia: String { t("finance.bill.category.media", "TV et câble") }
    public static var billCategoryTelecom: String { t("finance.bill.category.telecom", "Télécom et internet") }
    public static var billCategoryEducation: String { t("finance.bill.category.education", "École et formation") }
    public static var billCategoryOther: String { t("finance.bill.category.other", "Autres factures") }
    public static var billFieldAccountRef: String { t("finance.bill.field.account_ref", "Référence du compte") }
    public static var billFieldCustomerPhone: String { t("finance.bill.field.customer_phone", "Téléphone") }
    public static var billCustomer: String { t("finance.bill.customer", "Client") }
    /// Ni fil, ni dossier personnel : rien ne peut porter l'opération.
    ///
    /// Ce n'est plus « ouvrez une conversation » — le serveur tient un dossier
    /// pour les factures payées hors discussion (§5.1.1). Ce message ne
    /// s'affiche que s'il n'a pas pu le rendre.
    public static var billNeedsConversation: String {
        t("finance.bill.needs_conversation", "Impossible d'ouvrir votre dossier de paiement. Réessayez dans un instant.")
    }
    public static var billFieldMeter: String { t("finance.bill.field.meter", "Numéro de compteur") }
    public static var billFieldInvoiceRef: String { t("finance.bill.field.invoice_ref", "Référence de facture") }
    public static var billFieldPeriod: String { t("finance.bill.field.period", "Période") }
    public static var billFieldChoose: String { t("finance.bill.field.choose", "Choisir") }
    public static var billPeriodMonthCurrent: String { t("finance.bill.period.month_current", "Mois en cours") }
    public static var billPeriodMonthPrevious: String { t("finance.bill.period.month_previous", "Mois précédent") }
    public static var billPeriodArrears: String { t("finance.bill.period.arrears", "Arriérés") }

    /// La raison d'un champ refusé, formulée dans la langue de l'app.
    public static func billFieldError(_ issue: BillFieldIssue, label: String) -> String {
        switch issue {
        case .required:
            return String(format: t("finance.bill.field.error.required", "%@ est obligatoire"), label)
        case .tooShort(let min):
            return String(format: t("finance.bill.field.error.too_short", "%@ : au moins %d caractères"), label, min)
        case .tooLong(let max):
            return String(format: t("finance.bill.field.error.too_long", "%@ : au plus %d caractères"), label, max)
        case .invalidFormat:
            return String(format: t("finance.bill.field.error.format", "%@ : format invalide"), label)
        }
    }
    public static var requestActionLink: String { t("finance.request.action.link", "Lien de paiement") }
    public static var requestLinkTitle: String { t("finance.request.link.title", "Lien de paiement créé") }
    public static var requestLinkDetail: String { t("finance.request.link.detail", "Ce lien ne paie rien : il ouvre la demande, que la personne paie ensuite après confirmation.") }
    public static func requestLinkExpires(_ date: String) -> String { String(format: t("finance.request.link.expires", "Expire le %@"), date) }
    public static var requestLinkCopy: String { t("finance.request.link.copy", "Copier le lien") }
    public static var requestLinkCopied: String { t("finance.request.link.copied", "Copié") }
    public static var requestLinkShare: String { t("finance.request.link.share", "Partager le lien") }
    public static var linkOpenChecking: String { t("finance.link.open.checking", "Vérification du lien…") }
    public static var linkOpenInvalidTitle: String { t("finance.link.open.invalid.title", "Lien de paiement invalide") }
    public static var linkOpenOwn: String { t("finance.link.open.own", "C'est votre propre demande : partagez ce lien avec la personne qui doit payer.") }
    public static var linkOpenNotPayable: String { t("finance.link.open.not.payable", "Cette demande ne peut plus être payée par ce lien.") }
    public static var requestCancelTitle: String { t("finance.request.cancel.title", "Annuler la demande ?") }
    public static var requestCancelDetail: String {
        t("finance.request.cancel.detail", "Elle ne pourra plus être payée.")
    }
    public static var requestCancelRequested: String {
        t("finance.request.cancel.requested", "Annulation demandée. La carte se mettra à jour dès qu'elle sera confirmée.")
    }
    public static var requestPayTitle: String { t("finance.request.pay.title", "Payer la demande") }
    public static var requestPayAmountHint: String { t("finance.request.pay.amount_hint", "Montant à payer") }
    public static var requestPayPreparing: String { t("finance.request.pay.preparing", "Préparation du paiement…") }
    public static var requestPayContinue: String { t("finance.request.pay.continue", "Continuer") }

    public static var cardFinancialOperation: String {
        t("finance.card.financial_operation", "Opération financière")
    }
    public static var cardLoadingDetails: String {
        t("finance.card.loading_details", "Chargement des détails…")
    }
    public static var cardLoadingAccessibility: String {
        t("finance.card.loading_a11y", "Opération financière, détails en cours de chargement")
    }
    public static var cardOpenInWallet: String {
        t("finance.card.open_in_wallet", "Ouvrir dans le portefeuille pour voir le détail")
    }

    public static var billFieldsVerified: String {
        t("finance.bill.fields_verified", "Les champs sont vérifiés par le facturier.")
    }
    public static var topUpOperatorNote: String {
        t("finance.topup.operator_note",
          "L'opérateur est déterminé par le service à partir du numéro.")
    }
    public static var receiptLinkTemporary: String {
        t("finance.receipt.link_temporary", "Ce lien est temporaire et personnel.")
    }
    public static var receiptReference: String { t("finance.receipt.reference", "Référence") }
    public static var receiptVersion: String { t("finance.receipt.version", "Version") }

    // MARK: - Copilot borné (ch. 42, §15)

    public static var copilotTitle: String { t("finance.copilot.title", "Assistant financier") }
    public static var copilotIntro: String {
        t("finance.copilot.intro",
          "L'assistant lit vos données pour vous les expliquer. Il ne peut ni payer, ni transférer, ni modifier quoi que ce soit.")
    }
    public static var copilotTools: String { t("finance.copilot.tools", "Ce qu'il peut consulter") }
    public static var copilotToolAnomalies: String {
        t("finance.copilot.tool.anomalies", "Vos anomalies détectées")
    }
    public static var copilotToolAnomaliesDetail: String {
        t("finance.copilot.tool.anomalies_detail",
          "Lit les anomalies de la période et l'opération qui les a déclenchées.")
    }
    public static var copilotToolBudgets: String {
        t("finance.copilot.tool.budgets", "Vos budgets")
    }
    public static var copilotToolBudgetsDetail: String {
        t("finance.copilot.tool.budgets_detail", "Lit vos budgets et leur consommation.")
    }
    public static var copilotAsk: String { t("finance.copilot.ask", "Analyser") }
    public static var copilotAskAgain: String { t("finance.copilot.ask_again", "Nouvelle analyse") }
    public static var copilotWorking: String { t("finance.copilot.working", "Analyse en cours…") }
    public static var copilotFailed: String {
        t("finance.copilot.failed", "L'analyse n'a pas abouti.")
    }
    public static var copilotNothing: String {
        t("finance.copilot.nothing", "Rien à signaler sur cette période.")
    }
    public static var copilotExceededBudgets: String {
        t("finance.copilot.exceeded_budgets", "Budgets dépassés")
    }
    public static var copilotFindings: String { t("finance.copilot.findings", "Constats") }
    public static var copilotSources: String {
        t("finance.copilot.sources", "Opérations à l'origine de ce constat :")
    }
    public static var copilotReadOnlyNote: String {
        t("finance.copilot.read_only_note",
          "Ces outils ne font que lire. Aucune opération ne peut être déclenchée par l'assistant.")
    }
    public static var copilotProposalNote: String {
        t("finance.copilot.proposal_note",
          "L'assistant propose ; c'est vous qui validez chaque geste dans l'écran correspondant.")
    }

    // MARK: - Factures marchandes (ch. 46)

    public static var invoiceTitle: String { t("finance.invoice.title", "Facture") }
    public static var invoiceLoading: String { t("finance.invoice.loading", "Chargement de la facture…") }
    public static var invoiceRevalidating: String {
        t("finance.invoice.revalidating", "Vérification de la facture…")
    }
    public static var invoiceNotIdentified: String {
        t("finance.invoice.not_identified", "Cette facture n'est pas identifiée pour cette conversation.")
    }
    public static var invoiceLines: String { t("finance.invoice.lines", "Détail") }
    public static var invoiceDiscount: String { t("finance.invoice.discount", "Remise") }
    public static var invoicePaid: String { t("finance.invoice.paid", "Déjà réglé") }
    public static var invoiceAmountDue: String { t("finance.invoice.amount_due", "Reste à payer") }
    public static var invoicePayTitle: String { t("finance.invoice.pay_title", "Régler") }
    public static var invoicePay: String { t("finance.invoice.pay", "Payer") }
    public static var invoicePayFull: String { t("finance.invoice.pay_full", "Solder la facture") }
    public static var invoicePayPartial: String { t("finance.invoice.pay_partial", "Verser un acompte") }
    /// Format à un entier : le numéro d'échéance.
    public static var invoicePayInstallment: String {
        t("finance.invoice.pay_installment", "Régler l'échéance n° %d")
    }
    public static var invoiceNotPayable: String {
        t("finance.invoice.not_payable", "Cette facture ne peut pas être réglée.")
    }
    public static var invoiceExpired: String {
        t("finance.invoice.expired", "Cette facture a expiré.")
    }
    public static var invoiceMultiplePayers: String {
        t("finance.invoice.multiple_payers", "Plusieurs personnes peuvent contribuer à cette facture.")
    }
    public static var invoiceChangedTitle: String {
        t("finance.invoice.changed_title", "La facture a changé")
    }
    public static var invoiceReview: String { t("finance.invoice.review", "Relire la facture") }

    /// Le motif de divergence, dit en clair.
    ///
    /// La modification silencieuse a son propre message : c'est le seul cas où
    /// l'on refuse de proposer la suite.
    public static func invoiceMutationReason(_ mutation: InvoiceMutation) -> String {
        switch mutation {
        case .silentContentChange:
            return t("finance.invoice.mutation.silent",
                     "Le contenu de cette facture a été modifié sans que son numéro de version change. Ne la réglez pas et contactez le marchand.")
        case .contentChanged:
            return t("finance.invoice.mutation.content",
                     "Le marchand a modifié cette facture. Relisez-la avant de payer.")
        case .versionChanged:
            return t("finance.invoice.mutation.version",
                     "Une nouvelle version de cette facture a été émise.")
        case .amountChanged:
            return t("finance.invoice.mutation.amount",
                     "Le montant dû a changé depuis l'affichage.")
        }
    }

    public static var invoiceStateDraft: String { t("finance.invoice.state.draft", "Brouillon") }
    public static var invoiceStateIssued: String { t("finance.invoice.state.issued", "Émise") }
    public static var invoiceStateViewed: String { t("finance.invoice.state.viewed", "Consultée") }
    public static var invoiceStatePartiallyPaid: String {
        t("finance.invoice.state.partially_paid", "Partiellement réglée")
    }
    public static var invoiceStatePaid: String { t("finance.invoice.state.paid", "Réglée") }
    public static var invoiceStateCancelled: String { t("finance.invoice.state.cancelled", "Annulée") }
    public static var invoiceStateExpired: String { t("finance.invoice.state.expired", "Expirée") }
    public static var invoiceStateDisputed: String { t("finance.invoice.state.disputed", "Contestée") }
    public static var invoiceStateUnknown: String {
        t("finance.invoice.state.unknown", "État non reconnu par cette version")
    }

    /// Motif de l'invite biométrique quand l'écran n'en précise pas.
    public static var stepUpReasonDefault: String {
        t("finance.step_up.reason_default", "Confirmez votre identité pour continuer.")
    }
    public static var stepUpReasonInvoice: String {
        t("finance.stepup.reason.invoice", "Confirmez votre identité pour régler cette facture.")
    }

    // MARK: - Liens de paiement (ch. 46.2)

    public static var linkTitle: String { t("finance.link.title", "Lien de paiement") }
    public static var linkResolving: String { t("finance.link.resolving", "Vérification du lien…") }
    public static var linkPayee: String { t("finance.link.payee", "Bénéficiaire") }
    public static var linkContinue: String { t("finance.link.continue", "Continuer") }
    public static var linkExternalWarning: String {
        t("finance.link.external_warning",
          "Ce lien vient de l'extérieur de l'application. Vérifiez le bénéficiaire avant de payer.")
    }
    /// Format à une chaîne : la date d'expiration.
    public static var linkExpiresAt: String { t("finance.link.expires_at", "Valable jusqu'au %@") }
    public static var linkSingleUse: String {
        t("finance.link.single_use", "Ce lien ne peut servir qu'une seule fois.")
    }
    public static var linkUnusable: String {
        t("finance.link.unusable", "Ce lien n'est plus utilisable.")
    }
    public static var linkIndicativeOnly: String {
        t("finance.link.indicative_only",
          "Ce montant est indicatif. Le montant à payer sera confirmé à l'étape suivante.")
    }
    /// Format à une chaîne : le montant minimum.
    public static var linkMinimum: String { t("finance.link.minimum", "Minimum : %@") }
    /// Format à une chaîne : le montant maximum.
    public static var linkMaximum: String { t("finance.link.maximum", "Maximum : %@") }

    public static var linkIssuedTitle: String { t("finance.link.issued_title", "Mes liens") }
    public static var linkLoadingIssued: String { t("finance.link.loading_issued", "Chargement des liens…") }
    public static var linkNoIssued: String { t("finance.link.no_issued", "Vous n'avez émis aucun lien.") }
    public static var linkRevoke: String { t("finance.link.revoke", "Révoquer") }
    public static var linkRevoking: String { t("finance.link.revoking", "Révocation…") }
    public static var linkRevokeConfirmTitle: String {
        t("finance.link.revoke_confirm_title", "Révoquer ce lien ?")
    }
    public static var linkRevokeConfirmDetail: String {
        t("finance.link.revoke_confirm_detail",
          "Plus personne ne pourra payer avec ce lien, même s'il l'a déjà reçu. Cette action est définitive.")
    }
    /// Format à un entier : le nombre de paiements reçus.
    public static var linkPaymentCount: String { t("finance.link.payment_count", "%d paiement(s)") }

    public static var linkStateActive: String { t("finance.link.state.active", "Actif") }
    public static var linkStateConsumed: String { t("finance.link.state.consumed", "Utilisé") }
    public static var linkStateRevoked: String { t("finance.link.state.revoked", "Révoqué") }
    public static var linkStateExpired: String { t("finance.link.state.expired", "Expiré") }
    public static var linkStateUnknown: String {
        t("finance.link.state.unknown", "État non reconnu par cette version")
    }

    // MARK: - Cartes (ch. 48)

    public static var cardsTitle: String { t("finance.cards.title", "Mes cartes") }
    public static var cardsLoading: String { t("finance.cards.loading", "Chargement des cartes…") }
    public static var cardsEmpty: String { t("finance.cards.empty", "Vous n'avez aucune carte.") }
    public static var cardTitle: String { t("finance.card.title", "Carte") }
    public static var cardWorking: String { t("finance.card.working", "Traitement en cours…") }
    /// Format à deux entiers : mois, année.
    public static var cardExpiry: String { t("finance.card.expiry", "Expire %02d/%d") }

    public static var cardFreeze: String { t("finance.card.freeze", "Geler la carte") }
    public static var cardUnfreeze: String { t("finance.card.unfreeze", "Dégeler la carte") }
    public static var cardFreezeNote: String {
        t("finance.card.freeze_note",
          "Le gel est immédiat et réversible. Aucun paiement ne passera tant que la carte est gelée.")
    }
    public static var cardBlockedNote: String {
        t("finance.card.blocked_note",
          "Cette carte a été bloquée par l'émetteur. Contactez le support pour la débloquer.")
    }
    public static var cardControls: String { t("finance.card.controls", "Contrôles") }
    public static var cardControlsNote: String {
        t("finance.card.controls_note",
          "Ces réglages sont appliqués par l'émetteur, qui peut imposer ses propres limites.")
    }
    public static var cardAllowInternational: String {
        t("finance.card.allow_international", "Paiements à l'étranger")
    }
    public static var cardAllowATM: String { t("finance.card.allow_atm", "Retraits en distributeur") }
    public static var cardLimits: String { t("finance.card.limits", "Plafonds appliqués") }
    public static var cardTransactions: String { t("finance.card.transactions", "Opérations") }
    public static var cardReplace: String { t("finance.card.replace", "Remplacer la carte") }
    public static var cardReplaceTitle: String { t("finance.card.replace_title", "Motif du remplacement") }
    public static var cardReplaceDetail: String {
        t("finance.card.replace_detail",
          "Une carte volée ou compromise est bloquée immédiatement, avant même l'envoi de la nouvelle.")
    }

    public static var cardChannelOnline: String { t("finance.card.channel.online", "En ligne") }
    public static var cardChannelInStore: String { t("finance.card.channel.in_store", "En magasin") }
    public static var cardChannelContactless: String { t("finance.card.channel.contactless", "Sans contact") }
    public static var cardChannelATM: String { t("finance.card.channel.atm", "Distributeur") }
    public static var cardChannelRecurring: String { t("finance.card.channel.recurring", "Prélèvements récurrents") }

    public static var cardLimitPerTransaction: String { t("finance.card.limit.per_transaction", "Par opération") }
    public static var cardLimitDaily: String { t("finance.card.limit.daily", "Par jour") }
    public static var cardLimitWeekly: String { t("finance.card.limit.weekly", "Par semaine") }
    public static var cardLimitMonthly: String { t("finance.card.limit.monthly", "Par mois") }
    public static var cardScopeAll: String { t("finance.card.scope.all", "Tous paiements") }
    public static var cardScopeATM: String { t("finance.card.scope.atm", "Distributeur") }
    public static var cardScopeOnline: String { t("finance.card.scope.online", "En ligne") }
    public static var cardScopeInternational: String { t("finance.card.scope.international", "À l'étranger") }

    public static var cardReasonLost: String { t("finance.card.reason.lost", "Carte perdue") }
    public static var cardReasonStolen: String { t("finance.card.reason.stolen", "Carte volée") }
    public static var cardReasonDamaged: String { t("finance.card.reason.damaged", "Carte endommagée") }
    public static var cardReasonCompromised: String { t("finance.card.reason.compromised", "Carte compromise") }
    public static var cardReasonExpired: String { t("finance.card.reason.expired", "Carte expirée") }

    public static var cardStateRequested: String { t("finance.card.state.requested", "Demandée") }
    public static var cardStateIssued: String { t("finance.card.state.issued", "Émise") }
    public static var cardStateShipped: String { t("finance.card.state.shipped", "Expédiée") }
    public static var cardStateActive: String { t("finance.card.state.active", "Active") }
    public static var cardStateFrozen: String { t("finance.card.state.frozen", "Gelée") }
    public static var cardStateBlocked: String { t("finance.card.state.blocked", "Bloquée") }
    public static var cardStateExpired: String { t("finance.card.state.expired", "Expirée") }
    public static var cardStateReplaced: String { t("finance.card.state.replaced", "Remplacée") }
    public static var cardStateCancelled: String { t("finance.card.state.cancelled", "Résiliée") }
    public static var cardStateUnknown: String {
        t("finance.card.state.unknown", "État non reconnu par cette version")
    }

    public static var stepUpReasonCardUnfreeze: String {
        t("finance.stepup.reason.card_unfreeze", "Confirmez votre identité pour remettre cette carte en service.")
    }
    public static var stepUpReasonCardReplace: String {
        t("finance.stepup.reason.card_replace", "Confirmez votre identité pour remplacer cette carte.")
    }
    public static var stepUpReasonCardControls: String {
        t("finance.stepup.reason.card_controls", "Confirmez votre identité pour modifier les contrôles de cette carte.")
    }
    public static var stepUpReasonCardDispute: String {
        t("finance.stepup.reason.card_dispute", "Confirmez votre identité pour contester cette opération.")
    }

    // MARK: - Transactions cartes (ch. 49)

    public static var cardTransactionsLoading: String {
        t("finance.card.tx.loading", "Chargement des opérations…")
    }
    public static var cardTransactionsEmpty: String {
        t("finance.card.tx.empty", "Aucune opération sur cette carte.")
    }
    public static var cardTransactionTitle: String { t("finance.card.tx.title", "Opération") }

    public static var cardAmountAuthorized: String { t("finance.card.amount.authorized", "Réservé") }
    public static var cardAmountCaptured: String { t("finance.card.amount.captured", "Débité") }
    public static var cardAmountSettled: String { t("finance.card.amount.settled", "Définitif") }
    public static var cardAmountRefunded: String { t("finance.card.amount.refunded", "Remboursé") }
    public static var cardAuthorizedOnlyNote: String {
        t("finance.card.authorized_only_note",
          "Ce montant est réservé, pas encore débité. Le montant final peut être différent.")
    }
    public static var cardOriginalAmount: String { t("finance.card.original_amount", "Montant d'origine") }
    public static var cardDeclineReason: String { t("finance.card.decline_reason", "Motif du refus") }

    public static var cardThreeDS: String { t("finance.card.3ds", "Authentification 3-D Secure") }
    public static var cardThreeDSFlow: String { t("finance.card.3ds.flow", "Parcours") }
    public static var cardThreeDSResult: String { t("finance.card.3ds.result", "Résultat") }
    public static var cardThreeDSFrictionless: String { t("finance.card.3ds.frictionless", "Sans friction") }
    public static var cardThreeDSChallenge: String { t("finance.card.3ds.challenge", "Avec défi") }
    public static var cardThreeDSAuthenticated: String { t("finance.card.3ds.authenticated", "Authentifié") }
    public static var cardThreeDSAttempted: String { t("finance.card.3ds.attempted", "Tentative enregistrée") }
    public static var cardThreeDSFailed: String { t("finance.card.3ds.failed", "Échec") }
    public static var cardThreeDSRejected: String { t("finance.card.3ds.rejected", "Rejeté") }
    public static var cardThreeDSUnavailable: String { t("finance.card.3ds.unavailable", "Indisponible") }
    public static var cardThreeDSUnknown: String { t("finance.card.3ds.unknown", "Non renseigné") }
    public static var cardThreeDSNotAuthenticated: String {
        t("finance.card.3ds.not_authenticated",
          "Cette opération n'a pas été authentifiée : une tentative a été enregistrée, sans vérification d'identité.")
    }

    public static var cardOpenDispute: String { t("finance.card.open_dispute", "Contester l'opération") }
    public static var cardNotDisputable: String {
        t("finance.card.not_disputable",
          "Cette opération n'est pas encore contestable : aucun montant n'a été débité.")
    }
    public static var cardDisputeOpened: String {
        t("finance.card.dispute_opened", "Contestation transmise.")
    }
    public static var cardDisputeKind: String { t("finance.card.dispute.kind", "Nature de la contestation") }
    public static var cardDisputeUnrecognized: String {
        t("finance.card.dispute.unrecognized", "Je ne reconnais pas cette opération")
    }
    public static var cardDisputeUnrecognizedNote: String {
        t("finance.card.dispute.unrecognized_note",
          "Signalez aussi votre carte comme compromise si vous pensez qu'elle a été utilisée sans votre accord.")
    }
    public static var cardDisputeNotReceived: String {
        t("finance.card.dispute.not_received", "Bien ou service non reçu")
    }
    public static var cardDisputeNotAsDescribed: String {
        t("finance.card.dispute.not_as_described", "Non conforme à la description")
    }
    public static var cardDisputeDuplicate: String {
        t("finance.card.dispute.duplicate", "Débité deux fois")
    }
    public static var cardDisputeIncorrectAmount: String {
        t("finance.card.dispute.incorrect_amount", "Montant incorrect")
    }
    public static var cardDisputeRefundMissing: String {
        t("finance.card.dispute.refund_missing", "Remboursement jamais reçu")
    }

    public static var cardTxPending: String { t("finance.card.tx.state.pending", "En attente") }
    public static var cardTxAuthorized: String { t("finance.card.tx.state.authorized", "Réservée") }
    public static var cardTxDeclined: String { t("finance.card.tx.state.declined", "Refusée") }
    public static var cardTxCaptured: String { t("finance.card.tx.state.captured", "Débitée") }
    public static var cardTxSettled: String { t("finance.card.tx.state.settled", "Réglée") }
    public static var cardTxReversed: String { t("finance.card.tx.state.reversed", "Annulée") }
    public static var cardTxRefunded: String { t("finance.card.tx.state.refunded", "Remboursée") }
    public static var cardTxPartiallyRefunded: String {
        t("finance.card.tx.state.partially_refunded", "Partiellement remboursée")
    }
    public static var cardTxDisputed: String { t("finance.card.tx.state.disputed", "Contestée") }
    public static var cardTxChargedBack: String { t("finance.card.tx.state.charged_back", "Rétrofacturée") }
    public static var cardTxExpired: String { t("finance.card.tx.state.expired", "Expirée") }
    public static var cardTxUnknown: String {
        t("finance.card.tx.state.unknown", "État non reconnu par cette version")
    }

    // MARK: - Partage d'addition (ch. 50)

    public static var splitTitle: String { t("finance.split.title", "Partage d'addition") }
    public static var splitLoading: String { t("finance.split.loading", "Chargement des partages…") }
    public static var splitEmpty: String { t("finance.split.empty", "Aucun partage en cours.") }
    public static var splitNew: String { t("finance.split.new", "Nouveau partage") }
    /// Pas de route de liste — **pas** un refus de droits, que seul le serveur
    /// peut prononcer. Créer un partage reste possible.
    public static var splitListingUnavailable: String {
        t("finance.split.listing_unavailable",
          "La liste des partages n'est pas encore disponible. Vous pouvez en créer un.")
    }
    public static var splitCreate: String { t("finance.split.create", "Créer le partage") }
    public static var splitCreating: String { t("finance.split.creating", "Création du partage…") }
    public static var splitLabel: String { t("finance.split.label", "Intitulé") }
    public static var splitCollected: String { t("finance.split.collected", "Collecté") }
    public static var splitRemaining: String { t("finance.split.remaining", "Reste à collecter") }
    /// Format à deux chaînes : collecté, total.
    public static var splitProgress: String { t("finance.split.progress", "%@ sur %@") }
    public static var splitMyShare: String { t("finance.split.my_share", "Ma part") }
    public static var splitShare: String { t("finance.split.share", "Part demandée") }
    public static var splitContributed: String { t("finance.split.contributed", "Déjà versé") }
    public static var splitAccept: String { t("finance.split.accept", "Accepter") }
    public static var splitDecline: String { t("finance.split.decline", "Refuser") }
    public static var splitPayMyShare: String { t("finance.split.pay", "Verser ce montant") }
    /// Format à une chaîne : le solde restant.
    public static var splitPayFull: String { t("finance.split.pay_full", "Verser le solde (%@)") }
    public static var splitSettled: String { t("finance.split.settled", "Votre part est réglée.") }
    public static var splitDeclinedNote: String {
        t("finance.split.declined_note", "Vous avez refusé ce partage. Rien ne vous sera débité.")
    }
    public static var splitConsentUnavailable: String {
        t("finance.split.consent_unavailable", "Cette invitation n'est plus active.")
    }
    public static var splitParticipants: String { t("finance.split.participants", "Participants") }
    public static var splitParticipantsChoose: String {
        t("finance.split.participants_choose", "Choisir les participants")
    }
    public static var splitParticipantsDone: String { t("finance.split.participants_done", "Terminé") }
    public static var splitParticipantsNone: String {
        t("finance.split.participants_none", "Aucun contact à inviter")
    }
    public static var splitSharing: String {
        t("finance.split.sharing", "Envoi du partage à chaque participant…")
    }
    public static var splitShareIncomplete: String {
        t("finance.split.share_incomplete", "Le partage est créé, mais n'a pas pu être envoyé à :")
    }
    public static var splitExcluded: String { t("finance.split.excluded", "Exclu du partage") }
    public static var splitRemind: String { t("finance.split.remind", "Relancer") }
    public static var splitClose: String { t("finance.split.close", "Clôturer le partage") }
    public static var splitPrivateNote: String {
        t("finance.split.private_note", "Les parts des autres participants ne sont pas visibles.")
    }
    public static var splitConsentNote: String {
        t("finance.split.consent_note",
          "Chaque participant devra accepter avant de verser quoi que ce soit. Rien n'est débité sans son accord.")
    }
    public static var splitRoundingNote: String {
        t("finance.split.rounding_note", "Les parts sont calculées par le service, arrondis compris.")
    }

    public static var splitStrategy: String { t("finance.split.strategy", "Répartition") }
    public static var splitStrategyEqual: String { t("finance.split.strategy.equal", "Parts égales") }
    public static var splitStrategyCustom: String { t("finance.split.strategy.custom", "Montants personnalisés") }
    public static var splitStrategyProportional: String {
        t("finance.split.strategy.proportional", "Parts proportionnelles")
    }
    public static var splitParticipantsFirst: String {
        t("finance.split.participants_first", "Choisissez d'abord les participants.")
    }
    public static var splitCustomSection: String { t("finance.split.custom_section", "Montant par personne") }
    public static var splitWeightsSection: String { t("finance.split.weights_section", "Poids de chacun") }
    public static var splitWeightsHint: String {
        t("finance.split.weights_hint",
          "Chaque part est proportionnelle à son poids — nombre de plats, de nuits, de parts.")
    }
    public static var splitCustomMismatch: String {
        t("finance.split.custom_mismatch", "Les montants saisis ne correspondent pas au total.")
    }
    /// Format à deux chaînes : saisi, total — « Saisi : 30 000 BIF sur 50 000 BIF ».
    public static func splitCustomSum(_ entered: String, _ total: String) -> String {
        String(format: t("finance.split.custom_sum", "Saisi : %@ sur %@"), entered, total)
    }
    public static func splitParticipantsSelected(_ count: Int) -> String {
        let format = t("finance.split.participants_selected", "%d sélectionné(s)")
        return format.replacingOccurrences(of: "%d", with: String(count))
    }

    public static var splitPrivacy: String { t("finance.split.privacy", "Visibilité") }
    public static var splitPrivacyOwn: String {
        t("finance.split.privacy.own", "Chacun ne voit que sa part")
    }
    public static var splitPrivacyAggregate: String {
        t("finance.split.privacy.aggregate", "Chacun voit sa part et l'avancement global")
    }
    public static var splitPrivacyOpen: String {
        t("finance.split.privacy.open", "Tout le monde voit tout")
    }

    public static var splitConsentPending: String { t("finance.split.consent.pending", "En attente de réponse") }
    public static var myQRTitle: String { t("finance.my_qr.title", "Code QR") }
    public static var myQRSubtitle: String { t("finance.my_qr.subtitle", "Contact Waangu") }
    public static var myQRPrivacy: String {
        t("finance.my_qr.privacy",
          "Votre code QR est privé. Quiconque le scanne avec Waangu peut vous ajouter, vous écrire ou vous payer.")
    }
    public static var myQRScan: String { t("finance.my_qr.scan", "Scanner") }
    public static var myQRReset: String { t("finance.my_qr.reset", "Réinitialiser le code QR") }
    public static var myQRPay: String { t("finance.my_qr.pay", "Payer") }
    public static var myQRMessage: String { t("finance.my_qr.message", "Envoyer un message") }
    public static var myQRMessageUnavailable: String {
        t("finance.my_qr.message_unavailable", "Ce code ne permet pas encore d'écrire à cette personne.")
    }
    public static var splitCardTitle: String { t("finance.split.card.title", "Partage") }
    public static var splitCardYou: String { t("finance.split.card.you", "Vous") }
    public static var splitCardPrivateShares: String {
        t("finance.split.card.private_shares", "Seul l'organisateur voit le statut de chacun.")
    }
    public static var splitProgressPaid: String { t("finance.split.progress.paid", "Payé") }
    public static var splitProgressAwaitingPayment: String {
        t("finance.split.progress.awaiting_payment", "Accepté, paiement en attente")
    }
    public static var splitProgressExcluded: String { t("finance.split.progress.excluded", "Exclu") }
    public static var splitConsentAccepted: String { t("finance.split.consent.accepted", "Accepté") }
    public static var splitConsentDeclined: String { t("finance.split.consent.declined", "Refusé") }
    public static var splitConsentExpired: String { t("finance.split.consent.expired", "Invitation expirée") }
    public static var splitConsentUnknown: String {
        t("finance.split.consent.unknown", "État non reconnu par cette version")
    }

    public static var splitStateDraft: String { t("finance.split.state.draft", "Brouillon") }
    public static var splitStateOpen: String { t("finance.split.state.open", "En cours") }
    public static var splitStatePartial: String { t("finance.split.state.partial", "Partiellement réglé") }
    public static var splitStateSettled: String { t("finance.split.state.settled", "Réglé") }
    public static var splitStateClosed: String { t("finance.split.state.closed", "Clôturé") }
    public static var splitStateCancelled: String { t("finance.split.state.cancelled", "Annulé") }
    public static var splitStateExpired: String { t("finance.split.state.expired", "Expiré") }
    public static var splitStateUnknown: String {
        t("finance.split.state.unknown", "État non reconnu par cette version")
    }

    public static var stepUpReasonSplit: String {
        t("finance.stepup.reason.split", "Confirmez votre identité pour verser votre part.")
    }

    // MARK: - Paiement sans contact (ch. 47)

    public static var nfcTitle: String { t("finance.nfc.title", "Paiement sans contact") }
    public static var nfcChecking: String { t("finance.nfc.checking", "Vérification de l'appareil…") }
    public static var nfcOpening: String { t("finance.nfc.opening", "Ouverture de la session…") }
    public static var nfcConfirming: String { t("finance.nfc.confirming", "Paiement en cours…") }
    public static var nfcConfirm: String { t("finance.nfc.confirm", "Payer") }
    public static var nfcRetry: String { t("finance.nfc.retry", "Réessayer") }
    public static var nfcRefreshStatus: String { t("finance.nfc.refresh_status", "Actualiser l'état") }
    /// Format à un entier : les secondes restantes.
    public static var nfcExpiresIn: String { t("finance.nfc.expires_in", "Valable encore %d s") }
    public static var nfcSessionExpired: String {
        t("finance.nfc.session_expired", "La session a expiré. Recommencez.")
    }
    public static var nfcUnavailableTitle: String {
        t("finance.nfc.unavailable_title", "Paiement sans contact indisponible")
    }
    public static var nfcRelayElevated: String {
        t("finance.nfc.relay_elevated",
          "Une vérification supplémentaire est demandée pour ce paiement.")
    }
    public static var nfcRelayBlocked: String {
        t("finance.nfc.relay_blocked",
          "Ce paiement a été bloqué par sécurité. Réglez autrement.")
    }
    public static var nfcMismatchTitle: String {
        t("finance.nfc.mismatch_title", "Le terminal a changé")
    }

    /// Pourquoi le sans contact est indisponible.
    ///
    /// Chaque motif appelle un geste différent : activer le NFC n'est pas la
    /// même réponse qu'un pays non ouvert.
    public static func nfcUnavailableReason(_ reason: ProximityUnavailableReason?) -> String {
        switch reason {
        case .hardwareMissing:
            return t("finance.nfc.unavailable.hardware", "Cet appareil ne gère pas le paiement sans contact.")
        case .nfcDisabled:
            return t("finance.nfc.unavailable.disabled", "Activez le NFC dans les réglages de votre appareil.")
        case .countryNotOpen:
            return t("finance.nfc.unavailable.country", "Le paiement sans contact n'est pas encore ouvert dans votre pays.")
        case .deviceNotAttested:
            return t("finance.nfc.unavailable.attestation", "Cet appareil n'a pas pu être vérifié. Redémarrez l'application.")
        case .accountRestricted:
            return t("finance.nfc.unavailable.account", "Le paiement sans contact n'est pas activé sur votre compte.")
        case .unknown, .none:
            return t("finance.nfc.unavailable.unknown", "Le paiement sans contact n'est pas disponible pour le moment.")
        }
    }

    /// Ce qui a changé entre l'épinglage et la présentation.
    public static func nfcMismatchReason(_ mismatch: ProximityMismatch) -> String {
        switch mismatch {
        case .terminalChanged:
            return t("finance.nfc.mismatch.terminal",
                     "Le terminal qui répond n'est pas celui du début. Le paiement a été interrompu.")
        case .merchantChanged:
            return t("finance.nfc.mismatch.merchant",
                     "Le marchand a changé depuis l'ouverture. Le paiement a été interrompu.")
        case .amountChanged:
            return t("finance.nfc.mismatch.amount",
                     "Le montant demandé a changé depuis l'affichage. Le paiement a été interrompu.")
        case .payloadChanged:
            return t("finance.nfc.mismatch.payload",
                     "Les données du terminal ne correspondent plus. Le paiement a été interrompu.")
        }
    }

    /// L'issue, en une ligne.
    public static func nfcTruthLabel(_ truth: ProximityPaymentTruth) -> String {
        switch truth {
        case .confirmed:  return t("finance.nfc.truth.confirmed", "Paiement effectué")
        case .processing: return t("finance.nfc.truth.processing", "Paiement en traitement")
        case .pending:    return t("finance.nfc.truth.pending", "Paiement en attente")
        case .failed:     return t("finance.nfc.truth.failed", "Paiement refusé")
        case .reversed:   return t("finance.nfc.truth.reversed", "Paiement annulé")
        case .unknown:    return t("finance.nfc.truth.unknown", "Issue en cours de vérification")
        }
    }

    /// Le détail, et surtout ce qu'il ne faut pas faire.
    public static func nfcTruthDetail(_ truth: ProximityPaymentTruth) -> String {
        switch truth {
        case .confirmed:
            return t("finance.nfc.truth.confirmed_detail", "Le marchand a reçu la confirmation.")
        case .processing, .pending:
            return t("finance.nfc.truth.pending_detail",
                     "Ne repayez pas : l'opération est en cours. Actualisez pour connaître son issue.")
        case .unknown:
            return t("finance.nfc.truth.unknown_detail",
                     "Nous vérifions si le paiement a abouti. Ne repayez pas avant de le savoir.")
        case .failed:
            return t("finance.nfc.truth.failed_detail", "Aucun montant n'a été débité.")
        case .reversed:
            return t("finance.nfc.truth.reversed_detail", "Le montant vous a été rendu.")
        }
    }

    public static var stepUpReasonProximity: String {
        t("finance.stepup.reason.proximity", "Confirmez votre identité pour ce paiement sans contact.")
    }

    // MARK: - Statuts de paiement, en clair

    /// Libellé humain d'un statut de paiement.
    ///
    /// Le brut du backend — `PENDING_SETTLEMENT`, `AML_REVIEW` — ne dit rien à
    /// personne, et le rendre tel quel viole la règle « aucun rendu de statut
    /// brut » que le dépôt vérifie en CI. Chaque libellé dit **où en est
    /// l'argent**, jamais une conclusion que le backend n'a pas posée.
    public static func paymentStatusLabel(_ status: PaymentStatus) -> String {
        switch status {
        case .queued:                return t("finance.status.queued", "En file d'attente")
        case .syncing:               return t("finance.status.syncing", "Synchronisation")
        case .pending:               return t("finance.status.pending", "En attente")
        case .processing:            return t("finance.status.processing", "En traitement")
        case .authorized:            return t("finance.status.authorized", "Autorisé")
        case .pendingProvider:       return t("finance.status.pending_provider", "En attente du prestataire")
        case .pendingSettlement:     return t("finance.status.pending_settlement", "En attente de règlement")
        case .confirmed:             return t("finance.status.confirmed", "Confirmé")
        case .completed:             return t("finance.status.completed", "Terminé")
        case .failed:                return t("finance.status.failed", "Échoué")
        case .cancelled:             return t("finance.status.cancelled", "Annulé")
        case .expired:               return t("finance.status.expired", "Expiré")
        case .compliancePending:     return t("finance.status.compliance_pending", "Vérification de conformité")
        case .authorizationRequired: return t("finance.status.authorization_required", "Autorisation requise")
        case .pendingReconciliation: return t("finance.status.pending_reconciliation", "En attente de rapprochement")
        case .refundRequested:       return t("finance.status.refund_requested", "Remboursement demandé")
        case .refundApproved:        return t("finance.status.refund_approved", "Remboursement accordé")
        case .refundProcessing:      return t("finance.status.refund_processing", "Remboursement en cours")
        case .reconciling:           return t("finance.status.reconciling", "Rapprochement en cours")
        case .refunded:              return t("finance.status.refunded", "Remboursé")
        case .partiallyRefunded:     return t("finance.status.partially_refunded", "Partiellement remboursé")
        case .reversed:              return t("finance.status.reversed", "Annulé par le prestataire")
        case .disputed:              return t("finance.status.disputed", "Contesté")
        case .restricted:            return t("finance.status.restricted", "Restreint")
        case .denied:                return t("finance.status.denied", "Refusé")
        case .complianceHold:        return t("finance.status.compliance_hold", "Bloqué pour conformité")
        case .amlReview:             return t("finance.status.aml_review", "Contrôle en cours")
        // Un statut que cette version ne connaît pas : ni réussi, ni échoué.
        case .unknown:               return t("finance.status.unknown", "État non reconnu par cette version")
        // Le serveur dit ne pas savoir encore : on vérifie, on ne rejoue pas.
        case .inDoubt:               return t("finance.status.in_doubt", "Issue en cours de vérification")
        }
    }

    // MARK: - Collectes, tontines, cagnottes (ch. 51)

    public static var campaignTitle: String { t("finance.campaign.title", "Collecte") }
    public static var campaignLoading: String { t("finance.campaign.loading", "Chargement des collectes…") }
    public static var campaignEmpty: String { t("finance.campaign.empty", "Aucune collecte en cours.") }
    /// Format à deux chaînes : collecté, objectif.
    public static var campaignProgress: String { t("finance.campaign.progress", "%@ sur %@") }
    /// Format à une chaîne : le montant collecté.
    public static var campaignCollectedOnly: String { t("finance.campaign.collected_only", "%@ collectés") }
    public static var campaignCollected: String { t("finance.campaign.collected", "Collecté") }
    public static var campaignTarget: String { t("finance.campaign.target", "Objectif") }
    public static var campaignDisbursed: String { t("finance.campaign.disbursed", "Déjà versé") }
    public static var campaignContributors: String { t("finance.campaign.contributors", "Contributeurs") }
    public static var campaignDeadline: String { t("finance.campaign.deadline", "Date limite") }
    public static var campaignOrganizer: String { t("finance.campaign.organizer", "Organisateur") }
    public static var campaignBeneficiary: String { t("finance.campaign.beneficiary", "Bénéficiaire") }
    public static var campaignContribute: String { t("finance.campaign.contribute", "Contribuer") }
    public static var campaignContributeAction: String {
        t("finance.campaign.contribute_action", "Envoyer ma contribution")
    }
    public static var campaignMessage: String { t("finance.campaign.message", "Message (facultatif)") }
    public static var campaignAnonymous: String {
        t("finance.campaign.anonymous", "Masquer mon nom aux autres participants")
    }
    public static var campaignAnonymousNote: String {
        t("finance.campaign.anonymous_note",
          "Votre nom reste connu du service et des autorités compétentes. L'anonymat ne concerne que l'affichage.")
    }
    public static var campaignTontineNote: String {
        t("finance.campaign.tontine_note",
          "Une tontine vous engage sur un tour de cotisations. On n'en sort pas comme d'une cagnotte.")
    }
    public static var campaignTrustWarning: String {
        t("finance.campaign.trust_warning", "Organisateur à vérifier")
    }
    public static var campaignRequestRefund: String {
        t("finance.campaign.request_refund", "Demander un remboursement")
    }
    public static var campaignReport: String { t("finance.campaign.report", "Signaler cette collecte") }
    public static var campaignReportTitle: String {
        t("finance.campaign.report_title", "Signaler cette collecte ?")
    }
    public static var campaignReportDetail: String {
        t("finance.campaign.report_detail",
          "Le service examinera la collecte et pourra la suspendre. Signalez sans hésiter : une collecte frauduleuse collecte pendant l'hésitation.")
    }
    public static var campaignSuspended: String {
        t("finance.campaign.suspended", "Cette collecte est suspendue le temps d'une vérification.")
    }
    public static var campaignClosedToContributions: String {
        t("finance.campaign.closed_contributions", "Cette collecte n'accepte plus de contributions.")
    }
    public static var campaignBeneficiaryUnverified: String {
        t("finance.campaign.beneficiary_unverified",
          "Le bénéficiaire n'est pas encore vérifié. Aucune contribution n'est possible.")
    }

    public static var campaignTrustNew: String { t("finance.campaign.trust.new", "Nouvel organisateur") }
    public static var campaignTrustEstablished: String { t("finance.campaign.trust.established", "Organisateur connu") }
    public static var campaignTrustTrusted: String { t("finance.campaign.trust.trusted", "Organisateur de confiance") }
    public static var campaignTrustFlagged: String { t("finance.campaign.trust.flagged", "Organisateur signalé") }

    public static var campaignBeneficiaryVerified: String { t("finance.campaign.beneficiary.verified", "Identité vérifiée") }
    public static var campaignBeneficiaryPending: String { t("finance.campaign.beneficiary.pending", "Vérification en cours") }
    public static var campaignBeneficiaryUnverifiedShort: String { t("finance.campaign.beneficiary_unverified_short", "Non vérifié") }
    public static var campaignBeneficiaryRejected: String { t("finance.campaign.beneficiary.rejected", "Vérification refusée") }

    public static var campaignEscrow: String { t("finance.campaign.escrow", "Fonds en séquestre") }
    public static var campaignEscrowState: String { t("finance.campaign.escrow.state", "État") }
    public static var campaignEscrowHeld: String { t("finance.campaign.escrow.held", "Montant détenu") }
    public static var campaignEscrowNote: String {
        t("finance.campaign.escrow.note",
          "Les fonds sont détenus par l'établissement partenaire, pas par l'application.")
    }
    public static var campaignEscrowHolding: String { t("finance.campaign.escrow.holding", "Détenus") }
    public static var campaignEscrowReleasing: String { t("finance.campaign.escrow.releasing", "Libération en cours") }
    public static var campaignEscrowReleased: String { t("finance.campaign.escrow.released", "Libérés") }
    public static var campaignEscrowRefunding: String { t("finance.campaign.escrow.refunding", "Remboursement en cours") }
    public static var campaignEscrowFrozen: String { t("finance.campaign.escrow.frozen", "Gelés") }
    public static var campaignEscrowUnknown: String {
        t("finance.campaign.escrow.unknown", "État non reconnu par cette version")
    }

    public static var campaignStateDraft: String { t("finance.campaign.state.draft", "Brouillon") }
    public static var campaignStateOpen: String { t("finance.campaign.state.open", "Ouverte") }
    public static var campaignStateTargetMet: String { t("finance.campaign.state.target_met", "Objectif atteint") }
    public static var campaignStateClosed: String { t("finance.campaign.state.closed", "Fermée") }
    public static var campaignStateDisbursing: String { t("finance.campaign.state.disbursing", "Versement en cours") }
    public static var campaignStateCompleted: String { t("finance.campaign.state.completed", "Terminée") }
    public static var campaignStateSuspended: String { t("finance.campaign.state.suspended", "Suspendue") }
    public static var campaignStateRefunding: String { t("finance.campaign.state.refunding", "Remboursement en cours") }
    public static var campaignStateCancelled: String { t("finance.campaign.state.cancelled", "Annulée") }
    public static var campaignStateUnknown: String {
        t("finance.campaign.state.unknown", "État non reconnu par cette version")
    }

    public static var stepUpReasonCampaign: String {
        t("finance.stepup.reason.campaign", "Confirmez votre identité pour envoyer cette contribution.")
    }

    // MARK: - Mini-apps (ch. 52)

    public static var nativeTitle: String { t("finance.native.title", "Objet") }
    public static var nativeLoading: String { t("finance.native.loading", "Chargement de l'objet…") }
    public static var nativeRegistryTitle: String { t("finance.native.registry_title", "Applications") }
    public static var nativeLoadingRegistry: String {
        t("finance.native.loading_registry", "Chargement des applications…")
    }
    public static var nativeNoApp: String {
        t("finance.native.no_app", "Aucune application n'est déclarée pour votre compte.")
    }
    public static var nativeLifecycle: String { t("finance.native.lifecycle", "État") }
    public static var nativeOwner: String { t("finance.native.owner", "Service responsable") }
    public static var nativeFinancialLink: String {
        t("finance.native.financial_link", "Opération financière liée")
    }
    public static var nativeOpenApp: String { t("finance.native.open_app", "Ouvrir dans l'application") }
    public static var nativeOpenWeb: String { t("finance.native.open_web", "Ouvrir dans le navigateur") }
    public static var nativeInstall: String { t("finance.native.install", "Installer l'application") }
    public static var nativeCardOnly: String {
        t("finance.native.card_only", "Cet objet ne peut être que consulté ici.")
    }
    public static var nativeUnavailable: String {
        t("finance.native.unavailable", "Ce service n'est plus disponible.")
    }
    public static var nativeUnavailableShort: String {
        t("finance.native.unavailable_short", "Indisponible")
    }
    public static var nativeUnsupportedObject: String {
        t("finance.native.unsupported_object",
          "Cette application ne gère pas ce type d'objet.")
    }
    public static var nativeActionUnsupported: String {
        t("finance.native.action_unsupported",
          "Cette action demande une version plus récente de l'application.")
    }

    public static var nativeLifecycleDraft: String { t("finance.native.lifecycle.draft", "Brouillon") }
    public static var nativeLifecyclePending: String { t("finance.native.lifecycle.pending", "En attente") }
    public static var nativeLifecycleConfirmed: String { t("finance.native.lifecycle.confirmed", "Confirmé") }
    public static var nativeLifecycleInProgress: String { t("finance.native.lifecycle.in_progress", "En cours") }
    public static var nativeLifecycleCompleted: String { t("finance.native.lifecycle.completed", "Terminé") }
    public static var nativeLifecycleCancelled: String { t("finance.native.lifecycle.cancelled", "Annulé") }
    public static var nativeLifecycleFailed: String { t("finance.native.lifecycle.failed", "Échoué") }
    public static var nativeLifecycleUnknown: String {
        t("finance.native.lifecycle.unknown", "État non reconnu par cette version")
    }

    // MARK: - Réconciliation (ch. 53)

    public static var reconTitle: String { t("finance.recon.title", "Rapprochements") }
    public static var reconCaseTitle: String { t("finance.recon.case_title", "Dossier") }
    public static var reconLoading: String { t("finance.recon.loading", "Chargement des dossiers…") }
    public static var reconEmpty: String {
        t("finance.recon.empty", "Aucun désaccord constaté sur vos opérations.")
    }
    public static var reconAwaitsYou: String { t("finance.recon.awaits_you", "Action attendue") }
    public static var reconSubjects: String { t("finance.recon.subjects", "Opérations concernées") }
    public static var reconDiscrepancy: String { t("finance.recon.discrepancy", "Écart constaté") }
    public static var reconTruths: String { t("finance.recon.truths", "Ce que dit chaque système") }
    public static var reconLoadTruths: String {
        t("finance.recon.load_truths", "Interroger les systèmes")
    }
    public static var reconInconclusive: String {
        t("finance.recon.inconclusive",
          "Un seul système a répondu. Un silence n'est pas un accord : le rapprochement reste ouvert.")
    }
    /// Format à une chaîne : l'instant de capture.
    public static var reconCapturedAt: String {
        t("finance.recon.captured_at", "Relevé au %@, sur tous les systèmes en même temps.")
    }
    public static var reconEscalations: String { t("finance.recon.escalations", "Escalades") }
    public static var reconOverdue: String { t("finance.recon.overdue", "Délai de réponse dépassé") }
    public static var reconResolution: String { t("finance.recon.resolution", "Résolution") }
    public static var reconCorrelation: String { t("finance.recon.correlation", "Référence d'incident") }
    public static var reconCorrelationNote: String {
        t("finance.recon.correlation_note",
          "Donnez cette référence au support : elle relie cet incident à toutes ses traces, quel que soit l'appareil.")
    }

    /// Ce que le dossier constate.
    public static func reconKindLabel(_ kind: ReconciliationKind) -> String {
        switch kind {
        case .debitWithoutOrder:      return t("finance.recon.kind.debit_no_order", "Débit sans commande")
        case .orderWithoutDebit:      return t("finance.recon.kind.order_no_debit", "Commande sans débit")
        case .duplicateDebit:         return t("finance.recon.kind.duplicate", "Débit en double")
        case .wrongMerchant:          return t("finance.recon.kind.wrong_merchant", "Mauvais bénéficiaire")
        case .cardSettlementMismatch: return t("finance.recon.kind.card_mismatch", "Règlement carte divergent")
        case .missingRefund:          return t("finance.recon.kind.missing_refund", "Remboursement non reçu")
        case .missingContribution:    return t("finance.recon.kind.missing_contribution", "Contribution invisible")
        case .atmDispenseFailure:     return t("finance.recon.kind.atm", "Retrait débité sans espèces")
        case .unknown:                return t("finance.recon.kind.unknown", "Désaccord non catégorisé")
        }
    }

    /// Ce que ça veut dire, en une phrase.
    public static func reconKindDetail(_ kind: ReconciliationKind) -> String {
        switch kind {
        case .debitWithoutOrder:
            return t("finance.recon.detail.debit_no_order",
                     "Votre compte a été débité, mais le marchand ne voit pas la commande.")
        case .orderWithoutDebit:
            return t("finance.recon.detail.order_no_debit",
                     "Le marchand voit la commande payée, mais aucun débit n'est constaté.")
        case .duplicateDebit:
            return t("finance.recon.detail.duplicate",
                     "Deux débits ont été constatés pour une seule opération.")
        case .wrongMerchant:
            return t("finance.recon.detail.wrong_merchant",
                     "Le bénéficiaire du débit ne correspond pas à celui affiché.")
        case .cardSettlementMismatch:
            return t("finance.recon.detail.card_mismatch",
                     "Le montant réglé diffère du montant débité.")
        case .missingRefund:
            return t("finance.recon.detail.missing_refund",
                     "Un remboursement a été annoncé mais n'est pas arrivé.")
        case .missingContribution:
            return t("finance.recon.detail.missing_contribution",
                     "Votre contribution a été débitée mais n'apparaît pas dans la collecte.")
        case .atmDispenseFailure:
            return t("finance.recon.detail.atm",
                     "Le retrait a été débité sans que les espèces soient délivrées.")
        case .unknown:
            return t("finance.recon.detail.unknown",
                     "Un désaccord que cette version ne sait pas décrire. Le support a le détail.")
        }
    }

    public static func reconSystemLabel(_ system: TruthSystem) -> String {
        switch system {
        case .ledger:            return t("finance.recon.system.ledger", "Système financier")
        case .paymentGateway:    return t("finance.recon.system.gateway", "Prestataire de paiement")
        case .merchantBackend:   return t("finance.recon.system.merchant", "Marchand")
        case .cardSystem:        return t("finance.recon.system.card", "Système de cartes")
        case .collectionService: return t("finance.recon.system.collection", "Service de collecte")
        case .nativeApp:         return t("finance.recon.system.native", "Application partenaire")
        case .unknown:           return t("finance.recon.system.unknown", "Système non identifié")
        }
    }

    public static func reconStateLabel(_ state: ReconciliationState) -> String {
        switch state {
        case .opened:           return t("finance.recon.state.opened", "Ouvert")
        case .gatheringTruth:   return t("finance.recon.state.gathering", "Collecte des informations")
        case .awaitingEvidence: return t("finance.recon.state.awaiting_evidence", "Pièces attendues")
        case .underReview:      return t("finance.recon.state.review", "En cours d'examen")
        case .escalated:        return t("finance.recon.state.escalated", "Transmis au partenaire")
        case .resolved:         return t("finance.recon.state.resolved", "Résolu")
        case .closedNoAction:   return t("finance.recon.state.closed", "Clos sans suite")
        case .unknown:          return t("finance.recon.state.unknown", "État non reconnu par cette version")
        }
    }

    public static func reconPartnerLabel(_ target: PartnerEscalationTarget) -> String {
        switch target {
        case .paymentGateway:    return t("finance.recon.partner.gateway", "Prestataire de paiement")
        case .cardIssuer:        return t("finance.recon.partner.issuer", "Émetteur de la carte")
        case .cardNetwork:       return t("finance.recon.partner.network", "Réseau de cartes")
        case .merchant:          return t("finance.recon.partner.merchant", "Marchand")
        case .collectionService: return t("finance.recon.partner.collection", "Service de collecte")
        case .internalSupport:   return t("finance.recon.partner.support", "Support Waangu")
        }
    }

    public static func reconOutcomeLabel(_ outcome: ReconciliationOutcome) -> String {
        switch outcome {
        case .noDiscrepancy:  return t("finance.recon.outcome.none", "Aucun écart réel")
        case .corrected:      return t("finance.recon.outcome.corrected", "Corrigé")
        case .debitUpheld:    return t("finance.recon.outcome.upheld", "Débit confirmé justifié")
        case .refunded:       return t("finance.recon.outcome.refunded", "Remboursé")
        case .partnerTimeout: return t("finance.recon.outcome.timeout", "Partenaire sans réponse")
        case .unknown:        return t("finance.recon.outcome.unknown", "Issue non reconnue par cette version")
        }
    }

    // MARK: - Portes de capacité (§16)

    public static var capabilityChecking: String {
        t("finance.capability.checking", "Vérification de la disponibilité…")
    }
    public static var capabilityClosedTitle: String {
        t("finance.capability.closed_title", "Indisponible pour le moment")
    }

    /// Le motif de fermeture, dit en clair.
    ///
    /// Chaque porte a sa formulation : elles n'appellent pas les mêmes gestes.
    /// Libellé d'un traitement d'affichage de carte financière.
    public static func objectStatus(_ presentation: FinancialCardPresentation) -> String {
        switch presentation {
        case .settled: return t("finance.object.status.settled", "Effectué")
        case .verifying: return t("finance.object.status.verifying", "Vérification…")
        case .inFlight: return t("finance.object.status.in_flight", "En cours")
        case .atProvider: return t("finance.object.status.at_provider", "Chez l'opérateur")
        case .settling: return t("finance.object.status.settling", "En règlement")
        case .failed: return t("finance.object.status.failed", "Échoué")
        case .refused: return t("finance.object.status.refused", "Refusé")
        case .cancelled: return t("finance.object.status.cancelled", "Annulé")
        case .expired: return t("finance.object.status.expired", "Expiré")
        case .refunded: return t("finance.object.status.refunded", "Remboursé")
        case .partiallyRefunded: return t("finance.object.status.partially_refunded", "Remboursé en partie")
        case .reversed: return t("finance.object.status.reversed", "Annulé par l'opérateur")
        case .disputed: return t("finance.object.status.disputed", "En litige")
        case .complianceReview: return t("finance.object.status.compliance_review", "En vérification")
        case .refundInProgress: return t("finance.object.status.refund_in_progress", "Remboursement en cours")
        case .reconciling: return t("finance.object.status.reconciling", "Rapprochement en cours")
        case .repudiated: return t("finance.object.status.repudiated", "Non authentifié")
        }
    }

    public static var objectNeverSynced: String { t("finance.object.never_synced", "Jamais synchronisé") }
    public static var objectUpdatedAt: String { t("finance.object.updated_at", "Dernière mise à jour à %@") }

    public static var quoteExpiresIn: String { t("finance.quote.expires_in", "Ce devis expire dans %@ s.") }
    public static var quoteExpired: String {
        t("finance.quote.expired", "Ce devis a expiré. Actualisez-le pour continuer.")
    }
    public static var quoteRefresh: String { t("finance.quote.refresh", "Actualiser") }

    static func sessionRestrictionTitle(_ restriction: FinanceSessionViewModel.Restriction) -> String {
        switch restriction {
        case .countryClosed: return t("finance.session.country_closed_title", "Paiements non ouverts dans votre pays")
        case .serviceSuspended: return t("finance.session.service_suspended_title", "Paiements suspendus")
        case .readDenied: return t("finance.session.read_denied_title", "Consultation indisponible")
        case .safeMode: return t("finance.session.safe_mode_title", "Consultation seule")
        case .sessionLocked: return t("finance.session.session_locked_title", "Session à revalider")
        case .paymentsDisabled: return t("finance.session.payments_disabled_title", "Paiements indisponibles")
        case .unavailable: return t("finance.session.unavailable_title", "Paiements injoignables")
        }
    }

    /// Relance après une indisponibilité. Nomme le geste, pas l'espoir :
    /// « réessayer », jamais « veuillez patienter ».
    static var sessionRetry: String { t("finance.session.retry", "Réessayer") }

    /// Annonce de l'ossature de chargement, pour les lecteurs d'écran : ce que
    /// les blocs gris disent aux yeux, cette phrase le dit à l'oreille.
    public static var walletLoading: String {
        t("finance.session.loading", "Chargement de votre portefeuille…")
    }

    static func sessionRestrictionDetail(_ restriction: FinanceSessionViewModel.Restriction) -> String {
        switch restriction {
        case .countryClosed: return t("finance.session.country_closed_detail", "Les paiements ne sont pas encore disponibles pour votre pays.")
        case .serviceSuspended: return t("finance.session.service_suspended_detail", "Le service de paiement est suspendu pour le moment. Réessayez plus tard.")
        case .readDenied: return t("finance.session.read_denied_detail", "Votre session ne permet pas de consulter votre solde ni vos opérations pour le moment.")
        case .safeMode: return t("finance.session.safe_mode_detail", "Vous pouvez consulter vos opérations, mais aucun paiement n'est possible pour le moment.")
        case .sessionLocked: return t("finance.session.session_locked_detail", "Votre session doit être revalidée avant tout paiement. Reconnectez-vous ou réessayez dans un instant.")
        case .paymentsDisabled: return t("finance.session.payments_disabled_detail", "Les paiements ne sont pas autorisés sur votre compte pour le moment.")
        case .unavailable: return t("finance.session.unavailable_detail", "Impossible de vérifier votre accès aux paiements. Vérifiez votre connexion.")
        }
    }

    public static var financialObjectUnavailable: String {
        t("finance.object.unavailable",
          "Impossible de lire cette opération pour le moment. Son état n'est pas connu.")
    }

    public static var killSwitchSuspendedTitle: String {
        t("finance.killswitch.suspended_title", "Service suspendu")
    }

    /// Motif de suspension. La clé vient du backend ; inconnue, elle retombe sur
    /// le message générique plutôt que d'afficher une clé brute.
    public static func killSwitchReason(_ reasonKey: String?) -> String {
        let generic = t("finance.killswitch.suspended",
                        "Ce service est suspendu temporairement. Réessayez plus tard.")
        guard let reasonKey, !reasonKey.isEmpty else { return generic }
        return t(reasonKey, generic)
    }

    public static func capabilityClosedReason(_ closure: CapabilityClosure) -> String {
        switch closure {
        case .notEnabled:
            return t("finance.capability.closed.not_enabled",
                     "Ce service n'est pas activé pour votre compte.")
        case .notLicensed:
            return t("finance.capability.closed.not_licensed",
                     "Ce service n'est pas encore autorisé dans votre pays.")
        case .complianceWithheld:
            return t("finance.capability.closed.compliance_withheld",
                     "Ce service est en cours de revue de conformité. Réessayez plus tard.")
        case .partnerWithheld:
            return t("finance.capability.closed.partner_withheld",
                     "Notre partenaire a suspendu ce service temporairement.")
        case .notYetEffective:
            return t("finance.capability.closed.not_yet_effective",
                     "Ce service n'est pas encore ouvert.")
        case .expired:
            return t("finance.capability.closed.expired",
                     "Ce service n'est plus proposé.")
        }
    }

    // MARK: - FX — règles automatiques (ch. 37)

    public static var fxRulesTitle: String { t("finance.fx.rules_title", "Conversions automatiques") }
    public static var fxRulesLoading: String { t("finance.fx.rules_loading", "Chargement des règles…") }
    public static var fxNoRule: String {
        t("finance.fx.no_rule", "Aucune conversion automatique n'est active.")
    }
    public static var fxRuleDirection: String { t("finance.fx.rule_direction", "Conversion") }
    public static var fxRuleTrigger: String { t("finance.fx.rule_trigger", "Déclencheur") }
    public static var fxRuleCap: String { t("finance.fx.rule_cap", "Plafond par exécution") }
    public static var fxRuleNoCap: String {
        t("finance.fx.rule_no_cap", "Aucun plafond par exécution.")
    }
    public static var fxRuleConsent: String { t("finance.fx.rule_consent", "Autorisée le") }
    /// Format à une chaîne : la version du consentement.
    public static var fxRuleConsentVersion: String {
        t("finance.fx.rule_consent_version", "Conditions version %@")
    }
    public static var fxRuleInactive: String { t("finance.fx.rule_inactive", "Suspendue") }
    public static var fxRevoke: String { t("finance.fx.revoke", "Révoquer") }
    public static var fxRevoking: String { t("finance.fx.revoking", "Révocation…") }
    public static var fxRevokeConfirmTitle: String {
        t("finance.fx.revoke_confirm_title", "Révoquer cette règle ?")
    }
    public static var fxRevokeConfirmDetail: String {
        t("finance.fx.revoke_confirm_detail",
          "Plus aucune conversion automatique n'aura lieu. La recréer demandera un nouveau consentement.")
    }
    /// Format à une chaîne : le seuil de solde.
    public static var fxTriggerBalanceAbove: String {
        t("finance.fx.trigger_balance_above", "Dès que le solde dépasse %@")
    }
    /// Format à une chaîne : le taux visé.
    public static var fxTriggerRateReaches: String {
        t("finance.fx.trigger_rate_reaches", "Quand le taux atteint %@")
    }
    /// Format à une chaîne : la fréquence.
    public static var fxTriggerScheduled: String {
        t("finance.fx.trigger_scheduled", "Selon la fréquence : %@")
    }

    // MARK: - PFM — budgets et catégories (ch. 42)

    public static var pfmNewBudget: String { t("finance.pfm.new_budget", "Nouveau budget") }
    public static var pfmCreateBudget: String { t("finance.pfm.create_budget", "Créer le budget") }
    public static var pfmCreatingBudget: String { t("finance.pfm.creating_budget", "Création du budget…") }
    public static var pfmBudgetLabel: String { t("finance.pfm.budget_label", "Intitulé") }
    public static var pfmBudgetLimit: String { t("finance.pfm.budget_limit", "Limite") }
    public static var pfmBudgetCategory: String { t("finance.pfm.budget_category", "Catégorie") }
    public static var pfmBudgetCategoryOptional: String {
        t("finance.pfm.budget_category_optional", "Toutes les dépenses si vide")
    }
    public static var pfmBudgetPeriodNote: String {
        t("finance.pfm.budget_period_note", "Le budget s'applique à la période affichée.")
    }
    public static var pfmRecategorize: String {
        t("finance.pfm.recategorize", "Corriger la catégorie")
    }
    public static var pfmRecategorizing: String {
        t("finance.pfm.recategorizing", "Envoi de la correction…")
    }
    public static var pfmApplyCategory: String {
        t("finance.pfm.apply_category", "Appliquer la catégorie")
    }
    public static var pfmNoCategory: String {
        t("finance.pfm.no_category", "Aucune catégorie disponible pour cette période.")
    }

    // MARK: - Crédit — éligibilité, suivi, solde anticipé (ch. 38–39)

    public static var creditCheckEligibility: String {
        t("finance.credit.check_eligibility", "Vérifier mon éligibilité")
    }
    public static var creditLikelyEligible: String {
        t("finance.credit.likely_eligible", "Probablement éligible")
    }
    public static var creditUnlikelyEligible: String {
        t("finance.credit.unlikely_eligible", "Peu probable en l'état")
    }
    public static var creditMissingDocuments: String {
        t("finance.credit.missing_documents", "Documents manquants :")
    }
    public static var creditEligibilityIndicative: String {
        t("finance.credit.eligibility_indicative",
          "Indicatif. Seule la décision du prêteur fait foi.")
    }
    public static var creditApplicationState: String {
        t("finance.credit.application_state", "État de la demande")
    }
    public static var creditEarlyRepayment: String {
        t("finance.credit.early_repayment", "Remboursement anticipé")
    }
    public static var creditEarlyRepaymentQuote: String {
        t("finance.credit.early_repayment_quote", "Demander un décompte")
    }
    public static var creditEarlyRepaymentNote: String {
        t("finance.credit.early_repayment_note",
          "Décompte établi par le prêteur, valable jusqu'à sa date d'échéance.")
    }

    public static var creditStateDraft: String { t("finance.credit.state.draft", "Brouillon") }
    public static var creditStateSubmitted: String { t("finance.credit.state.submitted", "Déposée") }
    public static var creditStateUnderReview: String {
        t("finance.credit.state.under_review", "En cours d'examen")
    }
    public static var creditStateActionRequired: String {
        t("finance.credit.state.action_required", "Action requise")
    }
    public static var creditStateApproved: String { t("finance.credit.state.approved", "Accordée") }
    public static var creditStateDeclined: String { t("finance.credit.state.declined", "Refusée") }
    public static var creditStateOfferIssued: String {
        t("finance.credit.state.offer_issued", "Offre émise")
    }
    public static var creditStateOfferExpired: String {
        t("finance.credit.state.offer_expired", "Offre expirée")
    }
    public static var creditStateAccepted: String { t("finance.credit.state.accepted", "Offre acceptée") }
    public static var creditStateDisbursementPending: String {
        t("finance.credit.state.disbursement_pending", "Décaissement en cours")
    }
    public static var creditStateActive: String { t("finance.credit.state.active", "Crédit en cours") }
    public static var creditStateClosed: String { t("finance.credit.state.closed", "Soldé") }

    // MARK: - Portefeuille et ordres (ch. 41)

    public static var portfolioTitle: String { t("finance.portfolio.title", "Portefeuille") }
    public static var portfolioLoading: String {
        t("finance.portfolio.loading", "Chargement du portefeuille…")
    }
    public static var portfolioEmpty: String {
        t("finance.portfolio.empty", "Vous ne détenez aucun produit.")
    }
    /// Format à une chaîne : le nombre de parts.
    public static var portfolioUnits: String { t("finance.portfolio.units", "%@ parts") }
    /// Format à une chaîne : la date de valorisation.
    public static var portfolioValuedAt: String {
        t("finance.portfolio.valued_at", "Valorisé le %@")
    }

    public static var orderLoading: String { t("finance.order.loading", "Chargement de l'ordre…") }
    public static var investmentOrderTitle: String { t("finance.investment.order.title", "Ordre") }
    public static var investmentOrderSide: String { t("finance.investment.order.side", "Sens") }
    public static var investmentOrderState: String { t("finance.investment.order.state", "État") }
    public static var investmentOrderProduct: String { t("finance.investment.order.product", "Produit") }
    public static var investmentOrderRequested: String {
        t("finance.investment.order.requested", "Montant demandé")
    }
    public static var investmentOrderExecuted: String {
        t("finance.investment.order.executed", "Montant exécuté")
    }
    public static var investmentOrderNotExecuted: String {
        t("finance.investment.order.not_executed", "Pas encore exécuté.")
    }
    public static var investmentOrderPlacedAt: String {
        t("finance.investment.order.placed_at", "Passé le")
    }
    public static var investmentOrderReceipt: String {
        t("finance.investment.order.receipt", "Avis d'exécution")
    }
    public static var investmentOrderCancel: String {
        t("finance.investment.order.cancel", "Annuler l'ordre")
    }
    public static var investmentOrderCancelTitle: String {
        t("finance.investment.order.cancel_title", "Annuler cet ordre ?")
    }
    public static var investmentOrderCancelDetail: String {
        t("finance.investment.order.cancel_detail",
          "L'ordre ne sera pas exécuté. Un ordre déjà exécuté ne s'annule pas — il faut le racheter.")
    }
    public static var investmentRedeem: String { t("finance.investment.redeem", "Racheter") }

    public static var investmentStateDraft: String { t("finance.investment.state.draft", "Brouillon") }
    public static var investmentStateSubmitted: String { t("finance.investment.state.submitted", "Transmis") }
    public static var investmentStatePending: String { t("finance.investment.state.pending", "En attente") }
    public static var investmentStatePartial: String {
        t("finance.investment.state.partial", "Partiellement exécuté")
    }
    public static var investmentStateExecuted: String { t("finance.investment.state.executed", "Exécuté") }
    public static var investmentStateRejected: String { t("finance.investment.state.rejected", "Rejeté") }
    public static var investmentStateCancelled: String { t("finance.investment.state.cancelled", "Annulé") }

    // MARK: - Épargne — mouvements (ch. 40)

    public static var savingsBalance: String { t("finance.savings.balance", "Solde") }
    public static var savingsYield: String { t("finance.savings.yield", "Rendement") }
    public static var savingsNewPocket: String { t("finance.savings.new_pocket", "Nouveau pocket") }
    public static var savingsCreate: String { t("finance.savings.create", "Créer le pocket") }
    public static var savingsCreating: String { t("finance.savings.creating", "Création du pocket…") }
    public static var savingsPocketName: String { t("finance.savings.pocket_name", "Nom") }
    public static var savingsPocketKind: String { t("finance.savings.pocket_kind", "Type") }
    public static var savingsGoalOptional: String {
        t("finance.savings.goal_optional", "Objectif (facultatif)")
    }
    public static var savingsGoalDate: String { t("finance.savings.goal_date", "Date cible") }
    public static var savingsClose: String { t("finance.savings.close", "Fermer le pocket") }
    public static var savingsCloseConfirmTitle: String {
        t("finance.savings.close_confirm_title", "Fermer ce pocket ?")
    }
    public static var savingsCloseConfirmDetail: String {
        t("finance.savings.close_confirm_detail",
          "Le solde restant vous est reversé. Les règles d'alimentation sont révoquées.")
    }
    /// Format à une chaîne : la date d'échéance.
    public static var savingsMaturesAt: String {
        t("finance.savings.matures_at", "Disponible à partir du %@")
    }
    public static var savingsMovementNote: String {
        t("finance.savings.movement_note", "Le montant disponible est vérifié par votre banque.")
    }

    public static var savingsKindPocket: String { t("finance.savings.kind.pocket", "Pocket") }
    public static var savingsKindVault: String { t("finance.savings.kind.vault", "Coffre") }
    public static var savingsKindLocked: String { t("finance.savings.kind.locked", "Épargne bloquée") }
    public static var savingsKindPartner: String { t("finance.savings.kind.partner", "Produit partenaire") }
    public static var savingsKindGroup: String { t("finance.savings.kind.group", "Objectif de groupe") }
    public static var savingsKindTontine: String { t("finance.savings.kind.tontine", "Tontine") }

    public static var savingsKindPocketNote: String {
        t("finance.savings.kind.pocket_note", "Vous alimentez et retirez librement.")
    }
    public static var savingsKindVaultNote: String {
        t("finance.savings.kind.vault_note", "Retraits possibles, avec une confirmation supplémentaire.")
    }
    public static var savingsKindLockedNote: String {
        t("finance.savings.kind.locked_note", "Aucun retrait avant l'échéance choisie.")
    }
    public static var savingsKindPartnerNote: String {
        t("finance.savings.kind.partner_note", "Les conditions sont fixées par l'établissement partenaire.")
    }
    public static var savingsKindGroupNote: String {
        t("finance.savings.kind.group_note", "Plusieurs personnes alimentent le même objectif.")
    }
    public static var savingsKindTontineNote: String {
        t("finance.savings.kind.tontine_note", "Vous vous engagez sur un tour de cotisations.")
    }

    // MARK: - Suites d'une transaction (ch. 7)

    public static var actionsTitle: String { t("finance.actions.title", "Cette transaction") }
    public static var actionsReceipt: String { t("finance.actions.receipt", "Voir le reçu") }
    public static var actionsDispute: String { t("finance.actions.dispute", "Signaler un problème") }
    public static var draftPlaceholder: String {
        t("finance.draft.placeholder", "Que voulez-vous faire ? Ex. envoie 5000 à Jean")
    }
    public static var handoffContextMismatch: String {
        t("finance.handoff.context_mismatch",
          "Cette opération ne peut pas s'ouvrir depuis cette conversation.")
    }
    public static var draftSubmit: String { t("finance.draft.submit", "Continuer") }
    public static var draftNoAction: String {
        t("finance.draft.no_action", "Aucune opération reconnue. Choisissez un service ci-dessous.")
    }
    public static var draftActionUnavailable: String {
        t("finance.draft.action_unavailable", "Cette opération n'est pas disponible ici.")
    }
    public static var copilotName: String { t("finance.copilot.name", "Waangu Copilot") }
    public static var copilotIntroPrepare: String {
        t("finance.copilot.intro_prepare",
          "Je prépare, vous confirmez. Je ne paie jamais à votre place.")
    }
    public static var copilotPlaceholder: String {
        t("finance.copilot.placeholder", "Demandez à Waangu Copilot…")
    }
    public static var copilotSend: String { t("finance.copilot.send", "Envoyer à Waangu Copilot") }
    public static var copilotOpenReview: String { t("finance.copilot.open_review", "Ouvrir et vérifier") }
    public static var copilotProposalDetail: String {
        t("finance.copilot.proposal_detail",
          "Vous choisissez le bénéficiaire, vérifiez et confirmez dans l'écran suivant.")
    }
    public static var copilotAskRecipientSend: String {
        t("finance.copilot.ask_recipient_send", "À qui voulez-vous envoyer de l'argent ?")
    }
    public static var copilotRecipientPlaceholder: String {
        t("finance.copilot.recipient_placeholder", "Nom ou numéro de téléphone")
    }
    public static var copilotRecipientPickHint: String {
        t("finance.copilot.recipient_pick_hint", "Choisissez un contact ou tapez un numéro de téléphone.")
    }
    public static var copilotRecipientVerified: String {
        t("finance.copilot.recipient_verified", "Vérifié")
    }
    public static var copilotAskAmountSend: String {
        t("finance.copilot.ask_amount_send", "Combien voulez-vous envoyer ?")
    }
    public static func copilotAmountPlaceholder(_ currency: String) -> String {
        t("finance.copilot.amount_placeholder", "Montant en %@").replacingOccurrences(of: "%@", with: currency)
    }
    public static var copilotAmountInvalid: String {
        t("finance.copilot.amount_invalid", "Entrez un montant valide.")
    }
    public static var copilotQuoteReady: String {
        t("finance.copilot.quote_ready", "Voici le devis. Vérifiez, puis confirmez.")
    }
    public static var copilotStepUpCancelled: String {
        t("finance.copilot.step_up_cancelled", "Authentification annulée. Rien n'a été envoyé.")
    }
    public static var copilotSubmitted: String {
        t("finance.copilot.submitted", "Transmis à Finance. Le statut ci-dessous se met à jour.")
    }
    public static var copilotConditionsChanged: String {
        t("finance.copilot.conditions_changed", "Les conditions ont changé. Voici le nouveau devis.")
    }
    public static var copilotQuoteRefreshed: String {
        t("finance.copilot.quote_refreshed", "Le devis a expiré. Voici un devis actualisé.")
    }
    public static var copilotCancelled: String {
        t("finance.copilot.cancelled", "Annulé. Rien n'a été envoyé.")
    }
    public static var copilotAskRecipientRequest: String {
        t("finance.copilot.ask_recipient_request", "À qui voulez-vous demander de l'argent ?")
    }
    public static var copilotAskAmountRequest: String {
        t("finance.copilot.ask_amount_request", "Combien voulez-vous demander ?")
    }
    public static var copilotRequestReady: String {
        t("finance.copilot.request_ready", "Voici la demande. Vérifiez, puis envoyez-la.")
    }
    public static var copilotRequestFrom: String {
        t("finance.copilot.request_from", "De")
    }
    public static var copilotRequestSend: String {
        t("finance.copilot.request_send", "Envoyer la demande")
    }
    public static var copilotRequestSent: String {
        t("finance.copilot.request_sent", "Demande envoyée. Aucun argent n'a bougé : la personne paiera de son côté.")
    }
    public static var copilotRequestCancelled: String {
        t("finance.copilot.request_cancelled", "Annulé. Aucune demande n'a été envoyée.")
    }
    public static var copilotAskBillCategory: String {
        t("finance.copilot.ask_bill_category", "Quel type de facture voulez-vous payer ?")
    }
    public static var copilotAskBiller: String {
        t("finance.copilot.ask_biller", "Quel facturier ?")
    }
    public static var copilotAskAmountBill: String {
        t("finance.copilot.ask_amount_bill", "Combien voulez-vous payer ?")
    }
    public static var copilotSkip: String {
        t("finance.copilot.skip", "Passer")
    }
    public static var copilotFieldRequired: String {
        t("finance.copilot.field_required", "Ce champ est obligatoire.")
    }
    public static var copilotAskTopUpNumber: String {
        t("finance.copilot.ask_top_up_number", "Quel numéro voulez-vous recharger ?")
    }
    public static var copilotMyNumber: String {
        t("finance.copilot.my_number", "Mon numéro")
    }
    /// L'opérateur est celui que le serveur a nommé pour ce numéro.
    public static func copilotAskTopUpProduct(_ operatorName: String) -> String {
        t("finance.copilot.ask_top_up_product", "Quel forfait %@ ?")
            .replacingOccurrences(of: "%@", with: operatorName)
            .replacingOccurrences(of: "  ", with: " ")
    }
    public static var copilotAskScan: String {
        t("finance.copilot.ask_scan", "Visez le code du marchand.")
    }
    public static var copilotScanned: String {
        t("finance.copilot.scanned", "Code lu")
    }
    public static var copilotScanPaymentLink: String {
        t("finance.copilot.scan_payment_link", "Ce code est un lien de paiement : il se paie depuis la conversation où il a été envoyé.")
    }
    public static var copilotAskInvoiceReference: String {
        t("finance.copilot.invoice_reference_ask", "Quelle est la référence de la facture ?")
    }
    public static var copilotInvoiceReferencePlaceholder: String {
        t("finance.copilot.invoice_reference_placeholder", "Référence de la facture")
    }
    public static var copilotInvoiceChanged: String {
        t("finance.copilot.invoice_changed", "La facture a changé depuis sa lecture : voici la version à jour.")
    }
    public static var copilotAskCashInChannel: String {
        t("finance.copilot.cashin_channel_ask", "Comment voulez-vous déposer ?")
    }
    public static var copilotAskCashOutChannel: String {
        t("finance.copilot.cashout_channel_ask", "Où voulez-vous retirer ?")
    }
    public static var copilotAskAmountCashIn: String {
        t("finance.copilot.cashin_amount_ask", "Combien voulez-vous déposer ?")
    }
    public static var copilotAskAmountCashOut: String {
        t("finance.copilot.cashout_amount_ask", "Combien voulez-vous retirer ?")
    }
    public static var copilotChannel: String {
        t("finance.copilot.channel", "Canal")
    }
    public static var copilotAskCashInAgent: String {
        t("finance.copilot.cashin_agent_ask", "Chez l'agent, saisissez son identifiant pour le vérifier.")
    }
    public static var copilotAskCashInHandover: String {
        t("finance.copilot.cashin_handover_ask", "Remettez les espèces à l'agent, puis confirmez.")
    }
    public static var copilotAskCashOutAgent: String {
        t("finance.copilot.cashout_agent_ask", "Saisissez l'identifiant de l'agent pour émettre votre code de retrait.")
    }
    public static var copilotCashOutCodeReady: String {
        t("finance.copilot.cashout_code_ready", "Voici votre code de retrait. Il ne s'affiche qu'une fois : montrez-le à l'agent.")
    }
    public static var copilotScannerClosed: String {
        t("finance.copilot.scanner_closed", "Lecteur fermé")
    }
    public static var copilotPINTitle: String {
        t("finance.copilot.pin_title", "Saisissez votre code PIN")
    }
    public static var copilotPINUnavailable: String {
        t("finance.copilot.pin_unavailable", "La confirmation par PIN n'est pas encore disponible : utilisez Face ID.")
    }
    public static var copilotCashOutCodeNotKept: String {
        t("finance.copilot.cashout_code_not_kept", "Code de retrait affiché — il n'est pas conservé.")
    }
    public static var copilotDeleteTitle: String {
        t("finance.copilot.delete_title", "Supprimer la conversation Waangu Copilot ?")
    }
    public static var copilotDeleteMessage: String {
        t("finance.copilot.delete_message", "Son historique sera effacé de cet appareil. Les opérations déjà faites ne sont pas touchées.")
    }
    public static var copilotSlashTitle: String {
        t("finance.copilot.slash_title", "Commandes")
    }
    public static var copilotSlashNoMatch: String {
        t("finance.copilot.slash_no_match", "Aucune commande ne correspond.")
    }
    public static var copilotReportProblem: String {
        t("finance.copilot.report_problem", "Signaler un problème")
    }
    public static var copilotDisputeNoOperation: String {
        t("finance.copilot.dispute_no_operation", "Aucune opération de cette conversation ne peut être signalée pour l'instant.")
    }
    public static var copilotDisputePickOperation: String {
        t("finance.copilot.dispute_pick_operation", "Quelle opération voulez-vous signaler ?")
    }
    public static var copilotDisputePickReason: String {
        t("finance.copilot.dispute_pick_reason", "Quel est le problème ?")
    }
    public static var copilotDisputeAskDescription: String {
        t("finance.copilot.dispute_ask_description", "Décrivez ce qui s'est passé.")
    }
    public static var copilotDisputeAgree: String {
        t("finance.copilot.dispute_agree", "J'accepte")
    }
    public static var copilotDisputeDecline: String {
        t("finance.copilot.dispute_decline", "Annuler")
    }
    public static var copilotDisputeFiled: String {
        t("finance.copilot.dispute_filed", "Signalement envoyé. Le support le suit dans un dossier à part.")
    }
    public static var copilotDisputeStatus: String {
        t("finance.copilot.dispute_status", "Statut")
    }
    public static var copilotDisputeFirstResponse: String {
        t("finance.copilot.dispute_first_response", "Réponse du support avant")
    }
    public static var copilotDisputeResolveBy: String {
        t("finance.copilot.dispute_resolve_by", "Résolution avant")
    }
    /// La catégorie du serveur, traduite quand l'app en connaît la clé — sinon lisible telle quelle.
    public static func disputeCategoryLabel(_ raw: String) -> String {
        t("finance.dispute.category." + raw.lowercased(),
          raw.replacingOccurrences(of: "_", with: " ").capitalized)
    }
    public static var copilotRequestRefund: String {
        t("finance.copilot.request_refund", "Demander un remboursement")
    }
    public static var copilotRequestReversal: String {
        t("finance.copilot.request_reversal", "Demander une extourne")
    }
    public static var copilotRefundTitle: String {
        t("finance.copilot.refund_title", "Remboursement")
    }
    public static var copilotNothingToRefund: String {
        t("finance.copilot.nothing_to_refund", "Aucune opération de cette conversation ne peut être remboursée pour l'instant.")
    }
    public static var copilotNothingToReverse: String {
        t("finance.copilot.nothing_to_reverse", "Aucune opération de cette conversation ne peut faire l'objet d'une extourne pour l'instant.")
    }
    public static var copilotRefundPickOperation: String {
        t("finance.copilot.refund_pick_operation", "Quelle opération voulez-vous rembourser ?")
    }
    public static var copilotReversalPickOperation: String {
        t("finance.copilot.reversal_pick_operation", "Quelle opération voulez-vous faire extourner ?")
    }
    public static var copilotReversalAskReason: String {
        t("finance.copilot.reversal_ask_reason", "Pourquoi demandez-vous l'extourne ?")
    }
    public static var copilotReversalConfirm: String {
        t("finance.copilot.reversal_confirm", "Cette demande part chez Finance, qui l'exécute. Rien n'est annulé tant qu'elle ne l'a pas fait.")
    }
    public static var copilotReversalSend: String {
        t("finance.copilot.reversal_send", "Envoyer la demande")
    }
    public static var copilotReversalRequested: String {
        t("finance.copilot.reversal_requested", "Demande envoyée. Finance l'examine : rien n'est encore extourné.")
    }
    public static func copilotRefundFull(_ amount: String) -> String {
        t("finance.copilot.refund_full", "Tout : %@").replacingOccurrences(of: "%@", with: amount)
    }
    public static func copilotRefundAskAmount(_ amount: String) -> String {
        t("finance.copilot.refund_ask_amount", "Combien rembourser ? Jusqu'à %@.").replacingOccurrences(of: "%@", with: amount)
    }
    public static var copilotShareReceipt: String {
        t("finance.copilot.share_receipt", "Partager le reçu dans la conversation")
    }
    public static var copilotReceiptShared: String {
        t("finance.copilot.receipt_shared", "Reçu partagé dans la conversation.")
    }
    public static var copilotAnswerRequest: String {
        t("finance.copilot.answer_request", "Répondre à une demande")
    }
    public static var copilotAnswerNone: String {
        t("finance.copilot.answer_none", "Aucune demande en attente de votre réponse dans cette conversation.")
    }
    public static var copilotAnswerPick: String {
        t("finance.copilot.answer_pick", "Quelle demande ?")
    }
    public static func copilotAnswerAsk(_ amount: String) -> String {
        t("finance.copilot.answer_ask", "Demande de %@. Que faire ?").replacingOccurrences(of: "%@", with: amount)
    }
    public static var copilotAnswerKeep: String {
        t("finance.copilot.answer_keep", "Ne pas refuser")
    }
    public static var copilotAnswerDeclined: String {
        t("finance.copilot.answer_declined", "Demande refusée. Rien n'a été débité.")
    }
    public static var copilotCancelKeep: String {
        t("finance.copilot.cancel_keep", "Ne pas annuler")
    }
    public static var copilotSplitAskLabel: String {
        t("finance.copilot.split_ask_label", "Comment s'appelle ce partage ?")
    }
    public static var copilotSplitAskTotal: String {
        t("finance.copilot.split_ask_total", "Quel est le total à partager ?")
    }
    public static var copilotSplitPickParticipants: String {
        t("finance.copilot.split_pick_participants", "Avec qui partagez-vous ?")
    }
    public static var copilotSplitAskStrategy: String {
        t("finance.copilot.split_ask_strategy", "Comment répartir ?")
    }
    public static var copilotSplitCreate: String {
        t("finance.copilot.split_create", "Créer le partage")
    }
    public static var copilotSplitCreated: String {
        t("finance.copilot.split_created", "Partage créé. Chacun le reçoit dans sa conversation et choisit de payer sa part.")
    }
    public static func copilotSplitAddMore(_ names: String) -> String {
        t("finance.copilot.split_add_more", "Ajoutés : %@.").replacingOccurrences(of: "%@", with: names)
    }
    public static func copilotSplitAskAmountFor(_ name: String) -> String {
        t("finance.copilot.split_ask_amount_for", "Combien doit %@ ?").replacingOccurrences(of: "%@", with: name)
    }
    public static func copilotSplitAskWeightFor(_ name: String) -> String {
        t("finance.copilot.split_ask_weight_for", "Quel poids pour %@ ?").replacingOccurrences(of: "%@", with: name)
    }
    public static func copilotSplitSummary(_ label: String, _ total: String, _ names: String) -> String {
        t("finance.copilot.split_summary", "%1$@ · %2$@ · avec %3$@.")
            .replacingOccurrences(of: "%1$@", with: label)
            .replacingOccurrences(of: "%2$@", with: total)
            .replacingOccurrences(of: "%3$@", with: names)
    }
    public static var copilotIssueLink: String {
        t("finance.copilot.issue_link", "Créer un lien de paiement")
    }
    public static var copilotPaymentLinkTitle: String {
        t("finance.copilot.payment_link_title", "Lien de paiement")
    }
    public static var copilotPaymentLinkNote: String {
        t("finance.copilot.payment_link_note", "Le lien montre la demande seulement : payer exige le consentement du payeur.")
    }
    public static var copilotShareLink: String {
        t("finance.copilot.share_link", "Partager le lien")
    }
    public static var copilotPaymentLinkNotKept: String {
        t("finance.copilot.payment_link_not_kept", "Lien de paiement créé — il n'est pas conservé.")
    }
    public static var copilotToolBalance: String { t("finance.copilot.tool_balance", "Mon solde") }
    public static var copilotToolStatus: String {
        t("finance.copilot.tool_status", "Statut d'une opération")
    }
    public static var copilotToolCapabilities: String {
        t("finance.copilot.tool_capabilities", "Ce que je peux faire ici")
    }
    public static var copilotToolRefused: String {
        t("finance.copilot.tool_refused", "Cet outil n'est pas disponible.")
    }
    public static var copilotTextRefused: String {
        t("finance.copilot.text_refused", "Ce message ne peut pas être traité. Utilisez les suggestions.")
    }
    public static var noteTranslate: String { t("finance.note.translate", "Traduire la note") }
    public static var noteTranslating: String { t("finance.note.translating", "Traduction en cours…") }
    public static var noteMachineTranslation: String {
        t("finance.note.machine_translation", "Traduction automatique — le texte d'origine fait foi.")
    }
    public static var noteAlreadyInLanguage: String {
        t("finance.note.already_in_language", "La note est déjà dans votre langue.")
    }
    public static var noteLanguageUncertain: String {
        t("finance.note.language_uncertain", "La langue de la note n'a pas pu être reconnue.")
    }
    public static var actionsCancel: String { t("finance.actions.cancel", "Annuler l'opération") }
    public static var actionsCancelConfirm: String {
        t("finance.actions.cancel_confirm", "Annuler cette opération ?")
    }
    public static var actionsCancelling: String { t("finance.actions.cancelling", "Annulation en cours…") }
    public static var cancelDone: String { t("finance.cancel.done", "Opération annulée.") }
    public static var cancelRequested: String {
        t("finance.cancel.requested",
          "Annulation demandée. Finance doit la confirmer : l'opération n'est pas encore annulée.")
    }
    public static var actionsCheckDelivery: String { t("finance.actions.check_delivery", "Vérifier la livraison") }
    public static var actionsCheckingDelivery: String {
        t("finance.actions.checking_delivery", "Vérification auprès du fournisseur…")
    }
    public static var deliveryConfirmed: String {
        t("finance.delivery.confirmed", "Le fournisseur a confirmé la livraison.")
    }
    public static var deliveryPending: String {
        t("finance.delivery.pending",
          "Paiement reçu, livraison pas encore confirmée par le fournisseur. Ne payez pas une seconde fois.")
    }
    public static var actionsSupport: String { t("finance.actions.support", "Contacter le support") }

    // MARK: - Support corrélé (ch. 7)

    public static var supportTitle: String { t("finance.support.title", "Contacter le support") }
    public static var supportLoading: String { t("finance.support.loading", "Préparation du dossier…") }
    public static var supportOpening: String { t("finance.support.opening", "Ouverture du dossier…") }
    public static var supportYourMessage: String { t("finance.support.your_message", "Votre message") }
    public static var supportMessagePlaceholder: String {
        t("finance.support.message_placeholder", "Décrivez ce qui s'est passé")
    }
    public static var supportAttachedContext: String {
        t("finance.support.attached_context", "Transmis avec votre message")
    }
    public static var supportObservedStatus: String { t("finance.support.status", "Statut observé") }
    public static var supportIntent: String { t("finance.support.intent", "Paiement") }
    public static var supportProvider: String { t("finance.support.provider", "Référence fournisseur") }
    public static var supportCustomer: String { t("finance.support.customer", "Référence client") }
    public static var supportCorrelation: String { t("finance.support.correlation", "Corrélation") }
    public static var supportHistory: String { t("finance.support.history", "Historique des statuts") }
    public static var supportOpen: String { t("finance.support.open", "Ouvrir le dossier") }
    public static var supportOpened: String { t("finance.support.opened", "Dossier ouvert") }
    public static var supportContextNote: String {
        t("finance.support.context_note",
          "Ces informations sont transmises au support pour qu'il n'ait pas à vous les redemander.")
    }
    /// Format à un entier : le délai en heures.
    public static var supportExpectedResponse: String {
        t("finance.support.expected_response", "Réponse attendue sous environ %d h")
    }

    // MARK: - Formulaires distants (ch. 7)

    public static var formTitle: String { t("finance.form.title", "Formulaire") }
    public static var formNotIdentified: String {
        t("finance.form.not_identified", "Ce formulaire n'est pas identifié pour cette conversation.")
    }
    public static var formLoading: String { t("finance.form.loading", "Chargement du formulaire…") }
    public static var formSubmitting: String { t("finance.form.submitting", "Envoi…") }
    public static var formSubmit: String { t("finance.form.submit", "Envoyer") }
    public static var formNoChoice: String { t("finance.form.no_choice", "Aucun choix") }
    public static var formServerValidates: String {
        t("finance.form.server_validates", "Les champs sont vérifiés par le partenaire.")
    }
    public static var formNeedsUpdate: String {
        t("finance.form.needs_update",
          "Ce formulaire contient un champ obligatoire que cette version ne sait pas afficher. Mettez l'application à jour.")
    }
    public static var formFieldNeedsUpdate: String {
        t("finance.form.field_needs_update", "Ce champ nécessite une mise à jour de l'application.")
    }

    public static var returnTitle: String { t("finance.return.title", "Retour") }
    public static var returnKind: String { t("finance.return.kind", "Type de demande") }
    public static var returnKindRefund: String { t("finance.return.kind.refund", "Remboursement") }
    public static var returnKindExchange: String { t("finance.return.kind.exchange", "Échange") }
    public static var returnKindRepair: String { t("finance.return.kind.repair", "Réparation") }
    public static var returnItems: String { t("finance.return.items", "Articles concernés") }
    public static var returnReason: String { t("finance.return.reason", "Motif") }
    public static var returnComment: String { t("finance.return.comment", "Précisions (facultatif)") }
    public static var returnSubmit: String { t("finance.return.submit", "Envoyer la demande") }
    public static var returnSubmitting: String { t("finance.return.submitting", "Envoi de la demande…") }
    public static var returnSubmitted: String {
        t("finance.return.submitted", "Demande envoyée au marchand.")
    }

    // MARK: - QR présenté (ch. 7)

    public static var qrPresentTitle: String { t("finance.qr.present.title", "Me faire payer") }
    public static var qrPresentIssuing: String {
        t("finance.qr.present.issuing", "Génération du code…")
    }
    public static var qrPresentAccessibility: String {
        t("finance.qr.present.a11y", "Code QR de paiement à présenter")
    }
    public static var qrPresentRenderFailed: String {
        t("finance.qr.present.render_failed", "Le code n'a pas pu être affiché.")
    }
    public static var qrPresentOpenAmount: String {
        t("finance.qr.present.open_amount", "Le payeur saisit le montant")
    }
    public static var qrPresentReference: String {
        t("finance.qr.present.reference", "Ou dictez cette référence")
    }
    public static var qrPresentExpired: String {
        t("finance.qr.present.expired", "Ce code a expiré.")
    }
    public static var qrPresentRenew: String { t("finance.qr.present.renew", "Générer un nouveau code") }
    /// Format à deux entiers : minutes, secondes.
    public static var qrPresentExpiresIn: String {
        t("finance.qr.present.expires_in", "Valide encore %d min %02d s")
    }
    public static var optional: String { t("finance.common.optional", "Facultatif") }
    public static var reason: String { t("finance.common.reason", "Motif") }
    public static var amount: String { t("finance.common.amount", "Montant") }
    public static var checkingRecipient: String {
        t("finance.common.checking_recipient", "Vérification du bénéficiaire…")
    }

    // MARK: Bénéficiaire

    public static var recipientUnverified: String {
        t("finance.recipient.unverified", "Bénéficiaire non vérifié")
    }
    public static var recipientRevoked: String {
        t("finance.recipient.revoked", "Vérification retirée")
    }
    public static var recipientFirstTime: String {
        t("finance.recipient.first_time", "Premier envoi vers cette personne")
    }
    public static var recipientToCheck: String {
        t("finance.recipient.to_check", "Bénéficiaire à vérifier")
    }
    public static var recipientUnavailable: String {
        t("finance.recipient.unavailable", "Ce bénéficiaire n'est pas disponible.")
    }

    // MARK: Demande d'argent

    public static var requestTitle: String { t("finance.request.title", "Demander de l'argent") }
    public static var requestSubmit: String { t("finance.request.submit", "Envoyer la demande") }
    public static var requestSending: String { t("finance.request.sending", "Envoi de la demande…") }
    public static var requestFreeAmountHint: String {
        t("finance.request.free_amount_hint",
          "Laissez vide pour que la personne choisisse le montant.")
    }
    public static var requestNoDebitNotice: String {
        t("finance.request.no_debit_notice",
          "Une demande n'engage aucun paiement tant que la personne ne l'accepte pas.")
    }

    // MARK: Envoi d'argent

    public static var sendTitle: String { t("finance.send.title", "Envoyer de l'argent") }
    public static var sendContinue: String { t("finance.send.continue", "Continuer") }
    public static var sendQuoting: String { t("finance.send.quoting", "Calcul des frais…") }
    public static var sendSubmitting: String { t("finance.send.submitting", "Envoi en cours…") }
    public static var sendDone: String { t("finance.send.done", "Envoi transmis.") }
    public static var sendConfirm: String { t("finance.send.confirm", "Confirmer l'envoi") }
    public static var sendAcceptNewTerms: String {
        t("finance.send.accept_new_terms", "Accepter les nouvelles conditions")
    }
    public static var sendFeesLater: String {
        t("finance.send.fees_later",
          "Les frais et le taux vous seront montrés avant confirmation.")
    }
    public static var sendQuoteLimited: String {
        t("finance.send.quote_limited",
          "Ce récapitulatif est valable un temps limité. Passé ce délai, un nouveau devis sera demandé.")
    }
    public static var sendMissingAmount: String {
        t("finance.send.missing_amount", "Saisissez un montant.")
    }
    public static var sendOperationLost: String {
        t("finance.send.operation_lost", "Opération introuvable. Reprenez depuis le début.")
    }
    public static var sendRecipientUnavailable: String {
        t("finance.send.recipient_unavailable",
          "Ce bénéficiaire n'est pas disponible pour un envoi.")
    }

    // MARK: Dépôt (ch. 19)

    public static var cashInTitle: String { t("finance.cashin.title", "Déposer de l'argent") }
    public static var cashInNoChannel: String {
        t("finance.cashin.no_channel", "Aucun canal de dépôt disponible dans votre pays.")
    }
    public static var cashInReference: String { t("finance.cashin.reference", "Référence de dépôt") }
    public static var cashInSteps: String { t("finance.cashin.steps", "Marche à suivre") }
    // MARK: Dépôt chez un agent (§6)

    public static var cashInAgentID: String { t("finance.cashin.agent_id", "Identifiant de l'agent") }
    public static var cashInVerifyAgent: String { t("finance.cashin.verify_agent", "Vérifier l'agent") }
    public static var cashInAgentVerified: String {
        t("finance.cashin.agent_verified", "Agent vérifié")
    }
    public static var cashInConfirmPhysical: String {
        t("finance.cashin.confirm_physical", "L'agent a reçu les espèces")
    }
    public static var cashInPhysicalReceived: String {
        t("finance.cashin.physical_received", "Espèces remises à l'agent")
    }
    /// **Ni succès, ni échec.** L'agent a l'argent, le compte ne l'a pas encore :
    /// confondre les deux est `CF_038`.
    public static var cashInAwaitingCredit: String {
        t("finance.cashin.awaiting_credit",
          "Le crédit apparaîtra sur votre compte une fois le dépôt confirmé par le canal. Cette remise ne vaut pas encore crédit.")
    }
    public static var cashInStepVerify: String {
        t("finance.cashin.step_verify", "Vérifier l'agent")
    }
    public static var cashInStepHandOver: String {
        t("finance.cashin.step_hand_over", "Remettre les espèces")
    }
    public static var cashInStepCredit: String {
        t("finance.cashin.step_credit", "Crédit sur votre compte")
    }
    public static var cashInCredited: String {
        t("finance.cashin.credited", "Dépôt crédité sur votre compte.")
    }

    public static var cashInPendingWarning: String {
        t("finance.cashin.pending_warning",
          "Un dépôt est déjà en attente. Ne versez pas une seconde fois avant sa confirmation.")
    }
    public static var cashInExpired: String {
        t("finance.cashin.expired", "Cette instruction a expiré. Demandez-en une nouvelle.")
    }

    // MARK: Retrait (ch. 20)

    public static var cashOutTitle: String { t("finance.cashout.title", "Retirer de l'argent") }
    public static var cashOutNoChannel: String {
        t("finance.cashout.no_channel", "Aucun canal de retrait disponible.")
    }
    public static var cashOutCodeLabel: String { t("finance.cashout.code", "Code de retrait") }
    public static var cashOutRevoke: String { t("finance.cashout.revoke", "Révoquer ce code") }

    // MARK: Retrait chez un agent (§6)

    public static var cashOutAgentID: String { t("finance.cashout.agent_id", "Identifiant de l'agent") }
    public static var cashOutIssueToken: String {
        t("finance.cashout.issue_token", "Obtenir le code de retrait")
    }
    /// Le code vient de Finance, après l'exécution — jamais fabriqué ici.
    public static var cashOutTokenLater: String {
        t("finance.cashout.token_later",
          "Le code de retrait est émis par le service financier après confirmation, et ne s'affiche qu'une seule fois.")
    }
    public static func cashOutCodeExpires(_ time: String) -> String {
        String(format: t("finance.cashout.code_expires", "Valable jusqu'à %@"), time)
    }
    public static var cashOutConfirmRemittance: String {
        t("finance.cashout.confirm_remittance", "J'ai reçu les espèces")
    }
    public static var cashOutReportIncident: String {
        t("finance.cashout.report_incident", "Signaler un problème")
    }
    public static var cashOutRemitted: String {
        t("finance.cashout.remitted", "Remise confirmée. Le compte se met à jour dès que le service financier l'enregistre.")
    }
    /// Code consommé, espèces pas encore remises : **ni retrait abouti, ni échec**.
    public static var cashOutAwaitingSettlement: String {
        t("finance.cashout.awaiting_settlement",
          "Le code a été utilisé. Le retrait sera confirmé une fois les espèces remises.")
    }
    public static var cashOutStepIssue: String {
        t("finance.cashout.step_issue", "Obtenir le code")
    }
    public static var cashOutStepShow: String {
        t("finance.cashout.step_show", "Présenter le code à l'agent")
    }
    public static var cashOutStepShowDetail: String {
        t("finance.cashout.step_show_detail", "Il ne s'affiche qu'une fois. Ne le partagez avec personne d'autre.")
    }
    public static var cashOutStepCash: String {
        t("finance.cashout.step_cash", "Recevoir les espèces")
    }
    public static var cashOutIncidentOpened: String {
        t("finance.cashout.incident_opened", "Incident signalé. Le support reprend le dossier.")
    }
    public static var cashOutRevoked: String { t("finance.cashout.revoked", "Code révoqué.") }
    public static var cashOutRevokeFailed: String {
        t("finance.cashout.revoke_failed",
          "La révocation a échoué. Le code est peut-être toujours utilisable — contactez le support.")
    }
    public static var cashOutSecrecy: String {
        t("finance.cashout.secrecy",
          "Ne communiquez ce code qu'à l'agent, au moment du retrait.")
    }
    public static var cashOutExpired: String {
        t("finance.cashout.expired", "Ce code a expiré.")
    }

    // MARK: Factures (ch. 21)

    public static var billTitle: String { t("finance.bill.title", "Payer une facture") }
    public static var billSearch: String { t("finance.bill.search", "Rechercher un facturier") }
    public static var billNoBiller: String {
        t("finance.bill.no_biller", "Aucun facturier disponible dans votre pays.")
    }
    public static var billAmountDue: String { t("finance.bill.amount_due", "Montant dû") }
    public static var billArrears: String { t("finance.bill.arrears", "Arriérés") }
    public static var billStale: String {
        t("finance.bill.stale", "Cette facture a été lue il y a un moment. Actualisez avant de payer.")
    }
    public static var billRefresh: String { t("finance.bill.refresh", "Actualiser") }
    public static var billLookup: String { t("finance.bill.lookup", "Rechercher la facture") }
    public static var billPay: String { t("finance.bill.pay", "Payer") }
    public static var billPartialHint: String {
        t("finance.bill.partial_hint", "Ce facturier accepte un paiement partiel.")
    }
    /// Le serveur a répondu, et le compte n'a pas d'opération.
    public static var historyEmpty: String {
        t("finance.history.empty", "Aucune opération pour le moment.")
    }
    /// Pas de relevé à lire. Distinct d'un compte vide : le relevé vient du
    /// serveur, et rien n'est agrégé ici pour combler son absence.
    public static var historyUnavailable: String {
        t("finance.history.unavailable", "Le relevé n'est pas disponible pour le moment.")
    }
    public static var billDueDate: String { t("finance.bill.due_date", "Échéance") }
    /// Quand la facture a été lue au facturier. Un montant peut avoir changé
    /// depuis : l'écran le dit plutôt que de laisser croire à une lecture live.
    public static var billReadAt: String { t("finance.bill.read_at", "Relevé") }
    public static var billReference: String { t("finance.bill.reference", "Référence") }
    /// Le bouton porte le montant : ce qu'on confirme se lit sur ce qu'on presse.
    public static func billPayAmount(_ amount: String) -> String {
        String(format: t("finance.bill.pay_amount", "Payer %@"), amount)
    }

    // MARK: Recharge (ch. 23)

    public static var topUpTitle: String { t("finance.topup.title", "Recharger") }
    public static var topUpNumber: String { t("finance.topup.number", "Numéro") }
    public static var topUpNoProduct: String {
        t("finance.topup.no_product", "Aucun forfait disponible pour ce numéro.")
    }
    public static var topUpOrder: String { t("finance.topup.order", "Commander") }
    public static var topUpAllSucceeded: String {
        t("finance.topup.all_succeeded", "Toutes les recharges ont abouti.")
    }
    public static var topUpAllFailed: String {
        t("finance.topup.all_failed", "Aucune recharge n'a abouti.")
    }
    public static var topUpUndetermined: String {
        t("finance.topup.undetermined",
          "L'issue d'au moins une ligne est inconnue. Vérifiez avant de relancer.")
    }
    public static var topUpRetryFailed: String {
        t("finance.topup.retry_failed", "Relancer les lignes en échec")
    }
    public static func topUpPartial(_ ok: Int, _ ko: Int) -> String {
        let format = t("finance.topup.partial", "%1$@ recharge(s) abouties, %2$@ en échec.")
        return format
            .replacingOccurrences(of: "%1$@", with: "\(ok)")
            .replacingOccurrences(of: "%2$@", with: "\(ko)")
    }

    // MARK: Step-up (§52)

    public static var stepUpTitle: String {
        t("finance.stepup.title", "Confirmation de sécurité")
    }
    public static var stepUpAuthenticate: String {
        t("finance.stepup.authenticate", "S'authentifier")
    }
    public static var stepUpUnavailable: String {
        t("finance.stepup.unavailable",
          "Aucun moyen d'authentification n'est disponible sur cet appareil.")
    }
    public static var stepUpLevelUnavailable: String {
        t("finance.stepup.level_unavailable",
          "Le niveau de sécurité requis n'est pas disponible ici. Un autre chemin vous sera proposé.")
    }
    public static var stepUpLockedOut: String {
        t("finance.stepup.locked_out",
          "Trop de tentatives. Réessayez plus tard.")
    }
    public static var stepUpFailed: String {
        t("finance.stepup.failed", "L'authentification a échoué.")
    }
    public static var stepUpReasonWithdraw: String {
        t("finance.stepup.reason.withdraw", "Confirmez votre identité pour retirer de votre épargne.")
    }
    public static var stepUpReasonRemittance: String {
        t("finance.stepup.reason.remittance", "Confirmez votre identité pour financer cet envoi.")
    }
    public static var stepUpReasonCredit: String {
        t("finance.stepup.reason.credit", "Confirmez votre identité pour accepter cette offre de crédit.")
    }
    public static var stepUpReasonInvestment: String {
        t("finance.stepup.reason.investment", "Confirmez votre identité pour passer cet ordre.")
    }
    public static var stepUpReasonOrder: String {
        t("finance.stepup.reason.order", "Confirmez votre identité pour payer cette commande.")
    }

    public static var stepUpReasonCashOut: String {
        t("finance.stepup.reason.cashout",
          "Confirmez votre identité pour obtenir un code de retrait.")
    }
    public static var stepUpReasonPayment: String {
        t("finance.stepup.reason.payment",
          "Confirmez votre identité pour autoriser ce paiement.")
    }

    // MARK: Reçus (ch. 24)

    public static var receiptTitle: String { t("finance.receipt.title", "Reçu") }
    public static var receiptLoading: String {
        t("finance.receipt.loading", "Récupération du reçu…")
    }
    public static var receiptUnavailable: String {
        t("finance.receipt.unavailable", "Aucun reçu disponible pour cette opération.")
    }
    public static var receiptProvisional: String {
        t("finance.receipt.provisional",
          "Reçu provisoire — l'opération n'est pas encore définitive.")
    }
    public static var receiptExpiredLink: String {
        t("finance.receipt.expired_link", "Ce lien a expiré. Demandez-en un nouveau.")
    }
    public static var receiptOpen: String { t("finance.receipt.open", "Ouvrir le reçu") }
    public static var receiptShare: String { t("finance.receipt.share", "Partager") }
    public static var receiptNotShareable: String {
        t("finance.receipt.not_shareable", "Ce reçu ne peut pas être partagé.")
    }
    public static var receiptRefresh: String { t("finance.receipt.refresh", "Demander un nouveau lien") }

    // MARK: QR (ch. 22)

    public static var qrTitle: String { t("finance.qr.title", "Scanner un code") }
    public static var qrTorch: String { t("finance.qr.torch", "Lampe") }
    public static var qrTorchOn: String { t("finance.qr.torch_on", "Allumée") }
    public static var qrTorchOff: String { t("finance.qr.torch_off", "Éteinte") }
    public static var qrAimHint: String {
        t("finance.qr.aim", "Placez le code dans le cadre")
    }
    public static var qrResolving: String {
        t("finance.qr.resolving", "Vérification du code…")
    }
    public static var qrCameraDenied: String {
        t("finance.qr.camera_denied",
          "L'accès à la caméra est nécessaire pour scanner un code.")
    }
    public static var qrOpenSettings: String {
        t("finance.qr.open_settings", "Ouvrir les réglages")
    }
    public static var qrQuarantine: String {
        t("finance.qr.quarantine",
          "Ce code provient d'une source externe. Vérifiez le bénéficiaire avant de payer.")
    }
    public static var qrExpired: String { t("finance.qr.expired", "Ce code a expiré.") }
    public static var qrNotPayable: String {
        t("finance.qr.not_payable", "Ce code n'autorise aucun paiement.")
    }
    public static var qrContinue: String { t("finance.qr.continue", "Continuer") }

    // MARK: Litige (ch. 25)

    public static var disputeTitle: String { t("finance.dispute.title", "Signaler un problème") }
    public static var disputeReason: String { t("finance.dispute.reason", "Motif") }
    public static var disputeDescription: String {
        t("finance.dispute.description", "Décrivez ce qui s'est passé")
    }
    public static var disputeConsent: String {
        t("finance.dispute.consent",
          "J'accepte que ces informations soient partagées avec le partenaire financier concerné.")
    }
    public static var disputePrefilled: String {
        t("finance.dispute.prefilled", "Informations reprises automatiquement")
    }
    public static var disputeSubmit: String { t("finance.dispute.submit", "Envoyer le signalement") }
    public static var disputeUrgent: String {
        t("finance.dispute.urgent", "Ce motif est traité en priorité.")
    }

    // MARK: Bloc 5

    public static var remittanceTitle: String { t("finance.remittance.title", "Envoyer à l'étranger") }
    public static var remittanceNoCorridor: String {
        t("finance.remittance.no_corridor", "Aucune destination disponible depuis votre pays.")
    }
    public static var remittanceCorridor: String { t("finance.remittance.corridor", "Destination") }
    public static var remittanceDelivery: String { t("finance.remittance.delivery", "Mode de réception") }
    public static var remittanceReceives: String { t("finance.remittance.receives", "Le bénéficiaire reçoit") }
    public static var remittanceEstimated: String { t("finance.remittance.estimated", "Délai estimé") }
    public static var remittanceFunding: String { t("finance.remittance.funding", "Financer l'envoi") }
    public static var remittanceFundingMethod: String {
        t("finance.remittance.funding_method", "Payer avec")
    }
    public static var remittanceFundingWallet: String {
        t("finance.remittance.funding.wallet", "Solde du portefeuille")
    }
    public static var remittanceFundingBank: String {
        t("finance.remittance.funding.bank", "Compte bancaire")
    }
    public static var remittanceFundingCard: String {
        t("finance.remittance.funding.card", "Carte enregistrée")
    }
    public static var remittanceFundingNote: String {
        t("finance.remittance.funding_note",
          "L'argent n'est engagé qu'à cette étape. Avant, l'envoi reste un brouillon.")
    }
    public static var remittanceFunded: String {
        t("finance.remittance.funded", "Envoi financé — transmission au partenaire…")
    }

    // MARK: - Envoi international — suivi (ch. 36)

    public static var remittanceState: String { t("finance.remittance.state", "État") }
    public static var remittancePickup: String {
        t("finance.remittance.pickup", "Référence de retrait")
    }
    public static var remittanceUpdatedAt: String {
        t("finance.remittance.updated_at", "Mis à jour")
    }
    public static var remittanceProof: String {
        t("finance.remittance.proof", "Preuve de remise")
    }
    public static var remittanceRefresh: String {
        t("finance.remittance.refresh", "Actualiser le suivi")
    }
    public static var remittanceRefundPending: String {
        t("finance.remittance.refund_pending", "Un remboursement est en cours de traitement.")
    }
    public static var remittanceCancel: String { t("finance.remittance.cancel", "Annuler l'envoi") }
    public static var remittanceCancelConfirmTitle: String {
        t("finance.remittance.cancel_confirm_title", "Annuler cet envoi ?")
    }
    public static var remittanceCancelConfirmDetail: String {
        t("finance.remittance.cancel_confirm_detail",
          "Le bénéficiaire ne recevra rien et les fonds vous sont rendus. Cette action est définitive.")
    }
    /// Format à une chaîne : l'heure limite.
    public static var remittanceCancellableUntil: String {
        t("finance.remittance.cancellable_until", "Annulable jusqu'à %@.")
    }
    public static var remittanceNotCancellable: String {
        t("finance.remittance.not_cancellable", "Cet envoi n'est plus annulable.")
    }

    public static var remittanceStateDraft: String { t("finance.remittance.state.draft", "Brouillon") }
    public static var remittanceStateQuoted: String { t("finance.remittance.state.quoted", "Devis établi") }
    public static var remittanceStateQuoteExpired: String {
        t("finance.remittance.state.quote_expired", "Devis expiré")
    }
    public static var remittanceStateFunded: String { t("finance.remittance.state.funded", "Financé") }
    public static var remittanceStateCompliance: String {
        t("finance.remittance.state.compliance", "Vérification en cours")
    }
    public static var remittanceStateSubmitted: String {
        t("finance.remittance.state.submitted", "Transmis au partenaire")
    }
    public static var remittanceStateProcessing: String {
        t("finance.remittance.state.processing", "Traitement par le partenaire")
    }
    public static var remittanceStateReadyForPickup: String {
        t("finance.remittance.state.ready_for_pickup", "Prêt à être retiré")
    }
    public static var remittanceStateDelivered: String {
        t("finance.remittance.state.delivered", "Remis au bénéficiaire")
    }
    public static var remittanceStateFailed: String { t("finance.remittance.state.failed", "Échec") }
    public static var remittanceStateReturned: String { t("finance.remittance.state.returned", "Retourné") }
    public static var remittanceStateRefundPending: String {
        t("finance.remittance.state.refund_pending", "Remboursement en cours")
    }
    public static var remittanceStateRefunded: String {
        t("finance.remittance.state.refunded", "Remboursé")
    }
    public static var remittanceStateBlocked: String { t("finance.remittance.state.blocked", "Bloqué") }
    public static var remittanceStateCancelled: String { t("finance.remittance.state.cancelled", "Annulé") }

    public static var remittanceCancellable: String {
        t("finance.remittance.cancellable", "Annulable pendant un temps limité après l'envoi.")
    }

    public static var fxTitle: String { t("finance.fx.title", "Convertir") }
    public static var fxNoWallet: String {
        t("finance.fx.no_wallet", "Aucun portefeuille disponible.")
    }
    public static var fxFrom: String { t("finance.fx.from", "De") }
    public static var fxTo: String { t("finance.fx.to", "Vers") }
    public static var fxRate: String { t("finance.fx.rate", "Taux appliqué") }
    public static var fxReferenceRate: String { t("finance.fx.reference_rate", "Taux de référence") }
    public static var fxMargin: String { t("finance.fx.margin", "Marge") }
    public static var fxStaleBalance: String {
        t("finance.fx.stale_balance", "Solde daté. Actualisez avant de convertir.")
    }
    public static var fxConvert: String { t("finance.fx.convert", "Convertir") }
    public static var fxIndicative: String {
        t("finance.fx.indicative", "Cotation indicative — non exécutable.")
    }

    public static var creditTitle: String { t("finance.credit.title", "Crédit") }
    public static var creditNoProduct: String {
        t("finance.credit.no_product", "Aucune offre de crédit disponible.")
    }
    public static var creditSimulate: String { t("finance.credit.simulate", "Simuler") }
    public static var creditTerm: String { t("finance.credit.term", "Durée (mois)") }
    public static var creditMonthly: String { t("finance.credit.monthly", "Mensualité") }
    public static var creditTotalCost: String { t("finance.credit.total_cost", "Coût total") }
    public static var creditRate: String { t("finance.credit.rate", "Taux effectif") }
    public static var creditIndicative: String {
        t("finance.credit.indicative",
          "Simulation indicative. Elle n'engage aucun prêteur et ne constitue pas une offre.")
    }
    public static var creditApply: String { t("finance.credit.apply", "Faire une demande") }
    public static var creditConsent: String {
        t("finance.credit.consent",
          "J'accepte que mes données soient partagées avec le prêteur pour l'étude de ma demande.")
    }

    public static var savingsTitle: String { t("finance.savings.title", "Épargne") }
    public static var savingsNoPocket: String {
        t("finance.savings.no_pocket", "Aucun compte d'épargne.")
    }
    public static var savingsGoal: String { t("finance.savings.goal", "Objectif") }
    public static var savingsFund: String { t("finance.savings.fund", "Alimenter") }
    public static var savingsWithdraw: String { t("finance.savings.withdraw", "Retirer") }
    public static var savingsLocked: String {
        t("finance.savings.locked", "Retrait indisponible avant l'échéance.")
    }
    public static var savingsPauseRule: String { t("finance.savings.pause_rule", "Suspendre") }
    public static var savingsResumeRule: String { t("finance.savings.resume_rule", "Reprendre") }
    public static var savingsRuleFailed: String {
        t("finance.savings.rule_failed", "Dernière alimentation en échec.")
    }

    public static var investmentTitle: String { t("finance.investment.title", "Investir") }
    public static var investmentNoProduct: String {
        t("finance.investment.no_product", "Aucun produit disponible.")
    }
    public static var investmentNoProfile: String {
        t("finance.investment.no_profile",
          "Votre profil investisseur doit être établi avant toute souscription.")
    }
    public static var investmentNotSuitable: String {
        t("finance.investment.not_suitable", "Ce produit ne correspond pas à votre profil.")
    }
    public static var investmentPastPerformance: String {
        t("finance.investment.past_performance",
          "Les performances passées ne préjugent pas des performances futures.")
    }
    public static var investmentRiskAck: String {
        t("finance.investment.risk_ack", "J'ai lu et compris les risques associés à ce produit.")
    }
    public static var investmentSubscribe: String { t("finance.investment.subscribe", "Souscrire") }

    public static var pfmTitle: String { t("finance.pfm.title", "Mes dépenses") }
    public static var pfmNoData: String {
        t("finance.pfm.no_data", "Aucune donnée disponible pour cette période.")
    }
    public static var pfmIncome: String { t("finance.pfm.income", "Revenus") }
    public static var pfmExpense: String { t("finance.pfm.expense", "Dépenses") }
    public static var pfmNetWorth: String { t("finance.pfm.net_worth", "Valeur nette") }
    public static var pfmBudgets: String { t("finance.pfm.budgets", "Budgets") }
    public static var pfmRecurring: String { t("finance.pfm.recurring", "Paiements récurrents") }
    public static var pfmAnomalies: String { t("finance.pfm.anomalies", "Points d'attention") }
    public static var pfmBudgetExceeded: String { t("finance.pfm.budget_exceeded", "Dépassé") }

    // MARK: Divergence

    public static var termsChangedTitle: String {
        t("finance.terms_changed.title", "Les conditions ont changé")
    }
    public static var detailSection: String { t("finance.send.detail", "Détail") }
    public static var fees: String { t("finance.send.fees", "Frais") }
    public static var taxes: String { t("finance.send.taxes", "Taxes") }
    public static var rate: String { t("finance.send.rate", "Taux") }
    public static var total: String { t("finance.send.total", "Total") }

    /// Nommer ce qui a changé, jamais « veuillez réessayer ».
    // MARK: Demande à montant libre — §17.1.e

    public static var requestOpenAmountTitle: String {
        t("finance.request.open_amount.title", "Le payeur choisit le montant")
    }

    public static func requestOpenAmountReceives(_ name: String) -> String {
        let format = t("finance.request.open_amount.receives",
                       "%@ reçoit votre demande sans montant indiqué.")
        return format.replacingOccurrences(of: "%@", with: name)
    }

    public static var requestOpenAmountChooses: String {
        t("finance.request.open_amount.chooses",
          "C'est cette personne qui saisit la somme qu'elle vous envoie.")
    }

    public static var requestOpenAmountNoDebit: String {
        t("finance.request.open_amount.no_debit",
          "Rien n'est débité tant qu'elle n'a pas confirmé. Elle peut aussi refuser.")
    }

    // MARK: Recharge

    public static var disputeOperation: String { t("finance.dispute.operation", "Opération") }
    public static var disputeObservedStatus: String { t("finance.dispute.observed_status", "Statut observé") }
    public static var disputeRevision: String { t("finance.dispute.revision", "Révision") }

    // MARK: Espèces

    public static var cashChannel: String { t("finance.cash.channel", "Canal") }

    public static func cashInChannel(_ raw: String) -> String {
        t("finance.cashin.channel_" + raw.lowercased(), raw.capitalized)
    }

    public static func cashOutChannel(_ raw: String) -> String {
        t("finance.cashout.channel_" + raw.lowercased(), raw.capitalized)
    }

    // MARK: Crédit et investissement — libellés restés en dur

    public static var creditApprovedAmount: String {
        t("finance.credit.approved_amount", "Montant approuvé")
    }

    public static var creditInsurance: String { t("finance.credit.insurance", "Assurance") }

    public static var creditTermsAccept: String {
        t("finance.credit.terms_accept", "J'accepte les conditions de cette offre")
    }

    public static var investmentRisk: String { t("finance.investment.risk", "Risque") }

    public static var topUpWhichNumber: String {
        t("finance.topup.which_number", "Quel numéro recharger ?")
    }

    public static var topUpOperatorTitle: String {
        t("finance.topup.operator_title", "L'opérateur est reconnu tout seul")
    }

    public static var topUpPortedNote: String {
        t("finance.topup.ported_note",
          "Un numéro porté garde son préfixe d'origine : seul le service sait à qui il appartient aujourd'hui.")
    }

    public static func topUpUsePeerNumber(_ number: String) -> String {
        let format = t("finance.topup.use_peer_number", "Utiliser %@")
        return format.replacingOccurrences(of: "%@", with: number)
    }

    public static func topUpFor(_ number: String, _ operatorName: String) -> String {
        let format = t("finance.topup.for", "Pour %1$@ · %2$@")
        return format
            .replacingOccurrences(of: "%1$@", with: number)
            .replacingOccurrences(of: "%2$@", with: operatorName)
    }

    /// Intitulé d'une nature de forfait.
    public static func topUpKind(_ raw: String) -> String {
        t("finance.topup.kind_" + raw.lowercased(), raw.capitalized)
    }

    public static var topUpAddNumber: String {
        t("finance.topup.add_number", "Ajouter un autre numéro")
    }

    public static func topUpRecipients(_ count: Int) -> String {
        let template = t("finance.topup.recipients", "%1$@ numéro(s)")
        return template.replacingOccurrences(of: "%1$@", with: String(count))
    }

    /// Avancement d'un lot : il part ligne par ligne, et l'écran le dit.
    public static func topUpBatchProgress(_ done: Int, _ total: Int) -> String {
        let template = t("finance.topup.batch_progress", "Ligne %1$@ sur %2$@…")
        return template
            .replacingOccurrences(of: "%1$@", with: String(done + 1))
            .replacingOccurrences(of: "%2$@", with: String(total))
    }

    /// Ce qu'un lot engage : chaque ligne est une opération à part entière.
    public static var topUpBatchNote: String {
        t("finance.topup.batch_note",
          "Chaque numéro est une recharge distincte : elles peuvent aboutir séparément.")
    }

    // MARK: Facturiers

    public static var billRecurring: String { t("finance.bill.recurring", "Récurrents") }

    public static var billNoRecurring: String {
        t("finance.bill.no_recurring", "Aucun prélèvement en place.")
    }

    public static var billNoMatch: String {
        t("finance.bill.no_match", "Aucun facturier ne correspond à cette recherche.")
    }

    public static var billNoBillerInCategory: String {
        t("finance.bill.no_biller_in_category", "Aucun facturier pour l'instant")
    }

    public static func billerCount(_ count: Int) -> String {
        let format = t("finance.bill.biller_count", "%d facturier(s)")
        return format.replacingOccurrences(of: "%d", with: String(count))
    }

    public static func billNextOn(_ date: String) -> String {
        let format = t("finance.bill.next_on", "Prochaine échéance le %@")
        return format.replacingOccurrences(of: "%@", with: date)
    }

    public static var recipientTo: String { t("finance.recipient.to", "À") }

    public static var sendFrom: String { t("finance.send.from", "Depuis") }

    public static var flowDiscardDetail: String {
        t("finance.flow.discard_detail",
          "Le montant et le motif saisis seront perdus. Aucun argent n'a été envoyé.")
    }
    public static var flowDiscardDetailGeneric: String {
        t("finance.flow.discard_detail_generic",
          "Votre saisie sera perdue. Rien n'a encore été envoyé.")
    }

    public static var sourceVerificationPending: String {
        t("finance.source.verification_pending", "Vérification en cours")
    }

    /// Titre d'une soumission dont l'issue est inconnue. Ni « envoyé », ni
    /// « échoué » : les deux seraient une affirmation que le client ne peut pas
    /// faire.
    /// Titre commun d'une opération dont l'issue est inconnue.
    public static var flowVerifyingTitle: String {
        t("finance.flow.verifying_title", "Vérification de l'opération")
    }

    public static var flowCheckAgain: String {
        t("finance.flow.check_again", "Vérifier de nouveau")
    }

    /// Pourquoi renvoyer la requête ne paie pas deux fois.
    public static var flowCheckAgainSafe: String {
        t("finance.flow.check_again_safe",
          "Sans risque de payer deux fois : l'opération d'origine est reconnue.")
    }

    public static var sendVerifyingTitle: String {
        t("finance.send.verifying_title", "Vérification de votre envoi")
    }

    public static var sendYourBalance: String {
        t("finance.send.your_balance", "Votre solde")
    }

    /// Intitulé du bouton d'envoi, montant compris.
    public static func sendAmountAction(_ amount: String) -> String {
        let format = t("finance.send.amount_action", "Envoyer %@")
        return format.replacingOccurrences(of: "%@", with: amount)
    }

    public static func termsChangedDetail(_ names: [String]) -> String {
        let joined = names.joined(separator: ", ")
        let format = t("finance.terms_changed.detail",
                       "Ont changé : %@. Vérifiez avant de confirmer.")
        return format.replacingOccurrences(of: "%@", with: joined)
    }

    public static func decisionFieldName(_ raw: String) -> String {
        switch raw {
        case "amount":                return t("finance.field.amount", "le montant")
        case "currency":              return t("finance.field.currency", "la devise")
        case "fee":                   return t("finance.field.fee", "les frais")
        case "exchangeRate":          return t("finance.field.rate", "le taux")
        case "recipient":             return t("finance.field.recipient", "le bénéficiaire")
        case "recipientVerification": return t("finance.field.verification",
                                               "la vérification du bénéficiaire")
        case "compliance":            return t("finance.field.compliance",
                                               "les contrôles de conformité")
        default:                      return t("finance.field.operation", "l'opération")
        }
    }
}

// MARK: - Full-page finance presentation
extension FinanceStrings {
    static var flowAmountTitle: String { t("finance.flow.amount_title", "Quel montant ?") }
    static var flowReview: String { t("finance.flow.review", "Récapitulatif") }
    static var flowReviewTitle: String { t("finance.flow.review_title", "Prêt à envoyer ?") }
    static var flowReturn: String { t("finance.flow.return", "Retour à la conversation") }
    static var flowDiscard: String { t("finance.flow.discard", "Abandonner ce brouillon ?") }
    static var flowDiscardAction: String { t("finance.flow.discard_action", "Abandonner") }
    static var flowKeepEditing: String { t("finance.flow.keep_editing", "Continuer la saisie") }
    static var flowSubmittedDetail: String {
        t("finance.flow.submitted_detail", "L'envoi a été transmis. Son résultat final n'est pas encore confirmé sur cet écran. Conservez cette référence pour le suivi.")
    }
}

extension FinanceStrings {
    static var flowExecutionUnavailable: String { t("finance.flow.execution.unavailable", "Le paiement depuis cet écran n’est pas encore disponible. Aucun argent n’a été envoyé.") }
}


extension FinanceStrings {
    static var flowBubbleFailed: String { t("finance.flow.bubble_failed", "L’opération a été soumise, mais sa carte n’a pas pu être ajoutée à la conversation.") }
    static var flowShareInChat: String { t("finance.flow.share_in_chat", "Ajouter à la conversation") }
}


extension FinanceStrings {
    static var flowScanAgain: String { t("finance.flow.scan_again", "Scanner à nouveau") }
}

// MARK: - Erreurs financières, traduites

extension FinanceStrings {

    /// Message utilisateur d'une `FinanceError`, **dans la langue de l'app**.
    ///
    /// Ordre de priorité — voir `FinanceErrorExplanations` :
    /// 1. **le message rédigé par le serveur** pour cet échec, dans la langue
    ///    envoyée en `Accept-Language` ;
    /// 2. **la raison précise d'un refus de l'app** — session à revalider, pays
    ///    fermé, confirmation non autorisée — plutôt qu'un « indisponible » vague ;
    /// 3. notre phrase traduite, quand rien de plus précis n'est connu (pas de
    ///    réseau, délai dépassé) ou pour une issue incertaine, qui garde la nôtre ;
    /// 4. la phrase française de CoreKit, en dernier repli.
    ///
    /// `FinanceError.userMessage` vit dans CoreKit, qui ne voit pas TranslationKit :
    /// ses phrases sont en français, et s'affichaient telles quelles dans une
    /// interface anglaise.
    static func errorMessage(_ error: FinanceError) -> String {
        switch FinanceErrorExplanations.shared.explanation(for: error) {
        case .server(let text)?:      return text
        case .refusal(let refusal)?:  return refusalMessage(refusal)
        case nil:                     break
        }
        switch error {
        case .unauthorized:           return t("finance.error.unauthorized", error.userMessage)
        case .forbidden:              return t("finance.error.forbidden", error.userMessage)
        // Un motif fourni par le serveur est déjà rédigé pour l'utilisateur.
        case .complianceBlocked(let reason?): return reason
        case .complianceBlocked(nil): return t("finance.error.compliance_blocked", error.userMessage)
        case .recipientUnresolved(let reason):
            return t("finance.error.recipient_\(reason.rawValue.lowercased())", error.userMessage)
        case .executionPermitExpired: return t("finance.error.execution_permit_expired", error.userMessage)
        case .executionPermitConsumed: return t("finance.error.execution_permit_consumed", error.userMessage)
        case .confirmationStale:      return t("finance.error.confirmation_stale", error.userMessage)
        case .capabilityUnavailable:  return t("finance.error.capability_unavailable", error.userMessage)
        case .expired:                return t("finance.error.expired", error.userMessage)
        case .duplicate:              return t("finance.error.duplicate", error.userMessage)
        case .conflict:               return t("finance.error.conflict", error.userMessage)
        case .timeoutUnknown:         return t("finance.error.timeout_unknown", error.userMessage)
        case .networkUnavailable:     return t("finance.error.network_unavailable", error.userMessage)
        case .providerUnavailable:    return t("finance.error.provider_unavailable", error.userMessage)
        // Le nom de champ est technique : on ne le montre pas.
        case .validation:             return t("finance.error.validation", "Certaines informations sont incorrectes.")
        case .server:                 return t("finance.error.server", error.userMessage)
        }
    }

    /// La raison d'un refus décidé par l'app, dans les mots des bandeaux de session.
    static func refusalMessage(_ refusal: FinanceWriteRefusal) -> String {
        switch refusal {
        case .sessionUnavailable:  return sessionRestrictionDetail(.unavailable)
        case .countryClosed:       return sessionRestrictionDetail(.countryClosed)
        case .serviceSuspended:    return sessionRestrictionDetail(.serviceSuspended)
        case .safeMode:            return sessionRestrictionDetail(.safeMode)
        case .sessionLocked:       return sessionRestrictionDetail(.sessionLocked)
        case .paymentsDisabled:    return sessionRestrictionDetail(.paymentsDisabled)
        case .confirmationDenied:
            return t("finance.error.confirmation_denied",
                     "Votre session ne permet pas de confirmer un paiement pour le moment.")
        case .highRiskUnavailable:
            return t("finance.error.high_risk_unavailable",
                     "Cette opération est temporairement bloquée par mesure de sécurité.")
        }
    }

    static var sendFailedTitle: String { t("finance.send.failed_title", "Paiement non effectué") }
    static var referenceCopy: String { t("finance.reference.copy", "Copier la référence") }
    static var referenceCopied: String { t("finance.reference.copied", "Référence copiée") }
}

// MARK: - Détail d'une opération

extension FinanceStrings {

    /// Titre d'une opération dont l'issue n'est pas encore établie. Dit ce qui
    /// est vrai — pas confirmé — plutôt qu'un « Vérification… » qui se lit
    /// comme une formalité avant la réussite.
    static var objectUnconfirmedTitle: String {
        t("finance.object.unconfirmed_title", "Paiement pas encore confirmé")
    }
    static var objectUnconfirmedDetail: String {
        t("finance.object.unconfirmed_detail",
          "Nous vérifions auprès du service de paiement. Ne renvoyez pas ce paiement : cette page se mettra à jour dès que nous saurons.")
    }
    static var objectInProgressDetail: String {
        t("finance.object.in_progress_detail", "Ce paiement est en cours de traitement. Ne le renvoyez pas.")
    }
    static var objectNote: String { t("finance.object.note", "Motif") }
}

extension FinanceStrings {
    /// Titre du dialogue de refus. Dit que le geste s'arrête, sans affirmer
    /// qu'une opération a échoué — c'est le message qui le précise.
    static var errorDialogTitle: String { t("finance.error.dialog_title", "Impossible de continuer") }
}
