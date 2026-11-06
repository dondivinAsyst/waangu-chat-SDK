//
//  GroupJoinRequestDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

enum GroupJoinRequestDataSourceFactory {
    static func makeDataSource(
        store: any DatabaseRepositoryProtocol
    ) -> LocalGroupJoinRequestDataSourceProtocol {
        GRDBGroupJoinRequestDataSource(store: store)
    }
}
