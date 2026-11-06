//
//  ContactSyncStateDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

enum ContactSyncStateDataSourceFactory {

    static func create(
        store: any DatabaseRepositoryProtocol
    ) -> LocalContactSyncStateDataSourceProtocol {
        GRDBContactSyncStateDataSource(store: store)
    }
}
