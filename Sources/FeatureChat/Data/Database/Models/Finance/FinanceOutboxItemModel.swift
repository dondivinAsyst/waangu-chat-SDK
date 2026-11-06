//
//  FinanceOutboxItemModel.swift
//  FeatureChat
//
//  Ligne GRDB d'une action financière différée — Bloc 1, lot 2.3.
//

import Foundation
import WaanguCoreKit

/// Une action de la file financière, conservée entre deux lancements.
///
/// Porte l'item **tel quel**, clé d'idempotence comprise : une action restaurée
/// doit repartir sous la clé de sa création, jamais sous une clé neuve — une clé
/// neuve ferait exécuter une seconde fois ce que le serveur a peut-être déjà
/// exécuté. La clé elle-même reste enregistrée dans le trousseau par
/// `IdempotencyKeyPreserving` ; la ligne ne fait que dire quelle action la porte.
///
/// Rangée par compte, comme `FinancialObjectModel` : les actions d'un compte ne
/// sont ni relues ni rejouées par un autre.
public struct FinanceOutboxItemModel: Storable {

    public static let namespace = "chat"
    public static let schemaVersion = 1
    public static let indexedFields = ["accountId"]

    /// Identifiant de l'item — c'est aussi l'identifiant d'opération sous lequel
    /// sa clé est enregistrée.
    public let id: String
    public let accountId: String
    public let item: ChatFinanceOutboxItem

    public init(accountID: String, item: ChatFinanceOutboxItem) {
        self.id = item.id
        self.accountId = accountID
        self.item = item
    }
}
