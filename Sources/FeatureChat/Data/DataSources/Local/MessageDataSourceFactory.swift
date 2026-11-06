//
//  MessageDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class MessageDataSourceFactory {

    static func create(
        store: any DatabaseRepositoryProtocol,
        fieldEncryptionService: any FieldEncryptionServiceProtocol
    ) -> LocalMessageDataSourceProtocol {
        GRDBMessageDataSource(
            store: store,
            fieldEncryptionService: fieldEncryptionService
        )
    }
}
