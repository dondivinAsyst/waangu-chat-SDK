//
//  SecureFinancialActionGate.swift
//  CoreKit
//
//  Porte des actions sensibles — Bloc 6, §22.
//

import Foundation

/// Autorise — ou refuse — une action financière sensible.
///
/// Le §22 énumère les gestes qui doivent y passer : paiement marchand, gel et
/// dégel de carte, remplacement, provisioning, gros montant, paiement
/// international, rétrofacturation, action sur un bénéficiaire, décaissement
/// de collecte.
///
/// **La décision appartient au backend.** Cette porte transporte un contexte de
/// risque et rapporte un verdict ; elle ne calcule aucun score. Un client qui
/// évaluerait lui-même le risque évaluerait sans connaître ni le cumul, ni
/// l'historique, ni la juridiction — et un appareil compromis mentirait sur son
/// propre verdict.
public protocol SecureFinancialActionGate: Sendable {

    func authorize(
        action: FinancialAction,
        context: RiskContext
    ) async -> AuthorizationDecision
}

// MARK: - Actions

/// Les gestes qui exigent une autorisation explicite.
///
/// Liste **fermée**. Une action libre laisserait ajouter un geste sensible sans
/// passer par cette revue — et c'est exactement ainsi qu'un chemin non gardé
/// apparaît.
public enum FinancialAction: Sendable, Hashable {

    case merchantPayment(merchantID: String, amount: Money)
    case cardFreeze(cardID: String)
    case cardUnfreeze(cardID: String)
    case cardReplacement(cardID: String, reason: CardReplacementReason)
    case cardProvisioning(cardID: String)
    case largePayment(amount: Money)
    case internationalPayment(corridorID: String, amount: Money)
    case chargeback(transactionID: String)
    case beneficiarySensitive(beneficiaryID: String)
    case collectionDisbursement(campaignID: String, amount: Money)

    /// Le geste déplace de l'argent.
    ///
    /// Sépare ce qui coûte de ce qui protège : geler une carte n'engage rien,
    /// la dégeler la remet en circulation, mais aucun des deux ne débite.
    public var movesMoney: Bool {
        switch self {
        case .merchantPayment, .largePayment, .internationalPayment,
             .collectionDisbursement:
            return true
        case .cardFreeze, .cardUnfreeze, .cardReplacement, .cardProvisioning,
             .chargeback, .beneficiarySensitive:
            return false
        }
    }

    /// Le geste **réduit** l'exposition de l'utilisateur.
    ///
    /// Le gel de carte est le seul cas : c'est le geste qu'on fait en
    /// découvrant une fraude, et lui imposer la même friction qu'un paiement
    /// coûte les secondes pendant lesquelles la carte reste utilisable.
    public var reducesExposure: Bool {
        if case .cardFreeze = self { return true }
        return false
    }

    /// Identifiant stable, pour l'audit et la corrélation.
    public var auditKey: String {
        switch self {
        case .merchantPayment:        return "action.merchant_payment"
        case .cardFreeze:             return "action.card_freeze"
        case .cardUnfreeze:           return "action.card_unfreeze"
        case .cardReplacement:        return "action.card_replacement"
        case .cardProvisioning:       return "action.card_provisioning"
        case .largePayment:           return "action.large_payment"
        case .internationalPayment:   return "action.international_payment"
        case .chargeback:             return "action.chargeback"
        case .beneficiarySensitive:   return "action.beneficiary_sensitive"
        case .collectionDisbursement: return "action.collection_disbursement"
        }
    }
}

// MARK: - Contexte de risque

/// Ce que le client peut **rapporter** sur les circonstances d'un geste.
///
/// Des signaux, pas un jugement. Le backend les pondère avec ce qu'il est seul
/// à savoir — cumul sur la période, historique du bénéficiaire, règles du pays.
public struct RiskContext: Sendable, Hashable, Codable {

    /// Liaison de l'appareil au compte, établie à l'enrôlement.
    public let deviceBindingID: String

    /// Signaux d'intégrité — jailbreak, root, débogueur attaché.
    ///
    /// Rapportés, jamais interprétés localement : un appareil compromis peut
    /// falsifier ce signal, mais le rapporter reste utile à la corrélation.
    public let integritySignals: [String]

    /// L'appareil est-il connu du compte ?
    public let isKnownDevice: Bool

    /// Le bénéficiaire a-t-il déjà été payé ? Établi par le backend, transporté
    /// ici pour que la porte n'ait pas à le redemander.
    public let isFirstTimeCounterparty: Bool

    /// Le geste part-il d'un lien reçu plutôt que d'un parcours dans l'app ?
    ///
    /// Un paiement lancé depuis un lien externe n'a pas la même présomption
    /// qu'un paiement composé dans un écran.
    public let originatedFromExternalLink: Bool

    public let correlationID: CorrelationId
    public let observedAt: Date

    public init(deviceBindingID: String, integritySignals: [String] = [],
                isKnownDevice: Bool, isFirstTimeCounterparty: Bool = false,
                originatedFromExternalLink: Bool = false,
                correlationID: CorrelationId, observedAt: Date) {
        self.deviceBindingID = deviceBindingID
        self.integritySignals = integritySignals
        self.isKnownDevice = isKnownDevice
        self.isFirstTimeCounterparty = isFirstTimeCounterparty
        self.originatedFromExternalLink = originatedFromExternalLink
        self.correlationID = correlationID
        self.observedAt = observedAt
    }

    /// Des signaux méritent d'être remontés avec insistance.
    ///
    /// N'autorise ni ne refuse rien : sert à ce que l'interface prévienne, et à
    /// ce que le backend reçoive le contexte plutôt que de le deviner.
    public var warrantsAttention: Bool {
        !integritySignals.isEmpty || !isKnownDevice || originatedFromExternalLink
    }
}

// MARK: - Verdict

/// Ce que la porte répond.
///
/// Quatre issues distinctes plutôt qu'un booléen : « refusé » et « il manque
/// une authentification » appellent des réactions opposées, et les confondre
/// ferait abandonner un geste que l'utilisateur pouvait accomplir.
public enum AuthorizationDecision: Sendable, Equatable {

    /// Autorisé tel quel.
    case allowed

    /// Autorisé **après** satisfaction d'un niveau d'authentification.
    case requiresStepUp(level: StepUpLevel, reasonKey: String)

    /// Refusé, avec son motif. Réessayer ne changera rien.
    case denied(reasonKey: String)

    /// Le backend n'a pas tranché — indisponible, hors délai.
    ///
    /// **N'est pas une autorisation.** Un silence n'autorise rien, et le
    /// distinguer d'un refus permet à l'interface de proposer de réessayer
    /// plutôt que d'annoncer une décision qui n'a pas été prise.
    case undetermined(reasonKey: String)

    /// Le geste peut partir **sans autre condition**.
    public var permitsImmediateExecution: Bool { self == .allowed }

    /// Le niveau exigé, s'il y en a un.
    public var requiredStepUpLevel: StepUpLevel? {
        if case .requiresStepUp(let level, _) = self { return level }
        return nil
    }
}

// MARK: - Défaut fermé

/// Refuse toute action sensible.
///
/// Rend `.undetermined` plutôt que `.denied` : sans backend, aucune décision
/// n'a été prise, et prétendre à un refus ferait afficher un motif que
/// personne n'a formulé.
///
/// **Une exception, motivée** : le gel de carte passe. C'est le seul geste qui
/// *réduit* l'exposition — le bloquer par indisponibilité laisserait une carte
/// compromise active pendant une panne, ce qui est précisément le pire moment.
public struct ClosedFinancialActionGate: SecureFinancialActionGate {

    public init() {}

    public func authorize(action: FinancialAction,
                          context: RiskContext) async -> AuthorizationDecision {
        action.reducesExposure
            ? .allowed
            : .undetermined(reasonKey: "finance.gate.unavailable")
    }
}
