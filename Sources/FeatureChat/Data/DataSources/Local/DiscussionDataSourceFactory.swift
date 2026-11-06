//
//  DiscussionDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

enum DiscussionDataSourceFactory {

    static func create(
        store: any DatabaseRepositoryProtocol,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> LocalDiscussionDataSourceProtocol {
        let preferenceDataSource = ChatPreferenceDataSourceFactory.create(store: store)
        return GRDBDiscussionDataSource(
            store: store,
            fieldCrypto: fieldCrypto,
            preferenceDataSource: preferenceDataSource
        )
    }
}
