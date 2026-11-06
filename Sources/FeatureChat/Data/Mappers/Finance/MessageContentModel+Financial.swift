//
//  MessageContentModel+Financial.swift
//  FeatureChat
//
//  Écriture d'une carte financière dans le contenu persisté d'un message.
//

import Foundation
import WaanguCoreKit

extension MessageContentModel {

    /// Recopie une carte financière dans les colonnes `payment*` / `financial*`.
    ///
    /// **Un seul endroit** écrit ces champs : la construction d'un message
    /// (`MessageModelMapper.buildContent`) et la projection d'une révision
    /// serveur sur un message existant (Bloc 1, lot 1.4) passent toutes deux
    /// par ici. Deux copies de cette liste divergeraient au premier champ ajouté,
    /// et la bulle relue de la base ne serait plus celle qu'on a écrite.
    ///
    /// Relu par `MessageModelMapper.buildFinancial(from:)`.
    mutating func applyFinancial(_ payload: FinancialCardPayload) {
        // Les deux représentations sont écrites — voir `MessageContentModel`.
        // Le `Double` garde une version antérieure de l'application capable de
        // lire cette ligne ; le décimal porte la valeur exacte.
        paymentAmount = NSDecimalNumber(decimal: payload.amount).doubleValue
        paymentAmountDecimal = NSDecimalNumber(decimal: payload.amount).description
        paymentCurrency = payload.currency
        paymentStatus = payload.status.rawValue
        // `paymentRef` reste l'identifiant d'objet financier : c'est la colonne
        // qui existait déjà et sur laquelle `transactionId` était mappé.
        paymentRef = payload.reference.id
        financialObjectType = payload.reference.type.rawValue
        financialObjectVersion = payload.reference.version
        financialCorrelationId = payload.reference.correlationID.value
        financialCounterpartyName = payload.counterpartyName
        financialFeeAmount = payload.feeAmount.map { NSDecimalNumber(decimal: $0).doubleValue }
        financialFeeAmountDecimal = payload.feeAmount.map { NSDecimalNumber(decimal: $0).description }
        financialVerification = payload.verification.rawValue
        financialRefreshedAt = payload.lastRefreshedAt.timeIntervalSince1970
    }
}
