//
//  FinancialCardRegistry.swift
//  FeatureChat
//
//  Point d'extension unique des cartes financières — tâche 6.1.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §5.4.

import SwiftUI
import WaanguCoreKit

/// Résout un type d'objet financier vers sa carte.
///
/// **Le fil conversationnel n'est modifié qu'une fois.** `BubbleView` délègue ici
/// pour `.ISMONEY` ; chaque nouveau type de carte s'enregistre, sans qu'aucune
/// ligne de la timeline ne bouge. C'est l'exigence du §17 du prompt d'origine :
/// « le fil conversationnel central ne doit pas être modifié pour chaque nouveau
/// type ».
///
/// Registre plutôt que `switch` : un `switch` exhaustif sur `FinancialObjectType`
/// obligerait à toucher la timeline à chaque ajout, et forcerait à écrire les dix
/// cartes avant de pouvoir en afficher une seule.
@MainActor
public enum FinancialCardRegistry {

    public typealias Renderer = @MainActor (FinancialCardPayload) -> AnyView

    private static var renderers: [FinancialObjectType: Renderer] = [:]

    /// Enregistre le rendu d'un type. Un second enregistrement remplace le premier.
    public static func register(_ type: FinancialObjectType, renderer: @escaping Renderer) {
        renderers[type] = renderer
    }

    /// Enregistre les cartes livrées avec le Bloc 1.
    ///
    /// Appelé au montage du module. Idempotent — un second appel réenregistre les
    /// mêmes rendus.
    public static func registerBuiltInCards() {
        // Argent qui change de mains entre deux parties : même carte, le titre
        // suit la nature (et le sens, pour un paiement).
        for type in [FinancialObjectType.payment, .merchantPayment, .remittance,
                     .cashIn, .cashOut, .payout] {
            register(type) { AnyView(PaymentCardView(payload: $0)) }
        }
        register(.moneyRequest)    { AnyView(MoneyRequestCardView(payload: $0)) }
        // Achat de service : facture, crédit téléphonique, forfait data.
        for type in [FinancialObjectType.bill, .airtime, .dataBundle] {
            register(type) { AnyView(BillCardView(payload: $0)) }
        }
        register(.refund)          { AnyView(RefundCardView(payload: $0)) }
        register(.dispute)         { AnyView(DisputeCardView(payload: $0)) }
        register(.splitBill)       { AnyView(SplitBillCardView(payload: $0)) }
        register(.fxQuote)         { AnyView(FXQuoteCardView(payload: $0)) }

        // `UnknownFinancialCard` reste le repli pour un type émis par un client
        // plus récent — Android ou Web — que cette version ne connaît pas.
    }

    /// Vue d'une carte.
    ///
    /// Un type non enregistré ne produit ni `EmptyView` ni crash : il tombe sur
    /// une carte générique qui renvoie vers le Wallet. Un message financier reçu
    /// d'un client plus récent — d'Android, par exemple — reste donc visible et
    /// actionnable, au lieu de laisser un trou dans la conversation.
    static func view(for payload: FinancialCardPayload) -> AnyView {
        renderers[payload.reference.type]?(payload)
            ?? AnyView(UnknownFinancialCard(payload: payload))
    }

    /// Nombre de types enregistrés — utilisé par les tests.
    static var registeredCount: Int { renderers.count }

    /// Vide le registre. Réservé aux tests.
    static func reset() { renderers.removeAll() }
}

// MARK: - Sens du message

/// Sens du message qui porte la carte — envoyé ou reçu.
///
/// **Pourquoi l'environnement et non un paramètre.** `Renderer` prend la charge
/// et rien d'autre ; ajouter un argument obligerait à toucher les dix cartes
/// enregistrées, et toute carte écrite plus tard, pour une information qu'une
/// seule d'entre elles lit aujourd'hui. La bulle le pose une fois, les cartes
/// qui en ont besoin le lisent.
///
/// `nil` hors d'un fil — un aperçu, une page de détail — où « envoyé » et
/// « reçu » n'ont pas de sens : la carte s'en tient alors à son libellé neutre.
struct FinanceCardDirectionKey: EnvironmentKey {
    static let defaultValue: MessageDirection? = nil
}

extension EnvironmentValues {
    var financeCardDirection: MessageDirection? {
        get { self[FinanceCardDirectionKey.self] }
        set { self[FinanceCardDirectionKey.self] = newValue }
    }
}

// MARK: - Répondre à une demande depuis la bulle

/// Ce qu'une carte de demande peut faire — remonté à la conversation.
///
/// La carte ne présente rien elle-même : une feuille ou un dialogue posé
/// depuis une cellule de liste serait lié à cette cellule, et disparaîtrait
/// avec elle au défilement. Elle émet l'intention ; la conversation présente.
struct FinanceRequestActions {
    /// Ouvre le parcours de paiement — un devis, puis confirmation explicite.
    let pay: @MainActor (MoneyRequestOverlay) -> Void
    /// Demande confirmation, puis refuse.
    let decline: @MainActor (MoneyRequestOverlay) -> Void
    let remind: @MainActor (MoneyRequestOverlay) -> Void
    /// Demande confirmation, puis annule sa propre demande.
    let cancel: @MainActor (MoneyRequestOverlay) -> Void
    /// Émet un lien de paiement vers la demande — jamais exécutable.
    let issueLink: @MainActor (MoneyRequestOverlay) -> Void
}

extension Notification.Name {
    /// Une demande vient de changer par une action de cet appareil — payée,
    /// refusée, annulée. `object` : la référence de la demande (`String`).
    ///
    /// Après un paiement, la demande reste souvent `OPEN` : seule la part du
    /// payeur change. Le statut de la carte ne bouge donc pas, et sans ce
    /// signal la carte ne se relisait pas — « Payer » restait affiché.
    static let financeRequestDidChange = Notification.Name("waangu.finance.requestDidChange")
}

struct FinanceRequestActionsKey: EnvironmentKey {
    static let defaultValue: FinanceRequestActions? = nil
}

extension EnvironmentValues {
    /// `nil` hors d'une conversation : la carte n'affiche alors aucun bouton.
    var financeRequestActions: FinanceRequestActions? {
        get { self[FinanceRequestActionsKey.self] }
        set { self[FinanceRequestActionsKey.self] = newValue }
    }
}
