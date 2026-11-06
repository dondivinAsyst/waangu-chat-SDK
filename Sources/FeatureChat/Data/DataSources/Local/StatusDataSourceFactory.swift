//
//  StatusDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class StatusDataSourceFactory {

    static func create(
        store: any DatabaseRepositoryProtocol,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> LocalStatusDataSourceProtocol {
        GRDBStatusDataSource(store: store, fieldCrypto: fieldCrypto)
    }
}
